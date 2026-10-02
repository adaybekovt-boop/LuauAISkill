// OAuth gate: discovery, Google sign-in on the site, consent, token, and per-request access policy.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Browser, ORIGIN, REDIRECT, authorizeUrl, connect, ctx, google, googleSignIn, makeEnv, pkce, registerClient, rpc, worker } from "./harness.mjs";

test("unauthenticated /mcp gets a Bearer challenge pointing at resource metadata", async () => {
	const env = makeEnv();
	const r = await rpc(env, null, "tools/list");
	assert.equal(r.status, 401);
	const challenge = r.headers.get("WWW-Authenticate");
	assert.match(challenge, /^Bearer /);
	assert.match(challenge, /resource_metadata="https:\/\/mcp\.example\.test\/\.well-known\/oauth-protected-resource\/mcp"/);
});

test("discovery documents describe this server", async () => {
	const env = makeEnv();
	let res = await worker.fetch(new Request(`${ORIGIN}/.well-known/oauth-protected-resource/mcp`), env, ctx);
	assert.equal(res.status, 200);
	const prm = await res.json();
	assert.equal(prm.resource, `${ORIGIN}/mcp`);
	assert.deepEqual(prm.authorization_servers, [ORIGIN]);
	res = await worker.fetch(new Request(`${ORIGIN}/.well-known/oauth-authorization-server`), env, ctx);
	const as = await res.json();
	assert.equal(as.authorization_endpoint, `${ORIGIN}/authorize`);
	assert.equal(as.token_endpoint, `${ORIGIN}/token`);
	assert.equal(as.registration_endpoint, `${ORIGIN}/register`);
	assert.ok(as.code_challenge_methods_supported.includes("S256"));
});

test("full flow: register → Google sign-in → consent → token → MCP tools", async () => {
	const env = makeEnv();
	const { accessToken } = await connect(env);
	const r = await rpc(env, accessToken, "tools/list");
	assert.equal(r.status, 200, JSON.stringify(r.json));
	assert.ok(r.json.result.tools.some((t) => t.name === "api_lookup"));
	const call = await rpc(env, accessToken, "tools/call", { name: "api_lookup", arguments: { query: "Humanoid.LoadAnimation" } });
	assert.match(call.json.result.content[0].text, /DEPRECATED/);
	const user = env.DB.db.prepare("SELECT id, email FROM users").get();
	assert.deepEqual({ ...user }, { id: "google_1001", email: "dev@example.com" });
	assert.ok(google.calls.at(-1).code_verifier, "Google code exchange used PKCE");
});

test("authorize without a session sends the user to Google sign-in first", async () => {
	const env = makeEnv();
	const browser = new Browser(env);
	const clientId = await registerClient(browser);
	const { challenge } = await pkce();
	const res = await browser.fetch(authorizeUrl(clientId, challenge));
	assert.equal(res.status, 302);
	assert.match(res.headers.get("Location"), /^\/login\?return_to=%2Fauthorize%3F/);
});

test("denying consent returns access_denied to the client", async () => {
	const env = makeEnv();
	const browser = new Browser(env);
	await googleSignIn(browser);
	const clientId = await registerClient(browser);
	const { challenge } = await pkce();
	let res = await browser.fetch(authorizeUrl(clientId, challenge));
	const handle = /name="handle" value="([^"]+)"/.exec(await res.text())[1];
	res = await browser.fetch("/authorize", {
		method: "POST",
		headers: { "Content-Type": "application/x-www-form-urlencoded" },
		body: new URLSearchParams({ handle, decision: "deny" }),
	});
	assert.equal(res.status, 302);
	const back = new URL(res.headers.get("Location"));
	assert.equal(back.origin + back.pathname, REDIRECT);
	assert.equal(back.searchParams.get("error"), "access_denied");
});

test("consent posted from another browser (no binding cookie) is refused", async () => {
	const env = makeEnv();
	const victim = new Browser(env);
	await googleSignIn(victim);
	const clientId = await registerClient(victim);
	const { challenge } = await pkce();
	const page = await victim.fetch(authorizeUrl(clientId, challenge));
	const handle = /name="handle" value="([^"]+)"/.exec(await page.text())[1];
	const attacker = new Browser(env);
	await googleSignIn(attacker);
	const res = await attacker.fetch("/authorize", {
		method: "POST",
		headers: { "Content-Type": "application/x-www-form-urlencoded" },
		body: new URLSearchParams({ handle, decision: "approve", scope: "mcp:read" }),
	});
	assert.notEqual(res.status, 302);
});

