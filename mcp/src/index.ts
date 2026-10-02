// Cloudflare Worker entry. /mcp is an OAuth-protected resource (workers-oauth-provider): MCP clients discover the
// authorization server, register, send the user through Google sign-in + consent on this site, and call /mcp with
// a bearer token. Every MCP request re-checks the user's access in D1, so revoking or ending a subscription takes
// effect immediately. The MCP server itself stays stateless (fresh server + transport per request, JSON responses).
import { OAuthProvider } from "@cloudflare/workers-oauth-provider";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { publicUrl, type AuthProps, type Env } from "./env";
import { createServer } from "./server";
import { siteHandler } from "./site";
import { checkAccess } from "./users";

export type { Env } from "./env";

export const SCOPES = ["mcp:read"];

const CORS: Record<string, string> = {
	"Access-Control-Allow-Origin": "*",
	"Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
	"Access-Control-Allow-Headers": "Content-Type, Accept, Authorization, Mcp-Session-Id, Mcp-Protocol-Version, Last-Event-ID",
	"Access-Control-Expose-Headers": "Mcp-Session-Id, Mcp-Protocol-Version, WWW-Authenticate",
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
	if (request.method === "GET" || request.method === "DELETE") {
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
		return handleMcp(request);
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
		});
		providers.set(origin, p);
	}
	return p;
}

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		if (request.method === "OPTIONS" && new URL(request.url).pathname.startsWith("/mcp")) {
			return withCors(new Response(null, { status: 204 }));
		}
		return provider(env).fetch(request, env, ctx);
	},
};
