// End-to-end: drive the Worker's fetch handler with real MCP JSON-RPC over Streamable HTTP (no network).
import assert from "node:assert/strict";
import { test } from "node:test";
import worker from "../.test-build/index.mjs";

const BASE = "https://mcp.example.test";
const ACCEPT = "application/json, text/event-stream";
let nextId = 1;

async function rpc(method, params = {}, env = {}, headers = {}) {
	const body = { jsonrpc: "2.0", id: nextId++, method, params };
	const res = await worker.fetch(
		new Request(`${BASE}/mcp`, {
			method: "POST",
			headers: { "Content-Type": "application/json", Accept: ACCEPT, "Mcp-Protocol-Version": "2025-06-18", ...headers },
			body: JSON.stringify(body),
		}),
		env,
	);
	const text = await res.text();
	return { status: res.status, headers: res.headers, json: text ? JSON.parse(text) : null };
}

async function call(name, args) {
	const r = await rpc("tools/call", { name, arguments: args });
	assert.equal(r.status, 200, JSON.stringify(r.json));
	assert.ok(r.json.result, JSON.stringify(r.json));
	return r.json.result;
}

test("initialize advertises tools, resources and instructions", async () => {
	const r = await rpc("initialize", {
		protocolVersion: "2025-06-18",
		capabilities: {},
		clientInfo: { name: "test", version: "0" },
	});
	assert.equal(r.status, 200);
	const res = r.json.result;
	assert.equal(res.serverInfo.name, "luau-skill");
	assert.ok(res.capabilities.tools);
	assert.ok(res.capabilities.resources);
	assert.match(res.instructions, /api_lookup/);
	assert.match(res.instructions, /Never claim Studio testing/);
	assert.equal(r.headers.get("Access-Control-Allow-Origin"), "*");
});

test("tools/list exposes the read-only tool set with input schemas", async () => {
	const r = await rpc("tools/list");
	const names = r.json.result.tools.map((t) => t.name).sort();
	assert.deepEqual(names, [
		"api_deprecated",
		"api_lookup",
		"api_search",
		"list_skill_docs",
		"read_skill_doc",
		"scan_legacy",
		"search_skill",
	]);
	for (const t of r.json.result.tools) {
		assert.equal(t.inputSchema.type, "object", t.name);
		assert.equal(t.annotations.readOnlyHint, true, t.name);
	}
	const lookup = r.json.result.tools.find((t) => t.name === "api_lookup");
	assert.deepEqual(lookup.inputSchema.required, ["query"]);
});

test("api_lookup: deprecated member, plugin-only write, NOT FOUND", async () => {
	let r = await call("api_lookup", { query: "Humanoid.LoadAnimation" });
	assert.match(r.content[0].text, /DEPRECATED\/SUPERSEDED/);
	assert.match(r.content[0].text, /Animator:LoadAnimation/);
	assert.doesNotMatch(r.content[0].text, /prefer=LoadAnimation/);
	r = await call("api_lookup", { query: "Lighting.LightingStyle" });
	assert.match(r.content[0].text, /write NO \(PluginOrOpenCloud/);
	r = await call("api_lookup", { query: "Lighting.RayTracing" });
	assert.match(r.content[0].text, /^NOT FOUND/);
	r = await call("api_lookup", { query: "Enum.RaycastFilterType" });
	assert.match(r.content[0].text, /Exclude/);
	assert.doesNotMatch(r.content[0].text, /Blacklist/);
});

test("scan_legacy finds legacy patterns in submitted code", async () => {
	const code = [
		"local track = humanoid:LoadAnimation(anim)",
		"spawn(function() end)",
		"while wait(1) do end",
		"-- humanoid:LoadAnimation(commented)",
	].join("\n");
	const r = await call("scan_legacy", { code });
	const t = r.content[0].text;
	assert.match(t, /\[anim-humanoid-load\]/);
	assert.match(t, /\[sched-spawn\]/);
	assert.match(t, /\[sched-wait\]/);
	assert.doesNotMatch(t, /:4:/);
});

test("search_skill and read_skill_doc reach the knowledge", async () => {
	let r = await call("search_skill", { query: "session locking" });
	assert.match(r.content[0].text, /save-system|data-persistence/);
	r = await call("read_skill_doc", { path: "SKILL.md" });
	assert.match(r.content[0].text, /name: tk-luau-roblox/);
	r = await call("read_skill_doc", { path: "handbook/roblox/25-monetization.md", heading: "Receipt APIs" });
	assert.match(r.content[0].text, /BindReceiptHandler/);
	r = await call("read_skill_doc", { path: "../../etc/passwd" });
	assert.equal(r.isError, true);
	r = await call("list_skill_docs", { prefix: "recipes/gameplay" });
	assert.match(r.content[0].text, /save-system\.md/);
});

test("invalid arguments are rejected by the schema", async () => {
	const r = await rpc("tools/call", { name: "api_lookup", arguments: {} });
	const err = r.json.error ?? (r.json.result?.isError ? r.json.result : null);
	assert.ok(err, JSON.stringify(r.json));
});

test("resource skill://SKILL.md is readable", async () => {
	const r = await rpc("resources/read", { uri: "skill://SKILL.md" });
	assert.match(r.json.result.contents[0].text, /Hard rules/);
});

test("optional bearer token guards /mcp", async () => {
	const env = { MCP_TOKEN: "s3cret" };
	let r = await rpc("tools/list", {}, env);
	assert.equal(r.status, 401);
	r = await rpc("tools/list", {}, env, { Authorization: "Bearer wrong" });
	assert.equal(r.status, 401);
	r = await rpc("tools/list", {}, env, { Authorization: "Bearer s3cret" });
	assert.equal(r.status, 200);
});

test("health endpoint and GET /mcp", async () => {
	let res = await worker.fetch(new Request(`${BASE}/`), {});
	const info = await res.json();
	assert.equal(info.name, "luau-skill");
	assert.equal(info.mcp_endpoint, `${BASE}/mcp`);
	assert.ok(info.counts.classes > 900);
	res = await worker.fetch(new Request(`${BASE}/mcp`, { method: "GET", headers: { Accept: "text/event-stream" } }), {});
	assert.equal(res.status, 405);
	res = await worker.fetch(new Request(`${BASE}/mcp`, { method: "OPTIONS" }), {});
	assert.equal(res.status, 204);
});
