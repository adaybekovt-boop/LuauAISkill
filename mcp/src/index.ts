// Cloudflare Worker entry. /mcp is an OAuth-protected resource (workers-oauth-provider): MCP clients discover the
// authorization server, register, send the user through Google sign-in + consent on this site, and call /mcp with
// a bearer token. Every MCP request re-checks the user's access in D1, so revoking or ending a subscription takes
// effect immediately. The MCP server itself stays stateless (fresh server + transport per request, JSON responses).
import { OAuthError, OAuthProvider } from "@cloudflare/workers-oauth-provider";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { googleReady, oauthEnabled, publicUrl, type AuthProps, type Env } from "./env";
import { createServer } from "./server";
import { siteHandler } from "./site";
import { checkAccess } from "./users";
import { refundCall, reserveCall } from "./usage";
import { keyUser } from "./keys";
import { sha256 } from "./session";

export type { Env } from "./env";

export const SCOPES = ["mcp:read"];

const CORS: Record<string, string> = {
	"Access-Control-Allow-Origin": "*",
	"Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
	"Access-Control-Allow-Headers": "Content-Type, Accept, Authorization, Mcp-Session-Id, Mcp-Protocol-Version, Last-Event-ID",
	"Access-Control-Expose-Headers": "Mcp-Session-Id, Mcp-Protocol-Version, WWW-Authenticate, Retry-After, X-Request-Id",
};

function withCors(res: Response): Response {
	const out = new Response(res.body, res);
	for (const [k, v] of Object.entries(CORS)) out.headers.set(k, v);
	return out;
}

function rpcError(status: number, code: number, message: string, extra: Record<string, string> = {}): Response {
	return withCors(
		new Response(JSON.stringify({ jsonrpc: "2.0", error: { code, message }, id: null }), {
			status,
			headers: { "Content-Type": "application/json", ...extra },
		}),
	);
}

export async function handleMcp(request: Request): Promise<Response> {
	if (request.method !== "POST") {
		// Stateless server: no standalone SSE stream and no sessions to terminate.
		return rpcError(405, -32000, "Method not allowed", { Allow: "POST, OPTIONS" });
	}
	const server = createServer();
	const transport = new WebStandardStreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
	await server.connect(transport);
	try {
		return withCors(await transport.handleRequest(request));
	} finally {
		await transport.close();
		await server.close();
	}
}

const mcpApi = {
	async fetch(request: Request, env: Env, ctx: ExecutionContext & { props?: AuthProps }): Promise<Response> {
		const props = ctx.props;
		if (!props?.userId) return rpcError(401, -32001, "Unauthorized");
		const access = await checkAccess(env, props.userId);
		if (!access.ok) {
			const message =
				access.reason === "subscription_required"
					? `An active subscription is required. Manage it at ${publicUrl(env)}/account`
					: `Access revoked. Sign in again at ${publicUrl(env)}`;
			return rpcError(403, -32002, message);
		}
		if (props.grantId && await env.DB.prepare("SELECT id FROM revoked_grants WHERE id = ?1 AND user_id = ?2")
			.bind(props.grantId, props.userId).first()) return rpcError(401, -32001, "This connection has been revoked.");
		const body = request.method === "POST" ? await request.clone().json().catch(() => null) as {method?: string; id?: unknown} | null : null;
		if (!body || body.id === undefined || !["tools/call", "resources/read"].includes(body.method ?? "")) return handleMcp(request);
		const reserved = await reserveCall(env, access.user);
		if (!reserved.ok) return rpcError(429, -32003, reserved.reason, { "Retry-After": String(reserved.retryAfter) });
		try {
			const response = await handleMcp(request);
			const result = await response.clone().json().catch(() => null) as {error?: unknown; result?: {isError?: boolean}} | null;
			if (!response.ok || result?.error || result?.result?.isError) await refundCall(env, props.userId, reserved);
			return response;
		} catch (error) {
			await refundCall(env, props.userId, reserved);
			throw error;
		}
	},
};

// The provider needs the public origin at construction; build one per origin and reuse it.
const providers = new Map<string, OAuthProvider<Env>>();

