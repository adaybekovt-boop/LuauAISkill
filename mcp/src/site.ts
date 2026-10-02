// The site (default handler): Google sign-in, account page, the OAuth /authorize endpoint with its consent page,
// and a token-guarded admin endpoint for manual subscription grants.
import { AuthorizationError, CimdFetchError } from "@cloudflare/workers-oauth-provider";
import { googleReady, oauthEnabled, publicUrl, type AuthProps, type Env } from "./env";
import { finishGoogleLogin, LoginError, safeReturnTo, startGoogleLogin } from "./google";
import { meta } from "./generated/data.js";
import { accountPage, consentPage, errorPage, landingPage, page, subscriptionRequiredPage } from "./pages";
import { cookie, createSession, csrfToken, destroySession, getSession, randomToken, validCsrf, type Session } from "./session";
import { checkAccess, getUser, hasActiveSubscription, policy, setSubscriptionByEmail, upsertGoogleUser } from "./users";
import { SERVER_NAME } from "./server";
import { billingReady, BillingError, cancelCheckout, changePrice, startCheckout, startPortal, subscriptionInfo, validAmount, webhook } from "./billing";
import { createKey, listKeys, revokeKey } from "./keys";
import { freeLimit, minuteLimit, usageInfo } from "./usage";
import { lookup } from "./api";

function redirect(location: string, headers?: Headers): Response {
	const h = headers ?? new Headers();
	h.set("Location", location);
	h.set("Cache-Control", "no-store");
	return new Response(null, { status: 302, headers: h });
}

function json(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body, null, 2), {
		status,
		headers: { "Content-Type": "application/json; charset=utf-8", "Access-Control-Allow-Origin": "*" },
	});
}

function sameToken(a: string, b: string): boolean {
	const x = new TextEncoder().encode(a);
	const y = new TextEncoder().encode(b);
	let diff = x.length ^ y.length;
	for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
	return diff === 0;
}

function rememberOptions(env: Env, session: Session) {
	return { secret: env.CONSENT_SECRET, subject: session.userId };
}

async function finish(env: Env, request: Parameters<Env["OAUTH_PROVIDER"]["completeAuthorization"]>[0]["request"], session: Session, headers: Headers) {
	const props: AuthProps = { userId: session.userId, email: session.email };
	const { redirectTo } = await env.OAUTH_PROVIDER.completeAuthorization({
		request,
		userId: session.userId,
		metadata: { email: session.email },
		scope: request.scope,
		props,
	});
	return redirect(redirectTo, headers);
}

async function authorizeGet(request: Request, env: Env): Promise<Response> {
	const oauth = env.OAUTH_PROVIDER;
	const authRequest = await oauth.parseAuthRequest(request);
	const session = await getSession(env, request);
	if (!session) {
		const url = new URL(request.url);
		return redirect(`/login?return_to=${encodeURIComponent(url.pathname + url.search)}`);
	}
	const access = await checkAccess(env, session.userId);
	if (!access.ok) {
		if (access.reason === "subscription_required") return page("Subscription required", subscriptionRequiredPage(session.email), 403);
		return redirect(`/login?return_to=${encodeURIComponent(new URL(request.url).pathname + new URL(request.url).search)}`);
	}
	if (await oauth.isConsentRemembered(request, authRequest, rememberOptions(env, session))) {
		return finish(env, authRequest, session, new Headers());
	}
	const details = await oauth.describeConsent(authRequest);
	const consent = await oauth.beginConsent(authRequest);
	return page("Connect to LuauAISkill", consentPage(details, consent.handle, session.email), 200, consent.headers);
}

async function authorizePost(request: Request, env: Env): Promise<Response> {
	const oauth = env.OAUTH_PROVIDER;
	const session = await getSession(env, request);
	if (!session) return page("Sign-in required", errorPage("Your session expired. Connect again from Claude."), 401);
	const form = await request.formData().catch(() => new FormData());
	const handle = String(form.get("handle") ?? "");
	if (form.get("decision") !== "approve") {
		const denied = await oauth.denyConsent(request, handle);
		return new Response(null, { status: 302, headers: denied.headers });
	}
	const access = await checkAccess(env, session.userId);
	if (!access.ok) return page("Subscription required", subscriptionRequiredPage(session.email), 403);
	const approved = await oauth.approveConsent(request, handle, {
		scope: form.getAll("scope").map(String),
		...(form.get("remember") ? { remember: rememberOptions(env, session) } : {}),
	});
	return finish(env, approved.request, session, approved.headers);
}

