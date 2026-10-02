import type { OAuthHelpers } from "@cloudflare/workers-oauth-provider";

export interface Env {
	/** OAuth grants/tokens/clients (workers-oauth-provider) and site sessions/login state (prefixed keys). */
	OAUTH_KV: KVNamespace;
	/** Registered users and their subscription status. */
	DB: D1Database;
	/** Public origin, e.g. https://luaumcp.tklabsskill.site (no trailing slash). */
	PUBLIC_URL: string;
	/** "registered" (any signed-in user) or "subscribed" (active subscription required). */
	ACCESS_POLICY?: string;
	GOOGLE_CLIENT_ID: string;
	GOOGLE_CLIENT_SECRET: string;
	/** 32+ random characters: signs remembered consent and site sessions. */
	CONSENT_SECRET: string;
	/** Optional bearer token for /admin/* (manual subscription grants until a payment provider is wired). */
	ADMIN_TOKEN?: string;
	/** Injected by OAuthProvider into the default handler. */
	OAUTH_PROVIDER: OAuthHelpers;
}

/** What completeAuthorization() stores with each grant; MCP requests see it as ctx.props. */
export interface AuthProps extends Record<string, unknown> {
	userId: string;
	email: string;
}

export function publicUrl(env: Env): string {
	return env.PUBLIC_URL.replace(/\/+$/, "");
}
