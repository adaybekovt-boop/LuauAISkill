# GAP REPORT — LuauAISkill-Core-2026-09-26.zip (v1.0.0)

Audience: maintainers. Written 2026-09-26 before the v2 rewrite. Evidence: full read of all 187 archive files;
cross-check against `Roblox/creator-docs@cc850a83` (2026-09-25, Studio 0.740.19), the engine API dump for client
0.740.19 (`MaximumADHD/Roblox-Client-Tracker@68bf0fc0`), `luau-lang/site@07c3dcd9`, `luau-lang/luau@0.740`.

## Inventory of v1
| Area | Content | Size |
|---|---|---|
| `SKILL.md` | Long policy contract (evidence, validation gates, report rules) | 8.8 KB |
| `handbook/` | 48 Russian chapters, 3.3–6 KB each, prose only | ~185 KB |
| `tracks/` | 10 routes, each a list of chapter links + 2 sentences | ~15 KB |
| `recipes/` | 24 "work orders", ~1.2 KB each, **no code** | ~31 KB |
| `examples/` | 26 Luau files (11 pure, 10 Roblox, 4 probes, 1 spec), 928 lines total | small |
| `evals/` | 96 short prompts + rubric, no fixtures, no scores | 90 KB |
| `reference/` | 58-row modernization matrix (1-line rows), 8-member Lighting audit JSON | 25 KB |
| `tools/` | FTS5 keyword search, corpus downloader, YAML member grep, heuristic legacy scanner, pack verifiers | ~1 k LOC |
| `sources/` | registry of URLs, pins, provenance | — |
| `upstream/` | **empty** — corpus download never succeeded | — |

## What v1 does well (keep)
- Honest evidence discipline: separates found-in-docs / compiled / executed / multi-client-tested; forbids fake test claims.
- Correct high-level security stance: client sends intent; server validates; `::` casts are not validation; NaN/inf checks.
- Correct persistence stance: failed load ≠ new profile; `UpdateAsync` transform may rerun; session locking needs fencing.
- Correct generation-token / stale-result / cleanup-ownership thinking.
- Correct Lighting fact: `Technology` is `RobloxScriptSecurity`; `LightingStyle` + `PrioritizeLightingQuality` are the
  scriptable successors (verified in YAML and dump).
- Pure Luau examples (TokenBucket, BoundedQueue, Cleanup, Generation) are sound.
- Awareness of 2026 features: server authority (`AuthorityMode`, `BindToSimulation`), Input Action System, CCL,
  ProceduralModel, Animation Graph, Script Sync, capabilities — all verified to exist.

## Core problems
1. **Knowledge without payload.** Chapters say *what to worry about* but almost never *what to write*. No property
   values, no working patterns, no concrete API sequences. Example: the lighting chapter never gives a single
   `Atmosphere`/`ColorCorrectionEffect` value or explains which settings combine; the bodycam recipe has zero code.
   A model with pre-2021 memory learns caution but not modern practice — it will still fall back to its stale memory.
2. **Not retrieval-shaped.** Russian prose paragraphs, no decision tables, no BAD→GOOD pairs. Cyrillic costs ~2–3×
   tokens vs English for the same content, and all API names are English anyway. Every chapter repeats a
   boilerplate header and a source block.
3. **SKILL.md is a policy essay, not a router.** It does not map task → files → APIs → recipe; it asks the agent to
   read README_RU + contract + tracks before doing anything.
4. **No API index.** `api_lookup.py` needs a corpus that was never downloaded; fallback is an 8-member JSON. No way to
   check "does `Humanoid:LoadAnimation` exist / is it deprecated / what replaced it".
5. **Legacy DB is shallow.** 58 one-line rows, no code, no "when the old code is still fine", and it misses most of
   the actual 2025–2026 drift (see below).
6. **Recipes are not recipes.** 24 × 1.2 KB checklists. No end-to-end system (interaction, inventory, save, combat,
   NPC, round manager…) with architecture + code + tests.
7. **Evals are quiz-style.** "Explain X" prompts; no broken-code fixtures, no adversarial legacy traps tied to real
   API drift, no API-freshness category, no automated checks.
8. **Missing major domains** (no or near-zero coverage): networking decision trees, rate limiting design, movement
   validation, DataStore limits/budgets/error codes, MicroProfiler label reading, graphics scene recipes (horror,
   Backrooms, poolrooms, night exterior…), `Atmosphere`/`Clouds`/`Sky` methodology, post-processing combinations,
   `SurfaceAppearance`/`MaterialVariant` specifics, environment art (scale, modular kits, clutter), camera math
   (springs, shake, recoil, head bob comfort), character controllers (slide/vault/mantle/lean/ladder/fall damage),
   combat (melee traces, hitscan, projectiles, lag compensation), physics (constraints, collision groups, ownership),
   animation (priorities, weights, markers, IK), audio (new Audio API graph specifics), UI (ScreenInsets, flex
   layouts, gamepad selection, localization), NPC (perception, LOD ticking, 100-NPC scheduling), terrain,
   procedural generation algorithms (seeded RNG, room graphs, Backrooms layout), anti-pattern DB, AI failure-mode DB,
   debugging playbook, device scalability tiers, tooling (Rojo/Wally/Selene/StyLua/luau-lsp).