async function authorize(request: Request, env: Env): Promise<Response> {
	try {
		if (request.method === "GET") return await authorizeGet(request, env);
		if (request.method === "POST") return await authorizePost(request, env);
		return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, POST" } });
	} catch (error) {
		if (error instanceof AuthorizationError && error.redirectTo) return Response.redirect(error.redirectTo, 302);
		if (error instanceof AuthorizationError || error instanceof CimdFetchError) {
			const message = error instanceof AuthorizationError ? error.description ?? "Invalid request." : "This app could not be verified.";
			return page("Cannot connect", errorPage(message), 400);
		}
		throw error;
	}
}

async function googleCallback(request: Request, env: Env): Promise<Response> {
	try {
		const { profile, returnTo, clearCookie } = await finishGoogleLogin(env, request);
		const user = await upsertGoogleUser(env, profile.sub, profile.email, profile.name);
		const headers = new Headers();
		headers.append("Set-Cookie", clearCookie);
		headers.append("Set-Cookie", await createSession(env, { userId: user.id, email: user.email }));
		return redirect(returnTo, headers);
	} catch (error) {
		if (error instanceof LoginError) return page("Sign-in failed", errorPage(error.message), 400,
			new Headers({ "Set-Cookie": cookie("__Host-luau-login", "", 0) }));
		throw error;
	}
}

async function account(request: Request, env: Env, newKey?: string): Promise<Response> {
	const session = await getSession(env, request);
	if (!session) return redirect("/login?return_to=/account");
	const user = await getUser(env, session.userId);
	if (!user) return redirect("/login?return_to=/account");
	const access = await checkAccess(env, user.id);
	if (user.disabled) return page("Account unavailable", errorPage("This account is disabled."), 403);
	const sub = await subscriptionInfo(env, user.id);
	const grants = await env.OAUTH_PROVIDER?.listUserGrants(user.id, { limit: 20, cursor: new URL(request.url).searchParams.get("cursor") ?? undefined });
	const connections = await Promise.all((grants?.items ?? []).map(async g => ({
		id: g.id, name: (await env.OAUTH_PROVIDER.lookupClient(g.clientId).catch(() => null))?.clientName || "MCP client",
	})));
	const status = new URL(request.url).searchParams.get("billing");
	return page(
		"Account",
		accountPage({
			email: user.email,
			policy: policy(env),
			subscription: hasActiveSubscription(user) ? "active" : user.subscription_status,
			periodEnd: user.subscription_period_end,
			allowed: access.ok,
			mcpUrl: `${publicUrl(env)}/mcp`,
			csrf: await csrfToken(env, request), operationId: randomToken(16), usage: await usageInfo(env, user), billingReady: billingReady(env),
			amount: sub?.amount ?? validAmount(new URL(request.url).searchParams.get("amount")) ?? 700, cancelAtPeriodEnd: Boolean(sub?.cancel_at_period_end),
			keys: await listKeys(env, user.id), grants: connections, nextCursor: grants?.cursor, newKey,
			notice: status === "success" ? "Checkout completed. Subscription access activates after payment confirmation; refresh this page shortly."
				: status === "canceled" ? "Checkout canceled. No new subscription was activated." : status === "updated" ? "Price updated for future invoices." : undefined,
		}),
	);
}

async function accountAction(request: Request, env: Env, path: string): Promise<Response> {
	if (request.method !== "POST") return new Response("Method not allowed", { status: 405, headers: { Allow: "POST" } });
	const session = await getSession(env, request);
	if (!session) return page("Sign-in required", errorPage("Please sign in again."), 401);
	const user = await getUser(env, session.userId);
	if (!user || user.disabled) return page("Account unavailable", errorPage("Account unavailable."), 403);
	const form = await request.formData().catch(() => new FormData());
	if (!await validCsrf(env, request, form)) return page("Request rejected", errorPage("This form expired. Reload your account page and try again."), 403);
	if (path === "/logout") return redirect("/", new Headers({ "Set-Cookie": await destroySession(env, request) }));
	if (path === "/account/keys") {
		const token = await createKey(env, user.id, String(form.get("label") ?? "MCP client"));
		return token ? account(request, env, token) : page("Key limit", errorPage("Revoke an unused key before creating another."), 409);
	}
	if (path === "/account/keys/revoke") await revokeKey(env, user.id, String(form.get("id") ?? ""));
	else if (path === "/account/connections/revoke") {
		const id = String(form.get("id") ?? "");
		if (!id || id.length > 200) return page("Invalid connection", errorPage("Invalid connection."), 400);
		await env.DB.prepare("INSERT INTO revoked_grants (id, user_id) VALUES (?1, ?2) ON CONFLICT DO NOTHING").bind(id, user.id).run();
		await env.OAUTH_PROVIDER.revokeGrant(id, user.id);
	} else if (path.startsWith("/billing/")) {
		if (!billingReady(env)) return page("Payments unavailable", errorPage("Payments are not configured yet."), 503);
		try {
			if (path === "/billing/checkout/cancel") { await cancelCheckout(env, user.id); return redirect("/account"); }
			if (path === "/billing/portal") return redirect(await startPortal(env, user.id));
			const amount = validAmount(form.get("amount"));
			if (amount === null) return page("Invalid amount", errorPage("Choose a whole-dollar monthly price between $3 and $20."), 400);
			const operationId = String(form.get("operation_id") ?? "");
			if (path === "/billing/checkout") return redirect(await startCheckout(env, user.id, amount));
			if (path === "/billing/price") {
				if (!/^[A-Za-z0-9_-]{22}$/.test(operationId)) return page("Invalid form", errorPage("Reload your account page and try again."), 400);
				await changePrice(env, user.id, amount, operationId); return redirect("/account?billing=updated");
			}
		} catch (error) {
			if (error instanceof BillingError) return page("Payment request failed", errorPage(error.message), 409);
			throw error;
		}
	} else if (path !== "/account/keys/revoke") return json({ error: "not found" }, 404);
	return redirect("/account");
}

