# Legacy → current: catalog (generated from catalog.json — edit the JSON, then run tools/render_legacy.py)

API snapshot 0.740.19, creator-docs `cc850a83d75d`, checked 2026-09-26. Statuses: **deprecated** = tagged Deprecated in API metadata (still works unless noted); **superseded** = docs say a newer API should be used for new work; **removed** = feature/enum item gone — old code errors or does nothing; **restricted** = exists but game scripts may not write/call it (security/capability); **discouraged** = official docs recommend the newer system; old one still supported; **outdated-fact** = a number/limit/behaviour models remember that changed; **pattern** = not an API status — an obsolete or unsafe practice.

Scan a project for these patterns: `python tools/scan_legacy.py <project-dir>`. For any other API run `python tools/api.py Class.Member` (the full deprecated list is `api/deprecated.tsv`).

## scheduling

### `sched-wait` — deprecated (seen 2006-2021)
- OLD: `wait(n) / wait()`
- NEW: `task.wait(n) — or better, wait on an event/signal`
- WHY: Legacy wait is throttled (30 Hz legacy scheduler, can resume late), deprecated.
- OLD STILL OK WHEN: Never in new code; migrating a working game can be gradual.
- NOTES: task.wait resumes on the next Heartbeat after the duration; returns elapsed time.
- VERIFY: api:wait, cd:scripting/scheduler

### `sched-spawn` — deprecated (seen 2006-2021)
- OLD: `spawn(f)`
- NEW: `task.defer(f) (same 'later' semantics) or task.spawn(f) (runs immediately)`
- WHY: spawn had an implicit delay and throttling; deprecated.
- NOTES: Changing spawn→task.spawn changes execution order; review re-entrancy.
- VERIFY: api:spawn, cd:scripting/scheduler

### `sched-delay` — deprecated (seen 2006-2021)
- OLD: `delay(t, f)`
- NEW: `local th = task.delay(t, f) — keep th to task.cancel(th) on cleanup`
- WHY: Deprecated; also uncancellable.
- VERIFY: api:delay

### `sched-tick` — discouraged (seen 2006-2022)
- OLD: `tick()`
- NEW: `os.clock() for durations; workspace:GetServerTimeNow() for synced time; os.time()/DateTime for timestamps`
- WHY: tick() depends on local timezone and isn't synced between machines.
- OLD STILL OK WHEN: Existing cosmetic use is harmless.
- VERIFY: api:tick, api:Workspace.GetServerTimeNow

### `sched-while-wait` — pattern (seen 2008-2021)
- OLD: `while wait(0.1) do ... end   -- polling`
- NEW: `Event-driven (Changed, AttributeChanged, tags) or one Heartbeat accumulator for many objects`
- WHY: Polling loops per object waste CPU and scale badly; wait() is deprecated.
- OLD STILL OK WHEN: A single low-rate loop (e.g. 1 Hz autosave) is fine with task.wait.
- VERIFY: cd:performance-optimization/improve

### `sched-stepped` — superseded (seen 2014-2023)
- OLD: `RunService.Stepped:Connect(fn)`
- NEW: `RunService.PreSimulation:Connect(fn)`
- WHY: Docs: Stepped superseded by PreSimulation for new work.
- OLD STILL OK WHEN: Existing code keeps working.
- VERIFY: api:RunService.Stepped, api:RunService.PreSimulation

### `sched-renderstepped` — superseded (seen 2014-2023)
- OLD: `RunService.RenderStepped:Connect(fn)`
- NEW: `RunService.PreRender:Connect(fn) (client) — or BindToRenderStep with a priority for camera ordering`
- WHY: Docs: RenderStepped superseded by PreRender.
- OLD STILL OK WHEN: Existing code keeps working.
- VERIFY: api:RunService.RenderStepped, api:RunService.PreRender

### `sched-coroutine-wrap` — pattern (seen 2012-2021)
- OLD: `coroutine.wrap(function() ... end)()  -- fire-and-forget`
- NEW: `task.spawn(function() ... end)`
- WHY: Errors inside coroutine.wrap propagate to the resumer / are harder to trace; task.spawn reports errors with traceback via the scheduler.
- OLD STILL OK WHEN: Generators/iterators are a valid coroutine use.
- VERIFY: cd:scripting/scheduler

## language

### `lang-ypcall` — deprecated (seen 2010-2018)
- OLD: `ypcall(f)`
- NEW: `pcall(f) (yield-safe in Luau)`
- WHY: ypcall is a deprecated alias.
- VERIFY: api:ypcall

### `lang-getfenv` — discouraged (seen 2008-2020)
- OLD: `getfenv/setfenv/loadstring tricks`
- NEW: `Plain modules and explicit dependencies`
- WHY: Disables Luau optimizations (imports, fastcalls, native codegen); loadstring is server-only and off by default; common in backdoors.
- OLD STILL OK WHEN: Never in new code.
- VERIFY: luau:guides/performance, cd:luau/native-code-gen

### `lang-table-getn` — deprecated (seen 2006-2015)
- OLD: `table.getn(t) / table.foreach(t, f) / table.foreachi`
- NEW: `#t / for k, v in t do`
- WHY: Lua 5.0-era functions kept for compatibility.
- VERIFY: api:table.getn, api:table.foreach