9. **Duplication.** The same "not tested in Studio / source review is not a test / screenshot is not a profile" text
   appears in SKILL.md, README, README_RU, 00-contract, 28-testing, 31-release, every recipe footer and every chapter
   header. Chapters 06/46 (async), 26/41 (profiling), 20/21 (graphics), 32/33 (tooling) overlap heavily.
10. **Examples unverified.** No typecheck against Roblox definitions was run; `qa/` only logs Python tests.
11. **Repository root out of sync.** Root README describes `guide/` with 45 chapters — does not exist.

## Outdated / missing freshness facts found in verification (not in v1)
Verified in dump 0.740.19 + creator-docs cc850a83:
- **`*Async` renames** (old names deprecated): `Player:LoadCharacter`→`LoadCharacterAsync`, `Player:IsInGroup`→
  `IsInGroupAsync`, `GetRankInGroup(Async)`/`GetRoleInGroup(Async)`→`GetRolesInGroupAsync`, `IsFriendsWith`→
  `IsFriendsWithAsync`, `MarketplaceService:GetProductInfo`→`GetProductInfoAsync`, `PlayerOwnsAsset`→
  `PlayerOwnsAssetAsync`, `BadgeService:AwardBadge`→`AwardBadgeAsync`, `TeleportService:ReserveServer`→
  `ReserveServerAsync`, `ContentProvider:Preload`→`PreloadAsync`, `Humanoid:ApplyDescription`→
  `ApplyDescriptionAsync`, `Humanoid:PlayEmote`→`PlayEmoteAsync`, `Players:GetHumanoidDescriptionFromUserId`→`…Async`,
  `Players:CreateHumanoidModelFromUserId`→`…Async`, `LocalizationService:GetTranslatorForPlayer`→`…Async`.
- **`RaycastParams`/`OverlapParams`**: `ExcludeInstances` / `IncludeInstances` supersede
  `FilterDescendantsInstances` + `FilterType` for new work (mixed include+exclude supported).
- **`ColorGradingEffect`** with `TonemapperPreset` exists; `Technology.Compatibility` look = Voxel + Retro tonemapper.
- **Light range clamp is 120 studs** (`ExtendLightRangeTo120` is unused/NotScriptable).
- **`SurfaceAppearance` texture maps are `PluginSecurity`** — game scripts cannot read/swap `ColorMap` etc. at runtime;
  `Color` (tint) and `EmissiveStrength` are script-writable.
- `Workspace.StreamingEnabled` write is `PluginSecurity`; `StreamingIntegrityMode`, `StreamOutBehavior`,
  `SignalBehavior`, `UseFixedSimulation`, `PhysicsSteppingMethod` are NotScriptable (Studio-only settings).
- Deprecated: `Humanoid:LoadAnimation`, `AnimationController:LoadAnimation`, `BodyMover` family,
  `GuiObject:TweenPosition/TweenSize`, `Model:SetPrimaryPartCFrame`, `FindPartOnRay*`, `FindPartsInRegion3*`,
  `BasePart.Velocity`, `PhysicsService:CreateCollisionGroup/SetPartCollisionGroup`, `Workspace.FilteringEnabled`,
  `wait`/`spawn`/`delay` globals, `UserInputService.ModalEnabled`, `Lighting.Outlines`, `Instance:Remove`,
  `Chat:FilterStringForPlayerAsync`, `TeleportService:TeleportPartyAsync/TeleportToPrivateServer`, `Message`/`Hint`.
- Luau: `const` bindings, `@native`/`@deprecated` attributes, explicit instantiation `f<<T>>()`, `math.isfinite/isnan/
  isinf/lerp/map`, `vector` library, `buffer.readbits/writebits` are documented in both Luau site and Roblox docs.

## Where a model can still hallucinate with v1
Every place v1 says "check the current API" without giving it: audio graph wiring, Atmosphere/post values,
InputAction bindings, ProceduralModel signature details, CCL ability shape, animation graph parameters, DataStore
limits, remote payload limits, MemoryStore quotas, UI safe areas, streaming APIs. Without an index the model will
fill gaps from memory.

## Replace entirely
All 48 chapters (rewrite as English dense guides grouped by domain), all 24 recipes (rewrite as end-to-end systems
with typechecked code), all tracks (turn into routers), the modernization matrix (turn into a verified legacy DB),
evals (rebuild around fixtures + adversarial freshness), SKILL.md (router), README/README_RU.

## Keep (adapted)
Evidence-level vocabulary; security/persistence invariants; pure example modules (reworked + tested); corpus
fetch concept (re-implemented against GitHub sources that are reachable); FTS search tool (kept, re-indexed).

## Delete
`PUBLISH_TO_GITHUB.cmd`, `publish_to_github.sh`, `PUBLISHING_RU.md`, `tools/publish_github.py` (one-off publication
helpers, repo already exists), `indexes/knowledge.sqlite` (generated binary; rebuild locally), per-file SHA
`PACK-MANIFEST.json` (git provides integrity), repeated disclaimers.