async function admin(request: Request, env: Env, path: string): Promise<Response> {
	const auth = request.headers.get("Authorization") ?? "";
	if (!env.ADMIN_TOKEN || !auth.startsWith("Bearer ") || !sameToken(auth.slice(7), env.ADMIN_TOKEN)) {
		return json({ error: "not found" }, 404);
	}
	if (path === "/admin/subscription" && request.method === "POST") {
		const body = (await request.json().catch(() => null)) as { email?: unknown; status?: unknown; period_end?: unknown } | null;
		const email = typeof body?.email === "string" ? body.email.trim() : "";
		const status = body?.status === "active" || body?.status === "none" || body?.status === "canceled" ? body.status : null;
		const periodEnd = typeof body?.period_end === "number" && Number.isFinite(body.period_end) ? body.period_end : null;
		if (!email || !status) return json({ error: "expected {email, status: active|none|canceled, period_end?: ms}" }, 400);
		const updated = await setSubscriptionByEmail(env, email, status, periodEnd);
		return json({ updated }, updated ? 200 : 404);
	}
	return json({ error: "not found" }, 404);
}

export const siteHandler = {
	async fetch(request: Request, env: Env): Promise<Response> {
		const url = new URL(request.url);
		const path = url.pathname;
		if (path === "/api/config" && request.method === "GET") return json({
			google_ready: googleReady(env), billing_ready: billingReady(env), auth_mode: oauthEnabled(env) ? "oauth" : "public-preview",
			mcp_url: `${publicUrl(env)}/mcp`, free_calls_per_week: freeLimit(env), calls_per_minute: minuteLimit(env),
		});
		if (path === "/api/demo" && request.method === "POST") {
			const body = await request.json().catch(() => null) as {query?: unknown} | null;
			if (typeof body?.query !== "string" || !body.query.trim() || body.query.length > 200) return json({error: "A query of 1–200 characters is required."}, 400);
			return json({ text: lookup(body.query).text });
		}
		if (path === "/billing/webhook") return request.method === "POST" ? webhook(request, env) : new Response("Method not allowed", { status: 405 });
		if (path === "/subscribe" && request.method === "GET") {
			const amount = validAmount(url.searchParams.get("amount")) ?? 700;
			const session = await getSession(env, request);
			if (!session) return redirect(`/login?return_to=${encodeURIComponent(`/account?amount=${amount}`)}`);
			return redirect(`/account?amount=${amount}`);
		}
		if (path === "/authorize") return authorize(request, env);
		if (path === "/auth/google/callback" && request.method === "GET") return googleCallback(request, env);
		if (path === "/login" && request.method === "GET") return startGoogleLogin(env, safeReturnTo(url.searchParams.get("return_to")));
		if (path === "/logout" || path.startsWith("/account/") || path.startsWith("/billing/")) return accountAction(request, env, path);
		if (path === "/account" && request.method === "GET") return account(request, env);
		if (path.startsWith("/admin/")) return admin(request, env, path);
		if (path === "/health") {
			return json({
				name: SERVER_NAME,
				mcp_endpoint: `${publicUrl(env)}/mcp`,
				transport: "streamable-http (stateless, JSON responses)",
				auth: oauthEnabled(env) ? "oauth (Google sign-in)" : "none (public preview)",
				google_ready: googleReady(env), billing_ready: billingReady(env),
				status: "ok",
				access_policy: policy(env),
				skill_version: meta.skillVersion,
				commit: meta.commit,
				built_at: meta.builtAt,
				engine_api: meta.apiClientVersion,
				counts: meta.counts,
			});
		}
		if (path === "/") {
			const session = await getSession(env, request);
			return session ? redirect("/account") : page("LuauAISkill", landingPage());
		}
		return json({ error: "not found", mcp_endpoint: `${publicUrl(env)}/mcp` }, 404);
	},
};
