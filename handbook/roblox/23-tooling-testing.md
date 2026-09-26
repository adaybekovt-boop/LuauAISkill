# Tooling and testing methodology

Read when: setting up a project, choosing workflow, verifying changes, reporting what was tested.
Related: [performance tools](08-performance.md#tools-and-what-each-answers), [debugging playbook](../../references/debugging-playbook.md).

## Evidence levels (use these words honestly in every report)
| Label | Meaning | How |
|---|---|---|
| `STATIC VERIFIED` | read/reasoned + API names checked against the index | `python tools/check_api_refs.py`, `python tools/api.py` |
| `TYPECHECKED` | passes luau-lsp/luau-analyze strict with Roblox definitions | `python tools/check_code.py` or `luau-lsp analyze` |
| `CLI-EXECUTED` | pure Luau logic ran under the `luau` CLI with assertions | `luau file.spec.luau` |
| `STUDIO TESTED` | ran in Roblox Studio (state which mode: Play, Server & Clients N, Team Test) and observed expected behaviour | only if you actually did it |
| `LIVE TESTED` | published place, real clients/devices | only if you actually did it |
| `NOT RUN` | none of the above | say so |
An AI without Studio access must never write "tested in Studio".

## Studio
- **Test modes**: Play (solo client+server in one), Play Here, Run (server only, no character), **Server & Clients**
  (separate server + 1–8 client windows — the only way to see replication/security issues), Team Test.
  Client/Server toggle during solo play switches which DataModel you inspect.
- **Network Simulator** (latency/packet loss), **Device Emulator** (screen sizes, touch), **Controller Emulator**,
  **Party Simulator** (party APIs in Server & Clients).
- **Debugger**: breakpoints, conditional breakpoints, watch, call stack; breakpoints disable native codegen for that
  function. **Command bar** runs with plugin-level permissions in Edit mode (can set Studio-only properties like
  `Lighting.LightingStyle` — game scripts can't).
- **Output** filters, **Developer Console** (F9) in play; **MicroProfiler** (Ctrl+F6); **Script Profiler**;
  **Luau heap**; **Scene Analysis**.
- **Studio MCP server** (built into Studio): tools such as `script_read`, `multi_edit`, `script_grep`,
  `search_game_tree`, `inspect_instance`, `execute_luau` (Edit/Client/Server), `start_stop_play`,
  `get_console_output`, `screen_capture`, input simulation, asset search/insert, `generate_procedural_model`. If an
  agent has it connected, it can actually playtest — then results may be reported as STUDIO TESTED with evidence
  (console output, captures).
- **Assistant** (in-Studio AI) exists; treat its output like any other code: verify.

## Source workflows
| Workflow | Source of truth | Pros | Cons |
|---|---|---|---|
| Studio only (+ Team Create, version history, packages) | place file in the cloud | zero setup | weak diff/review, no CI |
| **Script Sync** (built-in) | scripts on disk ↔ Studio, everything else in the place | Git for code, keeps Studio for building, works with Team Create | only Script/LocalScript/ModuleScript/Folder sync; attributes/tags on scripts are **not** synced (don't sync tagged scripts); limits 10k scripts per root, 128 roots |
| **Rojo** (community) | the file system (`default.project.json`), including models (`.rbxm/.model.json`) | full Git/CI, packages via Wally | builders must sync assets carefully; two-way sync limitations |
Script Sync naming: `name.luau` ModuleScript · `name.server.luau` Script(Server) · `name.client.luau` Script(Client) ·
`name.local.luau` LocalScript · `name.legacy.luau` Script(Legacy) · `name.plugin.luau` Script(Plugin) · folder =
Folder · `name/init.*.luau` = script with children. (Rojo uses `.server.luau`/`.client.luau` too, but its
`.client` historically maps to LocalScript — check the tool's docs.) Never run Script Sync and Rojo on the same tree.

## Community toolchain (optional, widely used)
- **luau-lsp** (VS Code extension + CLI `luau-lsp analyze`): Roblox type definitions, sourcemap-aware requires.
  Studio companion plugin keeps the DataModel map in sync for Script Sync users.
- **Selene** (linter with Roblox std), **StyLua** (formatter), **Wally** (package manager), **Rokit/Aftman/Foreman**
  (toolchain managers), **Lune** (standalone Luau runtime for scripts/tests outside Roblox).
- Testing frameworks: TestEZ-style/Jest-Lua-style runners inside Studio; or pure-logic tests under the `luau` CLI /
  Lune. `TestService` exists but its `Run` is deprecated (`RunAsync`); most teams use a framework.
None are required by this skill.

## Testing methodology
| Layer | What | Where |
|---|---|---|
| Syntax/types | every file strict-typechecks | luau-lsp / luau-analyze |
| Unit | pure modules (validation, math, state machines, inventory ops, migrations, RNG/hash, rate limiter) | `luau` CLI / Lune / in-Studio runner |
| Integration (single client) | bootstrap, remotes wiring, UI flows, tags/binders | Studio Play |
| Multi-client | replication, authority, two players interacting with the same object, late join, rejoin | Studio **Server & Clients** (2–3 clients) |
| Adversarial | invalid payloads (NaN, huge numbers, wrong types, other players' instances), spam 100 req/s, out-of-range interactions | command bar on a client in Server & Clients (`remote:FireServer(...)`) |
| Network | 100–300 ms latency, packet loss; unreliable remotes under loss | Network Simulator |
| Data | load/save/failure/lock/migration, shutdown with players | Studio with API access on a **test** universe; fault-injected store adapters |
| Performance | frame time p95, memory growth over 10+ min, server heartbeat | MicroProfiler, Dev Console, target devices |
| Mobile/UI | layouts, touch targets, safe areas | Device Emulator + a real phone |

Minimum acceptance for any gameplay feature: typecheck pass, one happy-path and one adversarial test (at least
described if you can't run it), cleanup verified by repeating the action 20× (no connection/instance growth).

## Pure test example (runs under `luau` CLI)
```luau
--!strict
local function clampHealth(current: number, delta: number, max: number): number
	local v = current + delta
	if v ~= v then return current end            -- NaN guard
	return math.clamp(v, 0, max)
end
local cases = { { 50, -20, 100, 30 }, { 90, 50, 100, 100 }, { 10, -50, 100, 0 }, { 10, 0 / 0, 100, 10 } }
for i, c in cases do
	local got = clampHealth(c[1], c[2], c[3])
	assert(got == c[4], `case {i}: expected {c[4]} got {got}`)
end
print("clampHealth: ok")
```

Sources: cd:studio/testing-modes, cd:studio/debugging, cd:studio/network-simulator, cd:studio/device-simulator,
cd:studio/mcp, cd:scripting/sync, cd:projects/external-tools, cd:studio/optimization/scriptprofiler,
cd:reference/engine/classes/TestService.
