// Site sessions: an opaque random cookie; KV holds only its SHA-256, so a KV read can't be replayed as a cookie.
import type { Env } from "./env";

export const SESSION_COOKIE = "__Host-luau-session";
const SESSION_TTL = 30 * 24 * 3600;

export interface Session {
	userId: string;
	email: string;
}

export function randomToken(bytes = 32): string {
	const b = crypto.getRandomValues(new Uint8Array(bytes));
	return btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256(text: string): Promise<string> {
	const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
	return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

export function readCookie(request: Request, name: string): string | null {
	const header = request.headers.get("Cookie") ?? "";
	for (const part of header.split(";")) {
		const [k, ...v] = part.trim().split("=");
		if (k === name) return v.join("=");
	}
	return null;
}

export function cookie(name: string, value: string, maxAge: number): string {
	return `${name}=${value}; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=${maxAge}`;
}

export async function createSession(env: Env, session: Session): Promise<string> {
	const token = randomToken();
	await env.OAUTH_KV.put(`site-session:${await sha256(token)}`, JSON.stringify(session), { expirationTtl: SESSION_TTL });
	return cookie(SESSION_COOKIE, token, SESSION_TTL);
}

export async function getSession(env: Env, request: Request): Promise<Session | null> {
	const token = readCookie(request, SESSION_COOKIE);
	if (!token) return null;
	const raw = await env.OAUTH_KV.get(`site-session:${await sha256(token)}`);
	return raw ? (JSON.parse(raw) as Session) : null;
}

export async function destroySession(env: Env, request: Request): Promise<string> {
	const token = readCookie(request, SESSION_COOKIE);
	if (token) await env.OAUTH_KV.delete(`site-session:${await sha256(token)}`);
	return cookie(SESSION_COOKIE, "", 0);
}
