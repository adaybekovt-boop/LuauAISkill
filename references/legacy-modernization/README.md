# Legacy modernization: recognizing Roblox code eras and migrating safely

Files: [CATALOG.md](CATALOG.md) (89 verified legacy→current entries, generated from `catalog.json`),
`api/deprecated.tsv` (every deprecated/superseded member from the API dump), `tools/scan_legacy.py` (project scanner).

## Recognize the era of a codebase
| Era | Tell-tale signs |
|---|---|
| Classic (≤ 2014) | lowercase methods (`:connect`, `:remove`), `game.Workspace`, `Instance.new("Part", workspace)`, `Player:SaveNumber`, `HopperBin`, `Message`/`Hint`, legacy terrain `SetCell`, surface welds / `MakeJoints` |
| Pre-FE / early FE (2014–2018) | code assuming client changes replicate, `FilteringEnabled` toggles, remotes named `"Remote"` taking arbitrary actions, `GamePassService:PlayerHasPass`, `Mouse.KeyDown`, `TweenPosition` |
| Mid (2018–2021) | `wait()/spawn()/delay()`, `FindPartOnRay` + `Ray.new`, `FindPartsInRegion3`, BodyMovers, `Humanoid:LoadAnimation`, `SetPrimaryPartCFrame`, `CreateCollisionGroup`, DataStore2, `Technology = Future` in Studio, `RenderStepped` everywhere |
| Modern (2022–2024) | `task.*`, `workspace:Raycast` with `FilterType = Exclude`, `Animator`, mover constraints, `PivotTo`, `RegisterCollisionGroup`, Luau types, `TextChatService`, `UnreliableRemoteEvent`, Atmosphere/MaterialVariant |
| Current (2025–Sep 2026) | `*Async` renames (`LoadCharacterAsync`, `IsInGroupAsync`, `GetProductInfoAsync`, …), `RaycastParams.ExcludeInstances/IncludeInstances`, `PreRender/PreSimulation`, `LightingStyle` + `PrioritizeLightingQuality`, `ColorGradingEffect`, Audio API (AudioPlayer/Wire), Input Action System, `const`, `@native`, require-by-string, server authority mode (beta), CCL (beta), ProceduralModel, Animation Graphs, Script Sync, Studio MCP |

## Migration procedure (don't regex-replace blindly)
1. **Baseline**: make the game run; list what works; back up the place (File → version history) and data stores
   (never test migrations on production data).
2. **Scan**: `python tools/scan_legacy.py <project>` → triage by risk: security/data first (client authority,
   DataStore patterns, receipts), then removed/erroring APIs (Blacklist enum, legacy terrain, Technology writes),
   then deprecated APIs, then performance patterns, then cosmetic renames.
3. **One category per change**, each with a before/after behaviour check. Semantics that change silently:
   - `spawn` → `task.spawn` runs immediately (order changes); use `task.defer` to keep "later" semantics.
   - `wait()` loops → events: make sure nothing depended on the ~1/30 s throttle.
   - BodyMover → constraints: forces/responsiveness differ; retune.
   - `FindPartOnRay(ray)` → `Raycast(origin, direction)`: direction must include length; filter lists change type.
   - `Humanoid:LoadAnimation` → `Animator`: must exist (create on server for NPCs, on client for local rigs).
   - DataStore changes: migrate schema on load with versioning; keep old fields readable for at least one release.
4. **Verify**: typecheck (`tools/check_code.py` style with luau-lsp), Studio Server & Clients test, compare with
   baseline.
5. **Don't modernize for its own sake**: "discouraged" systems (legacy `Sound`) and superseded-but-working APIs can
   stay if the code is stable; prioritize what's broken, insecure, or slow.

## When old code is still acceptable
- It works, isn't security/data related, and the replacement would change behaviour you rely on.
- It's a deprecated alias with identical behaviour in code you're not touching (fix opportunistically).
- Never acceptable: client authority over economy/damage, `SetAsync`-overwrite profiles, removed enum items,
  runtime writes to Studio-only properties, `require(assetId)` of third-party code.

Sources: cd:scripting/scheduler, cd:physics/mover-constraints, cd:workspace/raycasting, cd:environment/lighting,
cd:audio/objects, cd:cloud-services/data-stores/best-practices, cd:projects/teleport.