### `lang-g-shared` — pattern (seen 2008-2020)
- OLD: `_G.Money = 5 / shared.Config`
- NEW: `ModuleScripts (require) — one per concern`
- WHY: _G/shared are untyped global state; not replicated; ordering races between scripts.
- OLD STILL OK WHEN: Quick debugging in Studio command bar.
- VERIFY: cd:scripting/module

### `lang-ternary` — pattern (seen 2006-2022)
- OLD: `local v = cond and a or b`
- NEW: `local v = if cond then a else b`
- WHY: and/or breaks when a is false/nil.
- OLD STILL OK WHEN: When a can never be falsy.
- VERIFY: luau:getting-started/syntax

### `lang-cframe-new-lookat` — superseded (seen 2008-2020)
- OLD: `CFrame.new(pos, lookAtPos)`
- NEW: `CFrame.lookAt(pos, lookAtPos, up?)`
- WHY: Docs: this overload has been replaced by CFrame.lookAt (handles up vector, degenerate cases).
- OLD STILL OK WHEN: Works still.
- VERIFY: cd:reference/engine/datatypes/CFrame

## instances

### `inst-new-parent` — pattern (seen 2008-2019)
- OLD: `Instance.new("Part", workspace)  -- then set properties`
- NEW: `local p = Instance.new("Part"); set properties; p.Parent = workspace  -- parent last`
- WHY: Parenting first triggers replication/change events for every subsequent property set (slow, ordering issues).
- OLD STILL OK WHEN: Trivial one-offs in Studio command bar.
- VERIFY: cd:performance-optimization/improve

### `inst-lowercase` — deprecated (seen 2006-2014)
- OLD: `:connect(), :wait(), :disconnect(), :remove(), :clone(), :destroy(), :findFirstChild(), .className`
- NEW: `PascalCase: :Connect(), :Wait(), :Disconnect(), :Destroy(), :Clone(), :FindFirstChild(), .ClassName`
- WHY: Lowercase aliases are deprecated.
- VERIFY: api:Instance.findFirstChild, api:Instance.remove

### `inst-remove` — deprecated (seen 2006-2014)
- OLD: `part:Remove()`
- NEW: `part:Destroy() (or part.Parent = nil to reuse)`
- WHY: Remove is deprecated; Destroy locks parent and disconnects events.
- VERIFY: api:Instance.Remove

### `inst-getservice` — pattern (seen 2006-2019)
- OLD: `game.Players / game.Workspace.Map / game.ReplicatedStorage`
- NEW: `local Players = game:GetService("Players") at the top; workspace global or GetService("Workspace")`
- WHY: Direct indexing breaks if a service is renamed/not yet created; GetService is the canonical accessor.
- OLD STILL OK WHEN: workspace is fine.
- VERIFY: cd:scripting/services

### `inst-setprimarypartcframe` — deprecated (seen 2010-2021)
- OLD: `model:SetPrimaryPartCFrame(cf) / model:GetPrimaryPartCFrame()`
- NEW: `model:PivotTo(cf) / model:GetPivot()`
- WHY: Deprecated; PivotTo is faster and doesn't require PrimaryPart.
- VERIFY: api:Model.SetPrimaryPartCFrame, api:Model.GetPrimaryPartCFrame

### `inst-makejoints` — deprecated (seen 2006-2018)
- OLD: `model:MakeJoints() / BreakJoints() / surface-based welds`
- NEW: `WeldConstraint instances (or Weld with C0/C1); destroy them to break`
- WHY: Surface joints and MakeJoints are deprecated.
- VERIFY: api:Model.MakeJoints, api:BasePart.BreakJoints

### `inst-hopperbin` — deprecated (seen 2006-2013)
- OLD: `HopperBin`
- NEW: `Tool (RequiresHandle = false for handle-less tools)`
- WHY: Deprecated class.
- VERIFY: api:HopperBin

### `inst-status` — deprecated (seen 2008-2012)
- OLD: `humanoid:AddCustomStatus()/AddStatus()`
- NEW: `Attributes or your own state table`
- WHY: Deprecated unfinished library.
- VERIFY: api:Humanoid.AddCustomStatus

## runtime

### `layout-localscript-rs` — pattern (seen 2008-now)
- OLD: `LocalScript placed in ReplicatedStorage or Workspace (never runs)`
- NEW: `Script with RunContext = Client in ReplicatedStorage (single entry), or LocalScript in StarterPlayerScripts`
- WHY: LocalScripts only run in specific client containers.
- VERIFY: cd:scripting/locations

### `layout-scripts-in-parts` — pattern (seen 2008-2021)
- OLD: `A Script copied into every door/lamp/coin model`
- NEW: `Tag instances + one module with a CollectionService binder`
- WHY: Hundreds of script copies are hard to update and waste memory.
- OLD STILL OK WHEN: Creator Store assets that must be self-contained (set explicit RunContext).
- VERIFY: cd:scripting/locations, api:CollectionService.GetInstanceAddedSignal

