---
name: tk-luau-roblox
version: 2.0.0
snapshot: "2026-09-26 — engine API 0.740.19, creator-docs cc850a8, luau-lang/site 07c3dcd"
description: >-
  Modern Roblox Studio + Luau engineering: architecture, networking/security, DataStores, performance, combat, NPC AI,
  UI, audio, streaming, procedural generation, lighting/graphics and legacy-code modernization. Includes a generated
  engine API index with a lookup tool, a verified legacy→current catalog, typechecked end-to-end recipes and evals.
  Use for writing, reviewing, debugging or modernizing Roblox code and for scene lighting/art direction.
---

# Luau + Roblox engineering skill (router)

This file is the entry point. Load more only when the task needs it (progressive disclosure):
**SKILL.md → [tracks/INDEX.md](tracks/INDEX.md) (pick a track) → handbook chapters → a recipe → references / `api/`**.
Answer in the user's language; keep API names exact. Skill text is English for precision and token economy.

## Workflow (follow in order)
1. **Inspect the project** before writing: structure (services/folders, Rojo or Studio-only), existing patterns
   (module lifecycle, networking layer, data library), Luau mode (`--!strict`?), target devices. Follow what exists.
2. **Categorize** the task → pick 1–2 tracks from [tracks/INDEX.md](tracks/INDEX.md); load only those files.
3. **Check API freshness** for every engine API you plan to use: `python tools/api.py Class.Member`
   (existence, security, deprecation, writable by game scripts, yields, undocumented). Old code → `tools/scan_legacy.py`.
4. **Inspect the architecture** the change touches: who owns the state (server/client), what replicates, lifetimes.
5. **Choose the smallest correct design**: a recipe if one fits ([recipes/INDEX.md](recipes/INDEX.md)); no frameworks.
6. **Implement** with `--!strict`, explicit cleanup, server authority, and code that reads like the project's code.
7. **Validate client/server/security**: payload validation, rate limits, streaming (instances may be missing),
   respawn/rejoin, failure paths (DataStore errors, teleport failures).
8. **Test**: run what you can (typecheck, Luau CLI tests); give the user the Studio test steps you could not run.
9. **Report honestly** (template below): evidence level per claim, what ran, what didn't, assumptions, risks.

## Hard rules
- **Never invent APIs.** If `tools/api.py` says NOT FOUND, it doesn't exist. Mark `deprecated`, `superseded`,
  `beta`, `plugin-only`, `undocumented` APIs as such when you mention them.
- **Server owns truth.** Clients send intent; the server validates type/range/NaN, rate, state, distance, LOS, ownership.
- **Never claim you ran something you didn't.** Use the evidence labels below; "tested" without a label is forbidden.
- **No fake capabilities**: no custom shaders, ray tracing/GI toggles, lens distortion; Studio-only properties
  (`LightingStyle`, `PrioritizeLightingQuality`, `StreamingEnabled`, `CollisionFidelity`, `Script.Source`,
  `MeshId`, SurfaceAppearance maps) are not set by game scripts. `pcall` doesn't grant permission.
- **Modern forms**: `task.*` (not `wait/spawn/delay`), `Animator:LoadAnimation`, `PreRender`/`PreSimulation` for new
  per-frame code, `RaycastParams.ExcludeInstances`/`Exclude`, `*Async` renames, `UpdateAsync` + session locking,
  Audio API for new audio systems, Input Action System for new bindings. Details: [legacy catalog](references/legacy-modernization/CATALOG.md).
- **One owner per property and per loop**: one camera controller, one manager per system (not one loop per object).
- **Measure performance claims**; never state FPS/ms gains without a capture.
- **Don't break working code to modernize it** — list behaviour changes explicitly; keep the old form when the
  catalog says it's still acceptable.
- Before submitting: skim [AI failure modes](references/ai-failure-modes.md) for the areas you touched.

## Evidence labels (use in reports and code headers)
| Label | Meaning |
|---|---|
| STATIC VERIFIED | read against docs/API index; nothing executed |
| TYPECHECKED | luau-lsp with Roblox definitions passed (this repo: strict, old + new solver) |
| CLI-EXECUTED | pure logic executed by the standalone Luau CLI (tests) |
| STUDIO TESTED | run in Roblox Studio (say which mode: Play, Server & Clients, device emulator) |
| LIVE TESTED | run on published servers |
| NOT RUN | not executed in any form |
Everything in this repository is at most TYPECHECKED / CLI-EXECUTED; nothing was run in Studio.

