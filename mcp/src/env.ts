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
	/** Auto keeps the existing public MCP running until Google is configured; oauth always fails closed. */
	AUTH_MODE?: "auto" | "oauth" | "public";
	FREE_CALLS_PER_WEEK?: string;
	CALLS_PER_MINUTE?: string;
	SITE_URL?: string;
	EDGE_RATE_LIMITER?: RateLimit;
	STRIPE_SECRET_KEY?: string;
	STRIPE_WEBHOOK_SECRET?: string;
	STRIPE_PRODUCT_ID?: string;
	GOOGLE_CLIENT_ID: string;
	GOOGLE_CLIENT_SECRET: string;
	/** Optional independent 32+ character consent key. Otherwise derived from the Google client secret. */
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
	grantId?: string;
}

export function publicUrl(env: Env): string {
	return new URL(env.PUBLIC_URL || "https://luaumcp.tklabsskill.site").origin;
}

export function googleReady(env: Env): boolean {
	return Boolean(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET && env.CONSENT_SECRET?.length >= 32);
}

export function oauthEnabled(env: Env): boolean {
	return env.AUTH_MODE === "oauth" || (env.AUTH_MODE !== "public" && googleReady(env));
}