### `layout-signalbehavior` — pattern (seen 2006-2023)
- OLD: `Code assuming event handlers run immediately (Immediate signals)`
- NEW: `Code that works under SignalBehavior.Deferred (new templates, server authority)`
- WHY: Deferred is recommended and will become the default.
- VERIFY: api:Workspace.SignalBehavior, cd:scripting/events/deferred

## security

### `sec-filteringenabled` — removed (seen 2008-2018)
- OLD: `workspace.FilteringEnabled = false  -- 'turn off FE'`
- NEW: `Always-on client/server boundary: server authority + RemoteEvents`
- WHY: FilteringEnabled is deprecated and always effectively on; client changes never replicate (except owned physics).
- OLD STILL OK WHEN: Never.
- NOTES: Any tutorial that relies on FE off is obsolete.
- VERIFY: api:Workspace.FilteringEnabled, cd:projects/client-server

### `sec-client-currency` — pattern (seen 2008-2018)
- OLD:
```text
-- LocalScript
player.leaderstats.Coins.Value += 10
```
- NEW:
```text
-- client: remote:FireServer("ClaimReward", rewardId)
-- server: validate eligibility, then coins += amount
```
- WHY: Pre-FE habit: client-side changes don't replicate and are trivially exploitable.
- OLD STILL OK WHEN: Never.
- VERIFY: cd:scripting/security/client-server-boundary

### `sec-remote-damage` — pattern (seen 2012-now)
- OLD: `damageRemote:FireServer(target, 50) → server: target.Humanoid:TakeDamage(dmg)`
- NEW: `client sends intent (attack id, aim); server computes damage from server weapon stats + validation`
- WHY: Client can send any target and any number.
- OLD STILL OK WHEN: Never.
- VERIFY: cd:scripting/security/client-server-boundary, cd:scripting/security/security-tactics

### `sec-invokeclient` — pattern (seen 2012-now)
- OLD: `remoteFunction:InvokeClient(player) on the server critical path`
- NEW: `RemoteEvent push from the client with rate limits, or compute on the server`
- WHY: Server yields forever if the client never returns; errors if client errors/disconnects.
- OLD STILL OK WHEN: Non-critical UI queries with timeout wrappers (rarely justified).
- VERIFY: cd:scripting/events/remote

### `sec-require-assetid` — pattern (seen 2010-now)
- OLD: `require(123456789)  -- free model / 'admin' loader`
- NEW: `Code you own in the place (or packages you control); audit third-party models`
- WHY: Remote module requires are a classic backdoor vector; only works on the server and pulls code you don't control.
- OLD STILL OK WHEN: Your own published MainModule with pinned versions and review.
- VERIFY: cd:scripting/security/third-party-vulnerabilities

### `sec-secrets-replicated` — pattern (seen 2015-now)
- OLD: `local API_KEY = "..." in a ModuleScript in ReplicatedStorage`
- NEW: `HttpService:GetSecret("name") in server code (Secrets store)`
- WHY: Replicated modules can be decompiled by clients.
- OLD STILL OK WHEN: Never.
- VERIFY: cd:cloud-services/secrets, api:HttpService.GetSecret

### `server-authority-opt` — pattern (seen 2012-now)
- OLD: `Remote-based movement anti-cheat heuristics as the only defence in competitive games`
- NEW: `Consider engine server authority mode (AuthorityMode.Server, beta as of Sep 2026) with BindToSimulation + InputActions`
- WHY: Official docs call server authority the most reliable movement-exploit fix.
- OLD STILL OK WHEN: Most non-competitive games: classic model + validation is fine.
- NOTES: Beta: prototype separately.
- VERIFY: cd:projects/server-authority/index, cd:scripting/security/network-ownership

## physics

### `phys-bodymovers` — deprecated (seen 2008-2021)
- OLD: `BodyVelocity / BodyGyro / BodyPosition / BodyForce / BodyAngularVelocity / BodyThrust / RocketPropulsion`
- NEW: `LinearVelocity / AlignOrientation / AlignPosition / VectorForce / AngularVelocity / VectorForce(+offset)/Torque / AlignPosition+AlignOrientation`
- WHY: BodyMover classes are deprecated; mover constraints are attachment-based, more stable, and configurable.
- OLD STILL OK WHEN: Existing places keep working; migrate when touching the system.
- NOTES: Map: MaxForce→MaxForce/MaxTorque, P/D→Responsiveness/MaxVelocity; RelativeTo options differ. Retune feel.
- VERIFY: api:BodyVelocity, cd:physics/mover-constraints

### `phys-velocity` — deprecated (seen 2008-2021)
- OLD: `part.Velocity / part.RotVelocity`
- NEW: `part.AssemblyLinearVelocity / part.AssemblyAngularVelocity (or ApplyImpulse)`
- WHY: Deprecated; velocity is a property of the assembly.
- NOTES: Write velocity/impulses on the network owner.
- VERIFY: api:BasePart.Velocity, api:BasePart.RotVelocity

