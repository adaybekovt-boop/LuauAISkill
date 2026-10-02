// The site (default handler): Google sign-in, account page, the OAuth /authorize endpoint with its consent page,
// and a token-guarded admin endpoint for manual subscription grants.
import { AuthorizationError, CimdFetchError } from "@cloudflare/workers-oauth-provider";
import { publicUrl, type AuthProps, type Env } from "./env";
import { finishGoogleLogin, LoginError, safeReturnTo, startGoogleLogin } from "./google";
import { meta } from "./generated/data.js";
import { accountPage, consentPage, errorPage, landingPage, page, subscriptionRequiredPage } from "./pages";
import { createSession, destroySession, getSession, type Session } from "./session";
import { checkAccess, getUser, hasActiveSubscription, policy, setSubscriptionByEmail, upsertGoogleUser } from "./users";
import { SERVER_NAME } from "./server";

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
	const form = await request.formData();
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
		if (error instanceof LoginError) return page("Sign-in failed", errorPage(error.message), 400);
		throw error;
	}
}

async function account(request: Request, env: Env): Promise<Response> {
	const session = await getSession(env, request);
	if (!session) return redirect("/login?return_to=/account");
	const user = await getUser(env, session.userId);
	if (!user) return redirect("/login?return_to=/account");
	const access = await checkAccess(env, user.id);
	return page(
		"Account",
		accountPage({
			email: user.email,
			policy: policy(env),
			subscription: hasActiveSubscription(user) ? "active" : user.subscription_status,
			periodEnd: user.subscription_period_end,
			allowed: access.ok,
			mcpUrl: `${publicUrl(env)}/mcp`,
		}),
	);
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
		if (path === "/authorize") return authorize(request, env);
		if (path === "/auth/google/callback") return googleCallback(request, env);
		if (path === "/login") return startGoogleLogin(env, safeReturnTo(url.searchParams.get("return_to")));
		if (path === "/logout" && request.method === "POST") return redirect("/", new Headers({ "Set-Cookie": await destroySession(env, request) }));
		if (path === "/account") return account(request, env);
		if (path.startsWith("/admin/")) return admin(request, env, path);
		if (path === "/health") {
			return json({
				name: SERVER_NAME,
				mcp_endpoint: `${publicUrl(env)}/mcp`,
				transport: "streamable-http (stateless, JSON responses)",
				auth: "oauth (Google sign-in)",
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
