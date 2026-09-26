# Changelog

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