### `phys-collision-groups` — deprecated (seen 2017-2022)
- OLD: `PhysicsService:CreateCollisionGroup / SetPartCollisionGroup / part.CollisionGroupId`
- NEW: `PhysicsService:RegisterCollisionGroup + CollisionGroupSetCollidable; part.CollisionGroup = "Name"`
- WHY: Old API deprecated.
- NOTES: Max 32 groups.
- VERIFY: api:PhysicsService.CreateCollisionGroup, api:PhysicsService.SetPartCollisionGroup, api:BasePart.CollisionGroupId

### `render-collisionfidelity-runtime` — restricted (seen 2018-now)
- OLD: `meshPart.CollisionFidelity = Enum.CollisionFidelity.Box in a Script`
- NEW: `Set CollisionFidelity in Studio before publishing (PluginOrOpenCloud-only write)`
- WHY: Runtime scripts can't write it.
- VERIFY: api:TriangleMeshPart.CollisionFidelity

## queries

### `query-findpartonray` — deprecated (seen 2008-2020)
- OLD: `workspace:FindPartOnRay(Ray.new(o, d), ignore) / FindPartOnRayWithIgnoreList / WithWhitelist`
- NEW: `workspace:Raycast(origin, direction, params) → RaycastResult? (.Instance, .Position, .Normal, .Material, .Distance)`
- WHY: Deprecated; Raycast supports params, collision groups, returns a result object.
- NOTES: direction vector length = distance (max 15,000 studs).
- VERIFY: api:WorldRoot.FindPartOnRay, api:WorldRoot.Raycast, cd:workspace/raycasting

### `query-filter-blacklist` — removed (seen 2020-2023)
- OLD: `params.FilterType = Enum.RaycastFilterType.Blacklist / Whitelist`
- NEW: `params.ExcludeInstances = {...} / params.IncludeInstances = {...} (2026 API); or FilterType = Exclude / Include`
- WHY: Enum items Blacklist/Whitelist no longer exist in Enum.RaycastFilterType (API 0.740 has only Exclude, Include) → code errors.
- OLD STILL OK WHEN: Never.
- NOTES: FilterDescendantsInstances + FilterType still work but are superseded by ExcludeInstances/IncludeInstances (can be combined; exclusion wins).
- VERIFY: api:Enum.RaycastFilterType, api:RaycastParams.ExcludeInstances

### `query-filterdescendants` — superseded (seen 2020-2025)
- OLD: `params.FilterDescendantsInstances = {char}; params.FilterType = Enum.RaycastFilterType.Exclude`
- NEW: `params.ExcludeInstances = {char}`
- WHY: Docs: superseded by ExcludeInstances/IncludeInstances for new work.
- OLD STILL OK WHEN: Existing code keeps working.
- VERIFY: api:RaycastParams.FilterDescendantsInstances, api:RaycastParams.ExcludeInstances

### `query-region3` — deprecated (seen 2012-2021)
- OLD: `workspace:FindPartsInRegion3(Region3.new(a, b)) / IsRegion3Empty`
- NEW: `workspace:GetPartBoundsInBox(cframe, size, overlapParams) / GetPartBoundsInRadius / GetPartsInPart`
- WHY: Deprecated; new queries support rotation, OverlapParams, collision groups, MaxParts.
- VERIFY: api:WorldRoot.FindPartsInRegion3, api:WorldRoot.GetPartBoundsInBox

## animation

### `anim-humanoid-load` — deprecated (seen 2014-2021)
- OLD: `humanoid:LoadAnimation(anim) / animationController:LoadAnimation(anim)`
- NEW: `animator:LoadAnimation(anim) where animator = humanoid:FindFirstChildOfClass("Animator")`
- WHY: Deprecated in favour of Animator (explicit, replicates correctly).
- NOTES: Load once per Animator and reuse tracks.
- VERIFY: api:Humanoid.LoadAnimation, api:AnimationController.LoadAnimation, api:Animator.LoadAnimation

### `anim-keyframereached` — pattern (seen 2014-2020)
- OLD: `track.KeyframeReached:Connect(function(name) if name == "Hit" ...)`
- NEW: `track:GetMarkerReachedSignal("Hit"):Connect(fn) with animation events/markers`
- WHY: Markers are explicit events in the Animation Editor; KeyframeReached relies on keyframe naming.
- OLD STILL OK WHEN: KeyframeReached still works.
- NOTES: Markers are cosmetic on clients — no authoritative damage from them.
- VERIFY: api:AnimationTrack.GetMarkerReachedSignal

## players

### `async-loadcharacter` — deprecated (seen 2006-2025)
- OLD: `player:LoadCharacter()`
- NEW: `player:LoadCharacterAsync()`
- WHY: 2025-26 *Async rename; old name deprecated.
- VERIFY: api:Player.LoadCharacter, api:Player.LoadCharacterAsync

### `async-group` — deprecated (seen 2008-2025)
- OLD: `player:IsInGroup(id) / player:GetRankInGroup(id) / player:GetRoleInGroup(id)`
- NEW: `player:IsInGroupAsync(id); GroupService:GetRolesInGroupAsync(userId, groupId) (all public roles)`
- WHY: *Async renames; GetRankInGroupAsync/GetRoleInGroupAsync also superseded by GroupService:GetRolesInGroupAsync.
- NOTES: These yield: wrap in pcall, cache per session.
- VERIFY: api:Player.IsInGroup, api:Player.IsInGroupAsync, api:GroupService.GetRolesInGroupAsync

