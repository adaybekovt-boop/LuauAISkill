# Legacy modernization: recognizing Roblox code eras and migrating safely

Files: [CATALOG.md](CATALOG.md) (152 source-checked legacy→current entries, generated from `catalog.json`),
`api/deprecated.tsv` (every deprecated/superseded member from the API dump), `tools/scan_legacy.py` (project scanner).

## Recognize the era of a codebase
| Era | Tell-tale signs |
|---|---|
| Classic (≤ 2014) | lowercase methods (`:connect`, `:remove`), `game.Workspace`, `Instance.new("Part", workspace)`, `Player:SaveNumber`, `HopperBin`, `Message`/`Hint`, legacy terrain `SetCell`, surface welds / `MakeJoints` |
| Pre-FE / early FE (2014–2018) | code assuming client changes replicate, `FilteringEnabled` toggles, remotes named `"Remote"` taking arbitrary actions, `GamePassService:PlayerHasPass`, `Mouse.KeyDown`, `TweenPosition` |
| Mid (2018–2021) | `wait()/spawn()/delay()`, `FindPartOnRay` + `Ray.new`, `FindPartsInRegion3`, BodyMovers, `Humanoid:LoadAnimation`, `SetPrimaryPartCFrame`, `CreateCollisionGroup`, DataStore2, `Technology = Future` in Studio, `RenderStepped` everywhere |
| Modern (2022–2024) | `task.*`, `workspace:Raycast` with `FilterType = Exclude`, `Animator`, mover constraints, `PivotTo`, `RegisterCollisionGroup`, Luau types, `TextChatService`, `UnreliableRemoteEvent`, Atmosphere/MaterialVariant |
| Current (2025–Sep 2026) | `*Async` renames (`LoadCharacterAsync`, `IsInGroupAsync`, `GetProductInfoAsync`, …), `RaycastParams.ExcludeInstances/IncludeInstances`, `PreRender/PreSimulation`, `LightingStyle` + `PrioritizeLightingQuality`, `ColorGradingEffect`, Audio API (AudioPlayer/Wire), Input Action System, `const`, `@native`, require-by-string, server authority mode (full release), base CCL (released; advanced abilities beta), ProceduralModel, Animation Graphs, Script Sync, Studio MCP |

## Migration procedure (don't regex-replace blindly)
1. **Baseline**: make the game run; list what works; back up the place (File → version history) and data stores
   (never test migrations on production data).
2. **Scan**: `python tools/scan_legacy.py <project>` → triage by risk: security/data first (client authority,
   DataStore patterns, receipts), then removed/erroring APIs (Blacklist enum, legacy terrain, Technology writes),
   then deprecated APIs, then performance patterns, then cosmetic renames.
3. **One category per change**, each with a before/after behaviour check. Semantics that change silently:
   - `spawn` → `task.spawn` runs immediately (order changes); `task.defer` defers within the current resumption cycle, not the old scheduler delay. Neither is timing-identical.
   - `wait()` loops → events: make sure nothing depended on the ~1/30 s throttle.
   - BodyMover → constraints: forces/responsiveness differ; retune.
   - `FindPartOnRay(ray)` → `Raycast(origin, direction)`: direction must include length; filter lists change type.
   - `Humanoid:LoadAnimation` → `Animator`: must exist and be created on the server for replicated rigs; the owning client can load/play its character animations.
   - DataStore changes: migrate schema on load with versioning; keep old fields readable for at least one release.
4. **Verify**: typecheck (`tools/check_code.py` style with luau-lsp), Studio Server & Clients test, compare with
   baseline.
5. **Don't modernize for its own sake**: "discouraged" systems (legacy `Sound`) and superseded-but-working APIs can
   stay if the code is stable; prioritize what's broken, insecure, or slow.

## When old code is still acceptable
- It works, isn't security/data related, and the replacement would change behaviour you rely on.
- It's a deprecated alias with identical behaviour in code you're not touching (fix opportunistically).
- Never acceptable: client authority over economy/damage, `SetAsync`-overwrite profiles, removed enum items,
  runtime writes to Studio-only properties, unaudited `require(assetId)` of third-party code.

Sources: cd:scripting/scheduler, cd:physics/mover-constraints, cd:workspace/raycasting, cd:environment/lighting,
cd:audio/objects, cd:cloud-services/data-stores/best-practices, cd:projects/teleport.


## Reproducible priority and coverage

- [RANKING.md](RANKING.md) lists the top 150 API rows; [ranking.json](ranking.json) preserves all 704 rows,
  exact matching eval-case IDs, input hashes and each score component.
- [ranking-policy.json](ranking-policy.json) declares the editorial risk weights. Local eval prompt/fixture
  identifier mentions are a relevance proxy, not generated-model error rates. Member names shared
  by multiple API owners need an explicit owner in the prompt to count; remaining matches are lexical.
- No representative public/historical-tutorial or generated-model-output corpus was sampled. Frequencies are null,
  not zero. **The empirical-ranking release gate is blocked**, even though static top-150 coverage passes.
- 152 grouped entries explicitly cover 327 deprecated/superseded rows, including all 150 top-ranked rows.
  [coverage.json](coverage.json) records the exact join. Every entry has old/new/why/when_ok/detect,
  API and/or pinned-document verification, and a positive [fixture](fixtures.luau). Every declared API coverage
  also has a generated API-shaped regex fixture checked independently of the entry example.
- Findings are review candidates. Regexes cannot establish receiver types, execution side, asset trust,
  persistence durability or project architecture. A valid current use may match. No automatic rewrite is offered.

Regenerate in order: `python tools/sample_legacy_tutorials.py`, `python tools/rank_legacy.py`, `python tools/check_legacy.py`,
`python tools/render_legacy.py`. CI checks use `--check` on each. `python tools/check_legacy.py --release-gate`
also fails until empirical ranking evidence is actually supplied and reviewed; static coverage alone cannot
turn that gate green. These checks execute Python detectors, not the Luau snippets or Roblox Studio.

Server authority status uses the dated [Roblox staff full-release announcement, July 9, 2026](https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993),
which supersedes stale beta wording in the pinned documentation. The base Character Controller Library is
released; its newer advanced abilities remain a separate beta. Check the current fact registry when updating snapshots.


### Measured current official-code sample

[tutorial-sample.json](tutorial-sample.json) contains actual lexical API-reference counts from 1,738 Lua/Luau
code blocks in 285 pinned creator-docs files (58 blocks contain legacy candidates). Only language-labelled
code fences and source .lua/.luau files are included. Prose, comments and ordinary strings are excluded;
Instance.new class literals are retained. Every matching block carries a source path, line, file hash and code
hash; the full sampled-block manifest has a SHA-256 fingerprint. Reproduce with
`python tools/sample_legacy_tutorials.py --check`.

This is current official tutorial code, not a representative historical tutorial/public-project corpus.
Repeated examples are not independent projects, and a reference may intentionally demonstrate a legacy API.
Backtick interpolation, variable aliases and dynamically indexed APIs can be missed. Counts are displayed
beside the editorial score but do not change that risk-first ordering. Model-output and historical-corpus
evidence are still missing, so the empirical release gate remains blocked.
