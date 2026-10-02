// Test harness: in-memory KV, a D1 shim over node:sqlite, a stubbed Google, a cookie jar, and a helper that walks
// the full OAuth flow (DCR → authorize → Google sign-in → consent → token) the way claude.ai does.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import worker from "../.test-build/index.mjs";

export const ORIGIN = "https://mcp.example.test";
export const REDIRECT = "https://claude.ai/api/mcp/auth_callback";

export class MemoryKV {
	constructor() {
		this.map = new Map();
	}
	live(key) {
		const e = this.map.get(key);
		if (!e) return null;
		if (e.expires && e.expires < Date.now()) {
			this.map.delete(key);
			return null;
		}
		return e;
	}
	async get(key, opts) {
		const e = this.live(key);
		if (!e) return null;
		const type = typeof opts === "string" ? opts : opts?.type;
		return type === "json" ? JSON.parse(e.value) : e.value;
	}
	async put(key, value, opts = {}) {
		const ttl = opts.expirationTtl ? opts.expirationTtl * 1000 : opts.expiration ? opts.expiration * 1000 - Date.now() : 0;
		this.map.set(key, { value: String(value), expires: ttl ? Date.now() + ttl : 0, metadata: opts.metadata ?? null });
	}
	async delete(key) {
		this.map.delete(key);
	}
	async list({ prefix = "", limit = 1000 } = {}) {
		const keys = [...this.map.keys()]
			.filter((k) => k.startsWith(prefix) && this.live(k))
			.sort()
			.slice(0, limit)
			.map((name) => ({ name, metadata: this.map.get(name).metadata }));
		return { keys, list_complete: true, cursor: "" };
	}
}

export class SqliteD1 {
	constructor() {
		this.db = new DatabaseSync(":memory:");
	}
	prepare(sql) {
		const db = this.db;
		const make = (params) => ({
			bind: (...args) => make(args),
			async first() {
				return db.prepare(sql).get(...params) ?? null;
			},
			async all() {
				return { results: db.prepare(sql).all(...params), success: true, meta: {} };
			},
			async run() {
				const r = db.prepare(sql).run(...params);
				return { success: true, meta: { changes: Number(r.changes) } };
			},
		});
		return make([]);
	}
	async batch(statements) {
		this.db.exec("BEGIN");
		try {
			const results = [];
			for (const statement of statements) results.push(await statement.run());
			this.db.exec("COMMIT");
			return results;
		} catch (error) {
			this.db.exec("ROLLBACK");
			throw error;
		}
	}
}

export function makeEnv(overrides = {}) {
	return {
		OAUTH_KV: new MemoryKV(),
		DB: new SqliteD1(),
		PUBLIC_URL: ORIGIN,
		ACCESS_POLICY: "registered",
		GOOGLE_CLIENT_ID: "google-client-id",
		GOOGLE_CLIENT_SECRET: "google-client-secret",
		CONSENT_SECRET: "test-consent-secret-0123456789-abcdefghij",
		ADMIN_TOKEN: "admin-secret",
		...overrides,
	};
}

const ctx = { waitUntil() {}, passThroughOnException() {} };

// Google stub: records requests, returns a verified profile for the code "good-code".
export const google = {
	profile: { sub: "1001", email: "dev@example.com", email_verified: true, name: "Dev" },
	calls: [],
};
export const stripe = { calls: [], subscriptions: new Map(), failure: false };
const realFetch = globalThis.fetch;
globalThis.fetch = async (input, init) => {
	const url = typeof input === "string" ? input : input.url;
	if (url.startsWith("https://api.stripe.com/v1/")) {
		const path = url.slice("https://api.stripe.com/v1/".length);
		const fields = Object.fromEntries(new URLSearchParams(init?.body));
		stripe.calls.push({ path, method: init?.method ?? "GET", fields });
		if (stripe.failure) return Response.json({ error: { message: "upstream secret should never be shown" } }, { status: 500 });
		if (path === "customers") return Response.json({ id: "cus_test" });
		if (path === "checkout/sessions") return Response.json({ id: "cs_test", url: "https://checkout.stripe.com/test" });
		if (path === "checkout/sessions/cs_test/expire") return Response.json({ id: "cs_test", status: "expired" });
		if (path.startsWith("subscriptions?")) return Response.json({ data: [] });
		if (path === "billing_portal/sessions") return Response.json({ url: "https://billing.stripe.com/test" });
		if (path.startsWith("subscriptions/")) return Response.json(stripe.subscriptions.get(path.split("/")[1]) ?? {}, { status: stripe.subscriptions.has(path.split("/")[1]) ? 200 : 404 });
		throw new Error(`Unhandled Stripe request: ${path}`);
	}
	if (url.startsWith("https://oauth2.googleapis.com/token")) {
		const body = new URLSearchParams(init.body);
		google.calls.push(Object.fromEntries(body));
		if (body.get("code") !== "good-code" || !body.get("code_verifier")) {
			return new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 });
		}
		return Response.json({ access_token: "google-access", id_token: "x.y.z", token_type: "Bearer" });
	}
	if (url.startsWith("https://openidconnect.googleapis.com/v1/userinfo")) {
		return Response.json(google.profile);
	}
	return realFetch(input, init);
};