### `async-friends` — deprecated (seen 2010-2025)
- OLD: `player:IsFriendsWith(userId) / GetFriendsOnline()`
- NEW: `player:IsFriendsWithAsync(userId) / GetFriendsOnlineAsync()`
- WHY: *Async rename.
- VERIFY: api:Player.IsFriendsWith, api:Player.IsFriendsWithAsync

### `async-humanoiddesc` — deprecated (seen 2019-2025)
- OLD: `humanoid:ApplyDescription(desc) / Players:GetHumanoidDescriptionFromUserId(id) / CreateHumanoidModelFromUserId / humanoid:PlayEmote`
- NEW: `ApplyDescriptionAsync / GetHumanoidDescriptionFromUserIdAsync / CreateHumanoidModelFromUserIdAsync / PlayEmoteAsync`
- WHY: *Async renames.
- VERIFY: api:Humanoid.ApplyDescription, api:Players.GetHumanoidDescriptionFromUserId, api:Humanoid.PlayEmote

## monetization

### `money-productinfo` — deprecated (seen 2012-2025)
- OLD: `MarketplaceService:GetProductInfo(id) / PlayerOwnsAsset(p, id) / PlayerOwnsBundle`
- NEW: `GetProductInfoAsync / PlayerOwnsAssetAsync / PlayerOwnsBundleAsync`
- WHY: *Async renames.
- NOTES: pcall + cache.
- VERIFY: api:MarketplaceService.GetProductInfo, api:MarketplaceService.PlayerOwnsAsset

### `money-gamepass` — deprecated (seen 2012-2018)
- OLD: `GamePassService:PlayerHasPass(player, id)`
- NEW: `MarketplaceService:UserOwnsGamePassAsync(userId, passId) on the server`
- WHY: Deprecated service method.
- VERIFY: api:GamePassService.PlayerHasPass, api:MarketplaceService.UserOwnsGamePassAsync

### `money-receipt` — pattern (seen 2014-now)
- OLD: `ProcessReceipt returns PurchaseGranted immediately after awarding in memory`
- NEW: `Record PurchaseId + grant in the profile, save durably, then PurchaseGranted; NotProcessedYet on failure; idempotent on repeat ids`
- WHY: ProcessReceipt can re-run (rejoin/another server); granting without durable record duplicates or loses purchases.
- OLD STILL OK WHEN: Never.
- VERIFY: cd:cloud-services/data-stores/player-data-purchasing, api:MarketplaceService.ProcessReceipt

### `money-badge` — deprecated (seen 2012-2025)
- OLD: `BadgeService:AwardBadge(userId, id) / UserHasBadge`
- NEW: `BadgeService:AwardBadgeAsync / UserHasBadgeAsync (server, pcall)`
- WHY: *Async renames.
- VERIFY: api:BadgeService.AwardBadge, api:BadgeService.UserHasBadge

## teleport

### `tp-client-teleport` — deprecated (seen 2010-2022)
- OLD: `TeleportService:Teleport(placeId, player) from a LocalScript; TeleportPartyAsync; TeleportToPrivateServer; TeleportToPlaceInstance`
- NEW: `server-side TeleportService:TeleportAsync(placeId, players, TeleportOptions)`
- WHY: Client teleports are deprecated and bypass 'Secure within universe' access control.
- NOTES: TeleportOptions: ServerInstanceId, ReservedServerAccessCode, ShouldReserveServer, SetTeleportData.
- VERIFY: api:TeleportService.Teleport, api:TeleportService.TeleportAsync, cd:projects/teleport

### `tp-reserve` — deprecated (seen 2015-2025)
- OLD: `TeleportService:ReserveServer(placeId)`
- NEW: `TeleportService:ReserveServerAsync(placeId) or TeleportOptions.ShouldReserveServer = true`
- WHY: *Async rename.
- VERIFY: api:TeleportService.ReserveServer, api:TeleportService.ReserveServerAsync

## data

### `data-player-save` — deprecated (seen 2008-2014)
- OLD: `player:SaveNumber('Coins', n) / LoadNumber / DataReady / WaitForDataReady / SaveInstance`
- NEW: `DataStoreService profile per user key (UpdateAsync + session lock)`
- WHY: Legacy Data Persistence API removed/deprecated.
- OLD STILL OK WHEN: Never.
- VERIFY: api:Player.SaveNumber, api:Player.WaitForDataReady, cd:cloud-services/data-stores/index

### `data-setasync-profile` — pattern (seen 2014-now)
- OLD: `store:SetAsync(key, profile) on every change / on leave only`
- NEW: `load once, mutate in memory, UpdateAsync on autosave (60–300 s, jittered), leave, BindToClose, purchases; session lock`
- WHY: SetAsync overwrites blindly (lost updates across servers), wastes budget, no lock.
- OLD STILL OK WHEN: SetAsync for brand-new keys or admin overwrite tools.
- VERIFY: cd:cloud-services/data-stores/best-practices, cd:cloud-services/data-stores/player-data-purchasing

