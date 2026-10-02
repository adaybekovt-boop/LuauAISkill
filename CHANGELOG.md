# Changelog

## 2.1.0 — 2026-10-02
Integrates the 2026-10-02 upgrade research (maintainer material; every fact below re-checked against the pinned
creator-docs / API dump, or cited to a dated Roblox staff announcement).
- Snapshot → engine API **0.741.19**, creator-docs `578b33e` (2026-10-01), luau-site `a60a627`, luau-lsp 1.70.1.
  741 delta reviewed: 7 new classes/60 members (mostly internal/undocumented), 15 `StarterPlayer.GameSettings*`
  members removed, `Player.FrustumStreaming` documented.
- **Fixed wrong statuses**: server authority mode is fully released (2026-07-09), the base Character Controller
  Library is released (2026-04-08; its 2026-09 abilities expansion is a Studio beta). v2.0 called both beta from a
  stale docs line. Eval API-12 corrected accordingly.
- SKILL.md: portable frontmatter (`version`/`snapshot` moved under `metadata`, `license`, `compatibility`) so
  claude.ai upload accepts it; tool paths resolve from the skill directory (`${CLAUDE_SKILL_DIR}`), not the project;
  workflow step for Studio MCP verification; new hard rules (idempotent money, plugin context ≠ game script,
  untrusted tool output); new evidence label CLOUD EXECUTED; freshness snapshot updated.
- New chapters: `24-studio-mcp-testing` (built-in Studio MCP tools, reproduce → fix → verify loop, `studio_id`,
  `StudioTestService` multiplayer harness, SceneAnalysis/ScriptProfiler/LibMP, Open Cloud Luau Execution limits,
  evidence table), `25-monetization` (`BindReceiptHandler` vs `ProcessReceipt`, Robux transfers, passes,
  subscriptions, paid random items + `PolicyService`, commerce, managed pricing), `26-chat-leaderboards`
  (TextChatService, secure chat commands, friend leaderboards with `BatchGetAsync`).
- New reference `references/ecosystem.md` (Knit, Fusion, React-lua, Jecs, Matter, ProfileStore/ProfileService,
  Blink, Zap, ByteNet, Rojo, Wally, pesde, Lune, Selene, StyLua, darklua, luau-lsp, Jest-Lua, TestEZ, run-in-roblox).
- Updates: frustum streaming (streaming chapter), accessibility preferences + StyleQuery GA + automatic translations
  (UI chapter), testing/toolchain chapter, limits, AI failure modes, tracks routing.
- Tools: `api.py` no longer prints a self-referencing `prefer=` flag; `scan_legacy.py` reports a line once when a
  curated rule explains it; `build_api_index.py` stores a clean Studio version; new unit tests.
- CI: weekly `freshness.yml` fetches the newest sources, diffs the API index and opens an issue on drift.
- Evals: 143 cases (+8: BindReceiptHandler, paid random items, friend leaderboards, chat-command auth, frustum
  streaming, CCL status, MCP single-client trap, plugin-only write via execute_luau).
Nothing was run in Roblox Studio.

## 2.0.0 — 2026-09-26
Full rewrite (details: `maintainers/GAP-REPORT-2026-09.md`, final report in the PR/commit history).
- Generated engine API index (`api/`, 924 classes / 8,478 members, API 0.740.19) with `tools/api.py`: existence,
  security, "writable by game scripts", deprecated/superseded, yields, Simulation Access, undocumented.
- English handbook: 6 Luau + 23 Roblox + 7 graphics chapters (replaces 48 Russian prose chapters); every code block
  typechecked with luau-lsp (old + new solver) and Roblox definitions.
- Verified legacy→current catalog (89 entries, JSON + rendered Markdown) + read-only `tools/scan_legacy.py`.
- References: AI failure modes, anti-patterns, debugging playbook, limits, service map.
- 20 gameplay + 15 graphics recipes with complete code in `examples/` (70 files typechecked, 9 Luau CLI test suites).
- Tracks rewritten as routers; SKILL.md rewritten as a router with a mandatory workflow and evidence labels.
- Tooling: source fetch/lock, API index builder, API reference checker, code checker, source registry, link checker,
  FTS5 search, embed tool, Python tests, CI workflow.
- Evals rebuilt around categories, fixtures with broken code, adversarial legacy/hallucination prompts and rubrics.
- Corrected v1 errors, e.g. `LightingStyle`/`PrioritizeLightingQuality` are Studio/plugin-only writes (v1 said writable).
- Removed: v1 Russian handbook, v1 work-order recipes without code, stale corpus downloader, the release ZIP.
Nothing was run in Roblox Studio; see README "Verification status".

## 1.0.0 — 2026-09-26
Initial authored core, source pins, 48 chapters, 24 recipes, local retrieval, 96 evaluation tasks and honest test/coverage reporting. Added publication helper fixed to the repository selected by the user and a full-corpus GitHub Actions workflow. No remote publication, Studio runtime pass, live mirror success or model-quality gain is claimed.