function provider(env: Env): OAuthProvider<Env> {
	const origin = publicUrl(env);
	let p = providers.get(origin);
	if (!p) {
		p = new OAuthProvider<Env>({
			apiRoute: "/mcp",
			apiHandler: mcpApi as never,
			defaultHandler: siteHandler as never,
			authorizeEndpoint: "/authorize",
			tokenEndpoint: "/token",
			clientRegistrationEndpoint: "/register",
			scopesSupported: SCOPES,
			requiredScopes: SCOPES,
			resourceMetadata: {
				resource: `${origin}/mcp`,
				authorization_servers: [origin],
				bearer_methods_supported: ["header"],
				resource_name: "LuauAISkill MCP",
			},
			clientIdMetadataDocumentEnabled: true,
			accessTokenTTL: 3600,
			refreshTokenTTL: 30 * 24 * 3600,
			tokenExchangeCallback: async ({ env, userId, grantId, props }) => {
				const access = await checkAccess(env, userId);
				if (!access.ok || await env.DB.prepare("SELECT id FROM revoked_grants WHERE id = ?1 AND user_id = ?2").bind(grantId, userId).first()) {
					throw new OAuthError("invalid_grant", { description: "Account or connection access is unavailable." });
				}
				return { accessTokenProps: { ...props, grantId } };
			},
		});
		providers.set(origin, p);
	}
	return p;
}

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		// An independent secret can be supplied, otherwise derive a domain-separated signing key from the Google secret.
		// Connecting Google requires only its client ID and secret; no additional hand setup is needed.
		if (!env.CONSENT_SECRET && env.GOOGLE_CLIENT_SECRET) {
			env = { ...env, CONSENT_SECRET: await sha256(`LuauAISkill:consent:v1:${env.GOOGLE_CLIENT_SECRET}`) };
		}
		const requestId = crypto.randomUUID();
		let response: Response;
		try {
			response = await route(request, env, ctx);
		} catch (error) {
			// Never log submitted code, headers, tokens, payment details, or upstream response bodies.
			console.error(JSON.stringify({ event: "request_failed", request_id: requestId, path: new URL(request.url).pathname,
				error: error instanceof Error ? error.name : "Error" }));
			response = rpcError(503, -32603, "Service temporarily unavailable. Please retry.", { "Retry-After": "5" });
		}
		const out = new Response(response.body, response);
		out.headers.set("X-Request-Id", requestId);
		out.headers.set("X-Content-Type-Options", "nosniff");
		out.headers.set("Referrer-Policy", "no-referrer");
		out.headers.set("Cache-Control", "no-store");
		return out;
	},
};

async function route(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
	let url = new URL(request.url);
	if (url.pathname === "/" && request.method === "POST" || url.pathname === "/mcp/") {
		url.pathname = "/mcp";
		request = new Request(url, request);
	}
	if (request.method === "OPTIONS") return withCors(new Response(null, { status: 204 }));
	if (url.pathname === "/ready" && request.method === "GET") {
		if (oauthEnabled(env)) {
			if (!googleReady(env) || !env.DB || !env.OAUTH_KV) return withCors(Response.json({ status: "unavailable" }, { status: 503 }));
			await Promise.all([env.DB.prepare("SELECT 1").first(), env.OAUTH_KV.get("readiness-check")]);
		}
		return withCors(Response.json({ status: "ready", mode: oauthEnabled(env) ? "oauth" : "public-preview" }));
	}
	const limited = request.method === "POST" || ["/login", "/auth/google/callback", "/authorize"].includes(url.pathname);
	if (limited && url.pathname !== "/billing/webhook" && env.EDGE_RATE_LIMITER) {
		const key = request.headers.get("CF-Connecting-IP") || "unknown";
		if (!(await env.EDGE_RATE_LIMITER.limit({ key })).success) return rpcError(429, -32003, "Too many requests.", { "Retry-After": "60" });
	}
	if (["POST", "PUT", "PATCH"].includes(request.method) && request.body) {
		const max = url.pathname === "/mcp" ? 1024 * 1024 : url.pathname === "/billing/webhook" ? 128000 : 16384;
		if (Number(request.headers.get("Content-Length")) > max) return rpcError(413, -32600, "Request body too large.");
		const reader = request.body.getReader();
		const chunks: Uint8Array[] = [];
		let size = 0;
		while (true) {
			const { done, value } = await reader.read();
			if (done) break;
			size += value.byteLength;
			if (size > max) { await reader.cancel(); return rpcError(413, -32600, "Request body too large."); }
			chunks.push(value);
		}
		const bytes = new Uint8Array(size);
		let offset = 0;
		for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
		request = new Request(request, { body: bytes });
	}
	if (!oauthEnabled(env)) {
		if (url.pathname === "/mcp") return handleMcp(request);
		if (url.pathname.startsWith("/.well-known/oauth-") || ["/token", "/register", "/authorize"].includes(url.pathname)) {
			return withCors(Response.json({ error: "OAuth is not enabled in public preview." }, { status: 404 }));
		}
		return siteHandler.fetch(request, env);
	}
	if (!googleReady(env) || !env.DB || !env.OAUTH_KV) return rpcError(503, -32603, "Authentication is not configured.");
	const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
	if (url.pathname === "/mcp" && token.startsWith("la_sk_")) {
		const userId = await keyUser(env, token);
		if (!userId) return rpcError(401, -32001, "API key is invalid, expired or revoked.", {
			"WWW-Authenticate": `Bearer resource_metadata="${publicUrl(env)}/.well-known/oauth-protected-resource/mcp"`,
		});
		return mcpApi.fetch(request, env, { ...ctx, props: { userId, email: "" } });
	}
	return withCors(await provider(env).fetch(request, env, ctx));
}