### `data-default-on-fail` — pattern (seen 2014-now)
- OLD: `local ok, data = pcall(GetAsync); if not ok then data = DEFAULT end  -- then saved later`
- NEW: `mark profile errored: play with defaults but never save it; block purchases/trades; retry; tell the player`
- WHY: Saving defaults after a failed load wipes the real profile.
- OLD STILL OK WHEN: Never.
- VERIFY: cd:cloud-services/data-stores/player-data-purchasing

### `data-onupdate` — deprecated (seen 2014-2019)
- OLD: `dataStore:OnUpdate(key, fn)`
- NEW: `MessagingService publish/subscribe to signal changes; re-read the store`
- WHY: Deprecated.
- VERIFY: api:GlobalDataStore.OnUpdate, cd:cloud-services/cross-server-messaging

### `data-old-limits` — outdated-fact (seen 2016-2024)
- OLD: `'60 + numPlayers × 10 requests/min per server' and '6-second write cooldown per key'`
- NEW: `Server default read/write: 60 + 40 × players per minute (configurable via SetRateLimitForRequestType); experience-wide 300 + CCU×40 (read) / ×20 (write); per-key throughput 25 MB/min read, 4 MB/min write; 4 MB value limit`
- WHY: Limit model changed; old numbers are wrong.
- NOTES: Check GetRequestBudgetForRequestType at runtime.
- VERIFY: cd:cloud-services/data-stores/error-codes-and-limits, api:DataStoreService.SetRateLimitForRequestType

### `data-datastore2` — discouraged (seen 2018-2023)
- OLD: `DataStore2 library (one data store per player + backups pattern)`
- NEW: `Single-key-per-player profiles in few data stores; official DataStore2 migration tool for existing games`
- WHY: Official best-practices: don't use DataStore2 for new experiences.
- OLD STILL OK WHEN: Existing games until migrated.
- VERIFY: cd:cloud-services/data-stores/best-practices

### `data-remove-version` — deprecated (seen 2021-2025)
- OLD: `dataStore:RemoveVersionAsync(key, version)`
- NEW: `Rely on versioning retention; manage via Open Cloud / Data Stores Manager`
- WHY: Deprecated.
- VERIFY: api:DataStore.RemoveVersionAsync

## rendering

### `phys-light-range-60` — outdated-fact (seen 2008-2023)
- OLD: `'Light Range max is 60 studs'`
- NEW: `Range is clamped to 120 studs (ExtendLightRangeTo120 is unused)`
- WHY: Engine limit changed.
- VERIFY: api:Lighting.ExtendLightRangeTo120, cd:reference/engine/classes/Lighting

### `async-preload` — deprecated (seen 2012-2020)
- OLD: `ContentProvider:Preload(id)`
- NEW: `ContentProvider:PreloadAsync({instancesOrIds}, callback?) — only for loading-screen/critical assets`
- WHY: Deprecated; preloading everything slows joins.
- VERIFY: api:ContentProvider.Preload, api:ContentProvider.PreloadAsync