export class Browser {
	constructor(env) {
		this.env = env;
		this.cookies = new Map();
	}
	async fetch(pathOrUrl, init = {}) {
		const url = pathOrUrl.startsWith("http") ? pathOrUrl : ORIGIN + pathOrUrl;
		const headers = new Headers(init.headers);
		if (this.cookies.size) headers.set("Cookie", [...this.cookies].map(([k, v]) => `${k}=${v}`).join("; "));
		const res = await worker.fetch(new Request(url, { ...init, headers, redirect: "manual" }), this.env, ctx);
		for (const c of res.headers.getSetCookie()) {
			const [pair, ...attrs] = c.split(";");
			const [k, ...v] = pair.split("=");
			const value = v.join("=");
			if (attrs.some((a) => /max-age=0\b/i.test(a.trim())) || value === "") this.cookies.delete(k.trim());
			else this.cookies.set(k.trim(), value);
		}
		return res;
	}
}

function b64url(bytes) {
	return Buffer.from(bytes).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function pkce() {
	const verifier = b64url(crypto.getRandomValues(new Uint8Array(32)));
	const challenge = b64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))));
	return { verifier, challenge };
}

export async function registerClient(browser) {
	const res = await browser.fetch("/register", {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify({
			client_name: "Claude",
			redirect_uris: [REDIRECT],
			token_endpoint_auth_method: "none",
			grant_types: ["authorization_code", "refresh_token"],
			response_types: ["code"],
		}),
	});
	assert.equal(res.status, 201, await res.clone().text());
	return (await res.json()).client_id;
}

export function authorizeUrl(clientId, challenge, state = "st-123") {
	return (
		"/authorize?" +
		new URLSearchParams({
			response_type: "code",
			client_id: clientId,
			redirect_uri: REDIRECT,
			scope: "mcp:read",
			state,
			code_challenge: challenge,
			code_challenge_method: "S256",
			resource: `${ORIGIN}/mcp`,
		})
	);
}

/** Google sign-in on the site; returns after the callback redirect. */
export async function googleSignIn(browser, returnTo = "/account", code = "good-code") {
	const start = await browser.fetch(`/login?return_to=${encodeURIComponent(returnTo)}`);
	assert.equal(start.status, 302);
	const googleUrl = new URL(start.headers.get("Location"));
	assert.equal(googleUrl.origin + googleUrl.pathname, "https://accounts.google.com/o/oauth2/v2/auth");
	const state = googleUrl.searchParams.get("state");
	return browser.fetch(`/auth/google/callback?code=${code}&state=${encodeURIComponent(state)}`);
}

export async function accountForm(browser, path, fields = {}) {
	const account = await browser.fetch("/account");
	assert.equal(account.status, 200, await account.clone().text());
	const html = await account.text();
	const csrf = /name="csrf" value="([^"]+)"/.exec(html)[1];
	const operation_id = /name="operation_id" value="([^"]+)"/.exec(html)[1];
	return browser.fetch(path, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded", Origin: ORIGIN },
		body: new URLSearchParams({ csrf, operation_id, ...fields }) });
}

/** Full claude.ai-style flow. Returns { accessToken, refreshToken, clientId, browser }. */
export async function connect(env, browser = new Browser(env)) {
	const clientId = await registerClient(browser);
	const { verifier, challenge } = await pkce();
	const authUrl = authorizeUrl(clientId, challenge);
	let res = await browser.fetch(authUrl);
	if (res.status === 302 && res.headers.get("Location").startsWith("/login")) {
		const returnTo = new URL(ORIGIN + res.headers.get("Location")).searchParams.get("return_to");
		res = await googleSignIn(browser, returnTo);
		assert.equal(res.status, 302);
		res = await browser.fetch(res.headers.get("Location"));
	}
	assert.equal(res.status, 200, "consent page");
	const html = await res.text();
	const handle = /name="handle" value="([^"]+)"/.exec(html)[1];
	res = await browser.fetch("/authorize", {
		method: "POST",
		headers: { "Content-Type": "application/x-www-form-urlencoded" },
		body: new URLSearchParams({ handle, decision: "approve", scope: "mcp:read" }),
	});
	assert.equal(res.status, 302, await res.clone().text());
	const back = new URL(res.headers.get("Location"));
	assert.equal(back.origin + back.pathname, REDIRECT);
	assert.equal(back.searchParams.get("state"), "st-123");
	const code = back.searchParams.get("code");
	res = await browser.fetch("/token", {
		method: "POST",
		headers: { "Content-Type": "application/x-www-form-urlencoded" },
		body: new URLSearchParams({
			grant_type: "authorization_code",
			code,
			redirect_uri: REDIRECT,
			client_id: clientId,
			code_verifier: verifier,
			resource: `${ORIGIN}/mcp`,
		}),
	});
	assert.equal(res.status, 200, await res.clone().text());
	const tokens = await res.json();
	return { accessToken: tokens.access_token, refreshToken: tokens.refresh_token, clientId, browser };
}

let nextId = 1;
export async function rpc(env, token, method, params = {}, path = "/mcp") {
	const headers = { "Content-Type": "application/json", Accept: "application/json, text/event-stream", "Mcp-Protocol-Version": "2025-06-18" };
	if (token) headers.Authorization = `Bearer ${token}`;
	const res = await worker.fetch(
		new Request(ORIGIN + path, { method: "POST", headers, body: JSON.stringify({ jsonrpc: "2.0", id: nextId++, method, params }) }),
		env,
		ctx,
	);
	const text = await res.text();
	let body = null;
	try {
		body = text ? JSON.parse(text) : null;
	} catch {
		body = text;
	}
	return { status: res.status, headers: res.headers, json: body };
}

export { worker, ctx };