## Where things are
| Need | Go to |
|---|---|
| Task routes | [tracks/](tracks/INDEX.md) |
| Deep knowledge (Luau, Roblox systems, graphics) | [handbook/](handbook) — `luau/`, `roblox/`, `graphics/` |
| Working systems with code + tests | [recipes/INDEX.md](recipes/INDEX.md), code in `examples/` |
| Old → current APIs/patterns | [references/legacy-modernization/CATALOG.md](references/legacy-modernization/CATALOG.md) |
| Mistakes AIs make | [references/ai-failure-modes.md](references/ai-failure-modes.md), [anti-patterns](references/anti-patterns.md) |
| Symptom → cause → check | [references/debugging-playbook.md](references/debugging-playbook.md) |
| Numbers (limits, rates, sizes) | [references/limits.md](references/limits.md) |
| Which service does what | [references/service-map.md](references/service-map.md) |
| Engine API facts | `python tools/api.py X` · `api/*.tsv` (generated) |
| Search the skill | `python tools/search.py "query"` |
| Self-check with evals | [evals/README.md](evals/README.md) |

## Tools (Python 3.10+, no network needed after setup)
| Command | Does |
|---|---|
| `python tools/api.py Lighting.LightingStyle` | member facts + "can a game script write it?" |
| `python tools/api.py Humanoid --all` / `Enum.KeyCode` / `--search Pathfinding` / `--deprecated Humanoid` | class listing, enums, search, deprecations |
| `python tools/scan_legacy.py path/` | find legacy patterns in Luau code (read-only) |
| `python tools/search.py "session locking"` | ranked search over handbook/recipes/references |
| `python tools/check_api_refs.py file.md` | validate API names in text/code |
| `python tools/check_code.py file.md` | typecheck Luau blocks (needs `tools/install_toolchain.py` + sources) |
| `python tools/check_all.py` | every repository check (maintainers/CI) |

## Freshness snapshot (facts older models get wrong — verified against API 0.740 / docs 2026-09-25)
- Local light range max **120** studs; `Highlight` limit **255**; `ExposureCompensation` −5…5.
- `Lighting.Technology` is RobloxScriptSecurity + deprecated; `LightingStyle`/`PrioritizeLightingQuality` are Studio/plugin writes.
- `RaycastFilterType.Blacklist/Whitelist` removed → `Exclude/Include`; `RaycastParams.ExcludeInstances`/`IncludeInstances` exist.
- Renamed to `*Async`: `LoadCharacterAsync`, `IsInGroupAsync`, `GetRolesInGroupAsync`, `IsFriendsWithAsync`,
  `GetProductInfoAsync`, `PlayerOwnsAssetAsync`, `AwardBadgeAsync`, `UserHasBadgeAsync`, `ReserveServerAsync`,
  `PreloadAsync`, `ApplyDescriptionAsync`, `PlayEmoteAsync` … (check any with `tools/api.py`).
- `RenderStepped`/`Stepped` superseded by `PreRender`/`PreSimulation` for new work.
- Audio API is the recommended audio system; Input Action System is stable (`InputActionLabel` beta);
  server authority mode and the Character Controller Library are **beta**.
- DataStore: 4 MB values, server budget `60 + 40 × players`/min per type, 4 s `GetAsync` cache, BindToClose ~30 s.
- Require-by-string (`./`, `../`, `@self/`, `@game/`) works in Roblox and the Luau CLI.
- Undocumented in 0.740: `PlayerDataService` / `Player:GetData()` / `PlayerDataRecord` — present in the dump, no docs.

## Report template (end of any non-trivial task)
```text
Changed: files + one line each          Behaviour changes: … (or "none")
APIs checked: Class.Member (tools/api.py) …   Assumptions: …
Evidence: TYPECHECKED (command) · CLI-EXECUTED (tests) · NOT RUN in Studio
Studio test steps for the user: 1… 2… (Server & Clients where networked)
Risks / not covered: …
```