### `light-technology` — restricted (seen 2018-2025)
- OLD: `Lighting.Technology = Enum.Technology.Future  -- in a Script`
- NEW: `Set Lighting.LightingStyle = Realistic (and PrioritizeLightingQuality) in Studio's Properties window; runtime scripts can't change either`
- WHY: Technology is RobloxScriptSecurity (scripts can't read/write) and deprecated; its successors are Studio/plugin-only writes (PluginOrOpenCloud capability).
- OLD STILL OK WHEN: Never at runtime.
- NOTES: Runtime graphics presets change post effects, lights, shadows toggles, Atmosphere, particle rates instead.
- VERIFY: api:Lighting.Technology, api:Lighting.LightingStyle, cd:environment/lighting

### `light-outlines` — removed (seen 2006-2016)
- OLD: `Lighting.Outlines = true`
- NEW: `Highlight instances or modelled/decal outlines`
- WHY: The outlines feature was removed; property deprecated.
- VERIFY: api:Lighting.Outlines

### `light-fog-with-atmosphere` — outdated-fact (seen 2006-2020)
- OLD: `Setting Lighting.FogEnd/FogStart while an Atmosphere exists`
- NEW: `Tune Atmosphere Density/Offset/Haze/Color`
- WHY: Fog properties are ignored/hidden when Lighting contains an Atmosphere.
- OLD STILL OK WHEN: Places without Atmosphere (stylized) can still use fog.
- VERIFY: cd:reference/engine/classes/Atmosphere

### `light-compat-look` — deprecated (seen 2018-2024)
- OLD: `Technology = Compatibility for the old Roblox look`
- NEW: `Voxel-style lighting + ColorGradingEffect.TonemapperPreset = Retro, lights ≤ 1 brightness`
- WHY: Compatibility is deprecated and not selectable.
- VERIFY: api:Enum.Technology, api:ColorGradingEffect.TonemapperPreset

### `render-highlight-31` — outdated-fact (seen 2022-2024)
- OLD: `'Only 31 Highlights can be visible at once'`
- NEW: `Client renders up to 255 simultaneous Highlights (extras silently ignored)`
- WHY: Limit changed.
- NOTES: Still reuse Highlights for performance.
- VERIFY: cd:effects/highlighting

### `render-surfaceappearance-swap` — restricted (seen 2021-now)
- OLD: `surfaceAppearance.ColorMap = "rbxassetid://..." at runtime`
- NEW: `Prebuild SurfaceAppearance variants in Studio and clone/swap the whole MeshPart or SurfaceAppearance; tint with SurfaceAppearance.Color; EmissiveStrength/EmissiveTint are writable`
- WHY: Map properties are PluginSecurity (docs: SurfaceAppearance can't generally be modified by scripts at runtime due to preprocessing).
- OLD STILL OK WHEN: Plugins / edit-time tools.
- VERIFY: api:SurfaceAppearance.ColorMap, api:SurfaceAppearance.Color, cd:art/modeling/surface-appearance

### `render-meshid-runtime` — restricted (seen 2017-now)
- OLD: `meshPart.MeshId = "rbxassetid://..." at runtime`
- NEW: `Clone a prebuilt MeshPart, or AssetService:CreateMeshPartAsync(meshContent) then ApplyMesh/replace`
- WHY: MeshId/MeshContent writes are NotAccessibleSecurity for scripts.
- OLD STILL OK WHEN: Studio edit time.
- VERIFY: api:MeshPart.MeshId, api:AssetService.CreateMeshPartAsync

### `render-texture-realism` — pattern (seen 2008-2020)
- OLD: `Decals/Textures with baked lighting for 'realism', SmoothPlastic + BrickColor palettes`
- NEW: `PBR: MaterialVariant (tileable) / SurfaceAppearance (unique meshes) + Realistic lighting`
- WHY: Modern PBR pipeline gives physically consistent response.
- OLD STILL OK WHEN: Stylized games may keep flat textures.
- VERIFY: cd:parts/materials, cd:art/modeling/surface-appearance

## audio

### `audio-sound-props` — deprecated (seen 2008-2018)
- OLD: `sound.Pitch / MaxDistance / MinDistance / EmitterSize`
- NEW: `PlaybackSpeed / RollOffMaxDistance / RollOffMinDistance`
- WHY: Deprecated aliases.
- VERIFY: api:Sound.Pitch, api:Sound.MaxDistance, api:Sound.EmitterSize

### `audio-legacy-sound` — discouraged (seen 2008-2024)
- OLD: `Sound / SoundGroup / *SoundEffect for new audio systems`
- NEW: `Audio API: AudioPlayer → Wire → AudioEmitter / AudioDeviceOutput; AudioListener; effects (AudioReverb, AudioEqualizer...)`
- WHY: Audio docs: Sound/SoundGroup/SoundEffect are now discouraged in favour of audio objects (not deprecated).
- OLD STILL OK WHEN: Existing projects and simple one-shots.
- NOTES: Audio API adds routing, voice, acoustic simulation (occlusion/diffraction/reverb).
- VERIFY: cd:audio/objects, api:AudioPlayer.Asset

### `audio-assetid` — deprecated (seen 2024-2025)
- OLD: `audioPlayer.AssetId = "..."`
- NEW: `audioPlayer.Asset = "rbxassetid://..."`
- WHY: Property renamed.
- VERIFY: api:AudioPlayer.AssetId, api:AudioPlayer.Asset

## ui

### `inst-message-hint` — deprecated (seen 2006-2014)
- OLD: `Instance.new("Message") / Instance.new("Hint")`
- NEW: `ScreenGui + TextLabel (client), or TextChatService system messages`
- WHY: Deprecated classes.
- VERIFY: api:Message, api:Hint

### `ui-tween-methods` — deprecated (seen 2012-2020)
- OLD: `frame:TweenPosition(...) / TweenSize / TweenSizeAndPosition`
- NEW: `TweenService:Create(frame, TweenInfo.new(...), { Position = ..., Size = ... }):Play()`
- WHY: Deprecated; TweenService is general and cancellable.
- VERIFY: api:GuiObject.TweenPosition, api:GuiObject.TweenSize

### `ui-text-props` — deprecated (seen 2008-2016)
- OLD: `label.FontSize / TextWrap / TextColor / BackgroundColor / BorderColor`
- NEW: `TextSize / TextWrapped / TextColor3 / BackgroundColor3 / BorderColor3`
- WHY: Deprecated aliases.
- VERIFY: api:TextLabel.FontSize, api:TextLabel.TextWrap, api:GuiObject.BackgroundColor

### `ui-draggable` — deprecated (seen 2010-2023)
- OLD: `frame.Draggable = true`
- NEW: `UIDragDetector child`
- WHY: Deprecated; UIDragDetector supports more inputs.
- VERIFY: api:GuiObject.Draggable, api:UIDragDetector

### `ui-guiinset` — pattern (seen 2016-2023)
- OLD: `Hard-coded 36-pixel topbar offset / IgnoreGuiInset juggling`
- NEW: `ScreenGui.ScreenInsets = CoreUISafeInsets (default) / DeviceSafeInsets / TopbarSafeInsets / None`
- WHY: Topbar and device cutouts vary by device and over time.
- VERIFY: api:ScreenGui.ScreenInsets, cd:ui/on-screen-containers

### `ui-resetplayergui` — deprecated (seen 2014-2018)
- OLD: `StarterGui.ResetPlayerGuiOnSpawn = false`
- NEW: `screenGui.ResetOnSpawn = false per ScreenGui`
- WHY: Deprecated global switch.
- VERIFY: api:StarterGui.ResetPlayerGuiOnSpawn

### `ui-mouseclick` — pattern (seen 2008-now)
- OLD: `button.MouseButton1Click:Connect(fn)`
- NEW: `button.Activated:Connect(fn)`
- WHY: Activated works for mouse, touch and gamepad selection.
- OLD STILL OK WHEN: Mouse-only desktop tools.
- VERIFY: api:GuiButton.Activated

## input

### `input-mouse` — deprecated (seen 2006-2016)
- OLD: `local mouse = player:GetMouse(); mouse.KeyDown:Connect(...); mouse.Button1Down`
- NEW: `UserInputService / ContextActionService / Input Action System (InputContext/InputAction/InputBinding)`
- WHY: Mouse events are superseded by UserInputService; KeyDown deprecated.
- OLD STILL OK WHEN: Mouse.Hit for quick prototypes is still available.
- VERIFY: api:Mouse.KeyDown, cd:input/input-action-system

### `input-modalenabled` — deprecated (seen 2014-2024)
- OLD: `UserInputService.ModalEnabled = true`
- NEW: `GuiService.TouchControlsEnabled = false (hide touch controls)`
- WHY: Renamed/superseded.
- VERIFY: api:UserInputService.ModalEnabled, api:GuiService.TouchControlsEnabled

### `input-bindtypes` — deprecated (seen 2014-2016)
- OLD: `ContextActionService:BindActionToInputTypes(...)`
- NEW: `ContextActionService:BindAction(name, fn, touchButton, ...inputs)`
- WHY: Deprecated.
- VERIFY: api:ContextActionService.BindActionToInputTypes

## chat

### `chat-legacy` — deprecated (seen 2016-2023)
- OLD: `Legacy Lua chat (Chat service ChatModules/ChatScript forks, Chat:Chat bubbles)`
- NEW: `TextChatService (TextChannels, TextChatCommands, BubbleChatConfiguration); filtering built in`
- WHY: Legacy chat system is retired in favour of TextChatService; ChatVersion is not script-writable.
- NOTES: Player.Chatted still exists for listening.
- VERIFY: api:TextChatService.ChatVersion, cd:chat/in-experience-text-chat

### `chat-filter-player` — deprecated (seen 2016-2020)
- OLD: `Chat:FilterStringForPlayerAsync(text, player)`
- NEW: `TextService:FilterStringAsync(text, fromUserId) → GetNonChatStringForBroadcastAsync / GetNonChatStringForUserAsync`
- WHY: Deprecated.
- VERIFY: api:Chat.FilterStringForPlayerAsync, api:TextService.FilterStringAsync

## streaming

### `render-streamingenabled-runtime` — restricted (seen 2018-now)
- OLD: `workspace.StreamingEnabled = true in a Script`
- NEW: `Set in Studio (write security PluginSecurity); design scripts for partial worlds`
- WHY: Not scriptable.
- VERIFY: api:Workspace.StreamingEnabled, cd:workspace/streaming/index

### `stream-pausemode` — superseded (seen 2019-2022)
- OLD: `workspace.StreamingPauseMode`
- NEW: `Workspace.StreamingIntegrityMode = PauseOutsideLoadedArea (Studio setting); Player.GameplayPaused`
- WHY: Superseded setting (both Studio-only).
- VERIFY: api:Workspace.StreamingPauseMode, api:Workspace.StreamingIntegrityMode

## terrain

### `terrain-legacy-cells` — removed (seen 2008-2016)
- OLD: `Terrain:SetCell / GetCell / SetCells / AutowedgeCell`
- NEW: `FillBlock/FillBall/WriteVoxels/ReadVoxels (smooth terrain)`
- WHY: Legacy terrain engine removed.
- OLD STILL OK WHEN: Never.
- VERIFY: api:Terrain.SetCell, api:Terrain.WriteVoxels

## pathfinding

### `path-old` — deprecated (seen 2014-2019)
- OLD: `PathfindingService:ComputeRawPathAsync / ComputeSmoothPathAsync / FindPathAsync with ClosestNoPath checks`
- NEW: `PathfindingService:CreatePath(agentParams) then path:ComputeAsync(start, goal); Status Success/NoPath; Blocked event`
- WHY: Deprecated methods and PathStatus values.
- VERIFY: api:PathfindingService.ComputeRawPathAsync, api:Enum.PathStatus, api:Path.ComputeAsync

## camera

### `camera-old` — deprecated (seen 2008-2017)
- OLD: `camera.CoordinateFrame / camera.focus / camera:Interpolate(cf, focus, t)`
- NEW: `camera.CFrame / camera.Focus / TweenService on camera.CFrame (Scriptable)`
- WHY: Deprecated.
- VERIFY: api:Camera.CoordinateFrame, api:Camera.Interpolate
