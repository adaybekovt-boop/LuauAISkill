// "Sign in with Google" (OpenID Connect, authorization code + PKCE). The login state lives in KV under the hash of
// a random `state`, and the same state is pinned to the browser by a short-lived cookie, so a callback can't be
// replayed from another browser.
import { publicUrl, type Env } from "./env";
import { cookie, randomToken, readCookie, sha256 } from "./session";

export const GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
export const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
export const GOOGLE_USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo";
const LOGIN_COOKIE = "__Host-luau-login";
const LOGIN_TTL = 600;

export interface GoogleProfile {
	sub: string;
	email: string;
	name: string | null;
}

/** Only same-site relative paths may be returned to (no open redirect). */
export function safeReturnTo(value: string | null): string {
	if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) return "/account";
	return value;
}

async function s256(verifier: string): Promise<string> {
	const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
	return btoa(String.fromCharCode(...new Uint8Array(d))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function redirectUri(env: Env): string {
	return `${publicUrl(env)}/auth/google/callback`;
}

export async function startGoogleLogin(env: Env, returnTo: string): Promise<Response> {
	const state = randomToken();
	const verifier = randomToken(48);
	const nonce = randomToken(16);
	await env.OAUTH_KV.put(`google-login:${await sha256(state)}`, JSON.stringify({ verifier, nonce, returnTo }), {
		expirationTtl: LOGIN_TTL,
	});
	const url = new URL(GOOGLE_AUTH_URL);
	url.search = new URLSearchParams({
		client_id: env.GOOGLE_CLIENT_ID,
		redirect_uri: redirectUri(env),
		response_type: "code",
		scope: "openid email profile",
		state,
		nonce,
		code_challenge: await s256(verifier),
		code_challenge_method: "S256",
		prompt: "select_account",
	}).toString();
	return new Response(null, {
		status: 302,
		headers: { Location: url.toString(), "Set-Cookie": cookie(LOGIN_COOKIE, state, LOGIN_TTL), "Cache-Control": "no-store" },
	});
}

export class LoginError extends Error {}

/** Validates state (+ browser binding), exchanges the code, returns the verified Google profile. */
export async function finishGoogleLogin(
	env: Env,
	request: Request,
): Promise<{ profile: GoogleProfile; returnTo: string; clearCookie: string }> {
	const url = new URL(request.url);
	const state = url.searchParams.get("state") ?? "";
	const clearCookie = cookie(LOGIN_COOKIE, "", 0);
	if (url.searchParams.get("error")) throw new LoginError("Google sign-in was cancelled.");
	if (!state || readCookie(request, LOGIN_COOKIE) !== state) throw new LoginError("Sign-in expired or was opened in another browser.");
	const key = `google-login:${await sha256(state)}`;
	const raw = await env.OAUTH_KV.get(key);
	if (!raw) throw new LoginError("Sign-in expired. Please try again.");
	await env.OAUTH_KV.delete(key);
	const { verifier, returnTo } = JSON.parse(raw) as { verifier: string; nonce: string; returnTo: string };
	const code = url.searchParams.get("code");
	if (!code) throw new LoginError("Google did not return an authorization code.");

	const tokenRes = await fetch(GOOGLE_TOKEN_URL, {
		method: "POST",
		headers: { "Content-Type": "application/x-www-form-urlencoded" },
		body: new URLSearchParams({
			code,
			client_id: env.GOOGLE_CLIENT_ID,
			client_secret: env.GOOGLE_CLIENT_SECRET,
			redirect_uri: redirectUri(env),
			grant_type: "authorization_code",
			code_verifier: verifier,
		}),
	});
	if (!tokenRes.ok) throw new LoginError("Google rejected the sign-in. Please try again.");
	const tokens = (await tokenRes.json()) as { access_token?: string };
	if (!tokens.access_token) throw new LoginError("Google did not return an access token.");

	const infoRes = await fetch(GOOGLE_USERINFO_URL, { headers: { Authorization: `Bearer ${tokens.access_token}` } });
	if (!infoRes.ok) throw new LoginError("Could not read the Google profile.");
	const info = (await infoRes.json()) as { sub?: string; email?: string; email_verified?: boolean; name?: string };
	if (!info.sub || !info.email || info.email_verified !== true) {
		throw new LoginError("This Google account has no verified email address.");
	}
	return { profile: { sub: info.sub, email: info.email, name: info.name ?? null }, returnTo: safeReturnTo(returnTo), clearCookie };
}