test("Google callback with a foreign state or a bad code fails safely", async () => {
	const env = makeEnv();
	const browser = new Browser(env);
	const start = await browser.fetch("/login");
	const state = new URL(start.headers.get("Location")).searchParams.get("state");
	const other = new Browser(env); // no login cookie
	let res = await other.fetch(`/auth/google/callback?code=good-code&state=${encodeURIComponent(state)}`);
	assert.equal(res.status, 400);
	res = await browser.fetch(`/auth/google/callback?code=bad-code&state=${encodeURIComponent(state)}`);
	assert.equal(res.status, 400);
	assert.equal(env.DB.db.prepare("SELECT count(*) AS n FROM sqlite_master WHERE name = 'users'").get().n === 0 ||
		env.DB.db.prepare("SELECT count(*) AS n FROM users").get().n === 0, true);
});

test("unverified Google email is rejected", async () => {
	const env = makeEnv();
	const saved = google.profile;
	google.profile = { ...saved, email_verified: false };
	try {
		const res = await googleSignIn(new Browser(env));
		assert.equal(res.status, 400);
	} finally {
		google.profile = saved;
	}
});

test("login return_to cannot redirect off-site", async () => {
	const env = makeEnv();
	const browser = new Browser(env);
	const res = await googleSignIn(browser, "//evil.example/steal");
	assert.equal(res.status, 302);
	assert.equal(res.headers.get("Location"), "/account");
});

test("subscribed policy: no subscription → 403, admin grant → access, expiry → 403 again", async () => {
	const env = makeEnv();
	const { accessToken } = await connect(env); // registered while policy = registered
	env.ACCESS_POLICY = "subscribed";
	let r = await rpc(env, accessToken, "tools/list");
	assert.equal(r.status, 403);
	assert.match(r.json.error.message, /subscription/);

	const grant = (token, body) =>
		worker.fetch(
			new Request(`${ORIGIN}/admin/subscription`, {
				method: "POST",
				headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
				body: JSON.stringify(body),
			}),
			env,
			ctx,
		);
	assert.equal((await grant("wrong", { email: "dev@example.com", status: "active" })).status, 404);
	assert.equal((await grant("admin-secret", { email: "dev@example.com", status: "active", period_end: Date.now() + 86400000 })).status, 200);
	r = await rpc(env, accessToken, "tools/list");
	assert.equal(r.status, 200);

	await grant("admin-secret", { email: "dev@example.com", status: "active", period_end: Date.now() - 1000 });
	r = await rpc(env, accessToken, "tools/list");
	assert.equal(r.status, 403);
});

test("subscribed policy blocks the consent step for users without a subscription", async () => {
	const env = makeEnv({ ACCESS_POLICY: "subscribed" });
	const browser = new Browser(env);
	await googleSignIn(browser);
	const clientId = await registerClient(browser);
	const { challenge } = await pkce();
	const res = await browser.fetch(authorizeUrl(clientId, challenge));
	assert.equal(res.status, 403);
	assert.match(await res.text(), /Subscription required/);
});

test("site pages: landing, account, health, logout", async () => {
	const env = makeEnv();
	const browser = new Browser(env);
	let res = await browser.fetch("/");
	assert.match(await res.text(), /Sign in with Google/);
	await googleSignIn(browser);
	res = await browser.fetch("/account");
	const html = await res.text();
	assert.match(html, /dev@example\.com/);
	assert.match(html, /https:\/\/mcp\.example\.test\/mcp/);
	res = await browser.fetch("/health");
	assert.equal((await res.json()).auth, "oauth (Google sign-in)");
	res = await browser.fetch("/logout", { method: "POST" });
	assert.equal(res.status, 302);
	res = await browser.fetch("/account");
	assert.equal(res.status, 302);
	assert.match(res.headers.get("Location"), /^\/login/);
});

test("admin endpoint is invisible without ADMIN_TOKEN configured", async () => {
	const env = makeEnv({ ADMIN_TOKEN: undefined });
	const res = await worker.fetch(
		new Request(`${ORIGIN}/admin/subscription`, { method: "POST", headers: { Authorization: "Bearer " }, body: "{}" }),
		env,
		ctx,
	);
	assert.equal(res.status, 404);
});
