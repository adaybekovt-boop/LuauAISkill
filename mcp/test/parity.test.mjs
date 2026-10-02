// Parity with the Python CLI tools: the Worker must give the same answers as tools/api.py and tools/scan_legacy.py.
// Skipped when python3 isn't available.
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import * as lib from "../.test-build/testing.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const hasPython = spawnSync("python3", ["--version"]).status === 0;

function py(tool, args) {
	const r = spawnSync("python3", [join(ROOT, "tools", tool), ...args], { cwd: ROOT, encoding: "utf8" });
	return { code: r.status, out: r.stdout.replace(/\n$/, "") };
}

// Only the NOT FOUND hint differs (CLI flags vs MCP tool names).
const norm = (s) => s.replace(/ Check spelling, the superclass chain.*$/m, "");

const QUERIES = [
	"Humanoid.LoadAnimation",
	"Lighting.LightingStyle",
	"Lighting.Technology",
	"Workspace:Raycast",
	"Part.Anchored",
	"Workspace.StreamingEnabled",
	"Player.FrustumStreaming",
	"Player.GetData",
	"MarketplaceService.BindReceiptHandler",
	"MarketplaceService.ProcessReceipt",
	"StudioTestService.ExecuteMultiplayerTestAsync",
	"GuiService.PreferredTransparency",
	"Enum.RaycastFilterType",
	"Enum.RaycastFilterType.Blacklist",
	"Enum.KeyCode.LeftShift",
	"Enum.FrustumStreamingMode",
	"RaycastParams.new",
	"task.spawn",
	"task",
	"Lighting",
	"Lighting.RayTracing",
	"FakeService",
	"Humanoid:MoveTo()",
	"PlayerDataService",
];

test("api_lookup matches tools/api.py", { skip: !hasPython }, () => {
	for (const q of QUERIES) {
		const p = py("api.py", [q]);
		const js = lib.lookup(q);
		assert.equal(js.found, p.code === 0, `found flag for ${q}`);
		assert.equal(norm(js.text), norm(p.out), `output for ${q}`);
	}
	const p = py("api.py", ["BasePart", "--all"]);
	assert.equal(lib.lookup("BasePart", true).text, p.out, "class listing with --all");
});

test("api_search and api_deprecated match tools/api.py", { skip: !hasPython }, () => {
	for (const term of ["Pathfinding", "Frustum", "Receipt"]) {
		assert.equal(lib.search(term).text, py("api.py", ["--search", term]).out, `search ${term}`);
	}
	for (const cls of ["Humanoid", "Workspace", "MarketplaceService"]) {
		assert.equal(lib.deprecatedOf(cls).text, py("api.py", ["--deprecated", cls]).out, `deprecated ${cls}`);
	}
});

test("scan_legacy matches tools/scan_legacy.py on every fixture", { skip: !hasPython }, () => {
	const dirs = [join(ROOT, "evals", "fixtures"), join(ROOT, "references", "legacy-modernization")];
	let compared = 0;
	for (const dir of dirs) {
		for (const name of readdirSync(dir).filter((n) => n.endsWith(".luau"))) {
			const file = join(dir, name);
			const expected = JSON.parse(execFileSync("python3", [join(ROOT, "tools", "scan_legacy.py"), "--json", file], { cwd: ROOT, encoding: "utf8" })).findings;
			const actual = lib.scan(readFileSync(file, "utf8"), name);
			assert.deepEqual(
				actual.map((f) => [f.line, f.rule, f.suggest, f.api_candidates]),
				expected.map((f) => [f.line, f.rule, f.suggest, f.api_candidates]),
				`findings for ${name}`,
			);
			compared++;
		}
	}
	assert.ok(compared >= 10, `compared ${compared} fixtures`);
});

test("scan_legacy matches on every generic rule shape", { skip: !hasPython }, () => {
	const code = [
		'local bv = Instance.new("BodyVelocity")',
		"local f = Enum.RaycastFilterType.Blacklist",
		"local t = tick() + elapsedTime()",
		'local v = part["Velocity"]',
		"model:SetPrimaryPartCFrame(cf)",
		'settings().Studio["UI Theme"] = x',
		"local ok = player:IsInGroup(1) and humanoid:LoadAnimation(a)",
		"-- spawn(f) in a comment",
	].join("\n");
	const file = join(mkdtempSync(join(tmpdir(), "scan-")), "shapes.luau");
	writeFileSync(file, code);
	const expected = JSON.parse(execFileSync("python3", [join(ROOT, "tools", "scan_legacy.py"), "--json", file], { cwd: ROOT, encoding: "utf8" })).findings;
	const actual = lib.scan(code, "shapes.luau");
	assert.ok(expected.length >= 6, `python findings ${expected.length}`);
	assert.deepEqual(
		actual.map((f) => [f.line, f.rule, f.suggest, f.api_candidates]),
		expected.map((f) => [f.line, f.rule, f.suggest, f.api_candidates]),
	);
});

test("search_skill finds the same top documents as tools/search.py for core queries", { skip: !hasPython }, () => {
	for (const q of ["session locking", "BindReceiptHandler", "frustum streaming", "flicker photosensitivity"]) {
		const cli = py("search.py", [q, "-n", "5"]).out.split("\n").filter((l) => /^\S+:\d+ /.test(l)).map((l) => l.split(":")[0]);
		const js = lib.searchSkill(q, 5).map((h) => h.path);
		assert.ok(js.length > 0, `results for ${q}`);
		assert.ok(cli.includes(js[0]) || js.includes(cli[0]), `top result overlap for ${q}: cli=${cli} js=${js}`);
	}
});

test("every catalog regex compiles in JavaScript", () => {
	assert.ok(lib.scan("local x = 1").length === 0);
});
