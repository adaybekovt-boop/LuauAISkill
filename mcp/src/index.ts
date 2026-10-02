// Cloudflare Worker entry: stateless MCP over Streamable HTTP at /mcp (a fresh server + transport per request,
// JSON responses, no sessions, no Durable Objects). Everything served is read-only data built from the repo.
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";
import { meta } from "./generated/data.js";
import { createServer, SERVER_NAME } from "./server";

export interface Env {
	/** Optional. When set (wrangler secret put MCP_TOKEN), /mcp requires `Authorization: Bearer <token>`. */
	MCP_TOKEN?: string;
}

const CORS: Record<string, string> = {
	"Access-Control-Allow-Origin": "*",
	"Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
	"Access-Control-Allow-Headers": "Content-Type, Accept, Authorization, Mcp-Session-Id, Mcp-Protocol-Version, Last-Event-ID",
	"Access-Control-Expose-Headers": "Mcp-Session-Id, Mcp-Protocol-Version",
	"Access-Control-Max-Age": "86400",
};

function withCors(res: Response): Response {
	const out = new Response(res.body, res);
	for (const [k, v] of Object.entries(CORS)) out.headers.set(k, v);
	return out;
}

function json(body: unknown, status = 200): Response {
	return withCors(
		new Response(JSON.stringify(body, null, 2), { status, headers: { "Content-Type": "application/json; charset=utf-8" } }),
	);
}

// Constant-time comparison so the token can't be guessed byte by byte from response timing.
function sameToken(a: string, b: string): boolean {
	const enc = new TextEncoder();
	const x = enc.encode(a);
	const y = enc.encode(b);
	let diff = x.length ^ y.length;
	for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
	return diff === 0;
}

async function handleMcp(request: Request, env: Env): Promise<Response> {
	if (env.MCP_TOKEN) {
		const auth = request.headers.get("Authorization") ?? "";
		const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
		if (!sameToken(token, env.MCP_TOKEN)) {
			return withCors(
				new Response(JSON.stringify({ jsonrpc: "2.0", error: { code: -32001, message: "Unauthorized" }, id: null }), {
					status: 401,
					headers: { "Content-Type": "application/json", "WWW-Authenticate": 'Bearer realm="luau-skill"' },
				}),
			);
		}
	}
	if (request.method === "GET" || request.method === "DELETE") {
		// Stateless server: no standalone SSE stream and no sessions to terminate.
		return withCors(
			new Response(JSON.stringify({ jsonrpc: "2.0", error: { code: -32000, message: "Method not allowed" }, id: null }), {
				status: 405,
				headers: { "Content-Type": "application/json", Allow: "POST, OPTIONS" },
			}),
		);
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

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		const url = new URL(request.url);
		if (request.method === "OPTIONS") return withCors(new Response(null, { status: 204 }));
		if (url.pathname === "/mcp" || url.pathname === "/mcp/") return handleMcp(request, env);
		// Clients are often given the bare origin: accept MCP POSTs at "/" too (GET "/" stays the info page).
		if (url.pathname === "/" && request.method === "POST") return handleMcp(request, env);
		if (url.pathname === "/" || url.pathname === "/health") {
			return json({
				name: SERVER_NAME,
				mcp_endpoint: `${url.origin}/mcp`,
				transport: "streamable-http (stateless, JSON responses)",
				auth: env.MCP_TOKEN ? "bearer token required" : "none",
				skill_version: meta.skillVersion,
				commit: meta.commit,
				built_at: meta.builtAt,
				engine_api: meta.apiClientVersion,
				counts: meta.counts,
			});
		}
		return json({ error: "not found", mcp_endpoint: `${url.origin}/mcp` }, 404);
	},
};
