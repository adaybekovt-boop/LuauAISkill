# Legacy → current: catalog (generated from catalog.json — edit the JSON, then run tools/render_legacy.py)

API snapshot 0.741.19, creator-docs `578b33e83e51`, checked 2026-10-02. Statuses: **deprecated** = tagged Deprecated in API metadata (still works unless noted); **superseded** = docs say a newer API should be used for new work; **removed** = feature/enum item gone — old code errors or does nothing; **restricted** = exists but game scripts may not write/call it (security/capability); **discouraged** = official docs recommend the newer system; old one still supported; **outdated-fact** = a number/limit/behaviour models remember that changed; **pattern** = not an API status — an obsolete or unsafe practice.

152 curated entries cover 327 distinct deprecated/superseded API rows. [Priority ranking](RANKING.md) is reproducible editorial triage, not measured public-code popularity or AI failure frequency. Representative public/historical tutorial code and model outputs were not sampled; current official tutorial code is measured separately. Empirical ranking evidence remains provisional.

Every entry has a detecting fixture; findings are review candidates, not proof of incorrect code. See [coverage report](coverage.json) and [fixtures](fixtures.luau).

Scan a project for these patterns: `python tools/scan_legacy.py <project-dir>`. For any other API run `python tools/api.py Class.Member` (the full deprecated list is `api/deprecated.tsv`).

## scheduling

### `sched-wait` — deprecated (seen 2006-2021)
- OLD: `wait(n) / wait()`
- NEW: `task.wait(n) — or better, wait on an event/signal`
- WHY: Legacy wait is throttled (30 Hz legacy scheduler, can resume late), deprecated.
- OLD STILL OK WHEN: Never in new code; migrating a working game can be gradual.
- NOTES: task.wait resumes on the next Heartbeat after the duration; returns elapsed time.
- API COVERAGE: `wait`
- DETECT: `(?<![\w.:])wait\s*\(`
- DETECTING FIXTURE: `wait(1)`
- VERIFY: api:wait, cd:scripting/scheduler, cd:reference/engine/globals/RobloxGlobals

### `sched-spawn` — deprecated (seen 2006-2021)
- OLD: `spawn(f)`
- NEW: `task.defer(f) when deferred scheduling is intended, or task.spawn(f) for immediate resumption`
- WHY: spawn had an implicit delay and throttling; deprecated.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- NOTES: Neither task.defer nor task.spawn reproduces legacy spawn timing exactly. task.defer runs at the end of the current resumption cycle; test ordering and re-entrancy.
- API COVERAGE: `spawn`
- DETECT: `(?<![\w.:])spawn\s*\(`
- DETECTING FIXTURE: `spawn(function() work() end)`
- VERIFY: api:spawn, cd:scripting/scheduler, cd:reference/engine/globals/RobloxGlobals

### `sched-delay` — deprecated (seen 2006-2021)
- OLD: `delay(t, f)`
- NEW: `local th = task.delay(t, f) — keep th to task.cancel(th) on cleanup`
- WHY: Deprecated; also uncancellable.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `delay`
- DETECT: `(?<![\w.:])delay\s*\(`
- DETECTING FIXTURE: `delay(1, callback)`
- VERIFY: api:delay, cd:reference/engine/globals/RobloxGlobals

### `sched-tick` — discouraged (seen 2006-2022)
- OLD: `tick()`
- NEW: `os.clock() for durations; workspace:GetServerTimeNow() for synced time; os.time()/DateTime for timestamps`
- WHY: tick() depends on local timezone and isn't synced between machines.
- OLD STILL OK WHEN: Existing cosmetic use is harmless.
- DETECT: `(?<![\w.:])tick\s*\(`
- DETECTING FIXTURE: `local now = tick()`
- VERIFY: api:tick, api:Workspace.GetServerTimeNow

### `sched-while-wait` — pattern (seen 2008-2021)
- OLD: `while wait(0.1) do ... end   -- polling`
- NEW: `Event-driven (Changed, AttributeChanged, tags) or one Heartbeat accumulator for many objects`
- WHY: Polling loops per object waste CPU and scale badly; wait() is deprecated.
- OLD STILL OK WHEN: A single low-rate loop (e.g. 1 Hz autosave) is fine with task.wait.
- DETECT: `while\s+wait\s*\(`
- DETECTING FIXTURE: `while wait(0.1) do poll() end`
- VERIFY: cd:performance-optimization/improve

### `sched-stepped` — superseded (seen 2014-2023)
- OLD: `RunService.Stepped:Connect(fn)`
- NEW: `RunService.PreSimulation:Connect(fn)`
- WHY: Docs: Stepped superseded by PreSimulation for new work.
- OLD STILL OK WHEN: Existing code keeps working.
- API COVERAGE: `RunService.Stepped`
- DETECT: `\.Stepped\s*:\s*Connect`
- DETECTING FIXTURE: `RunService.Stepped:Connect(step)`
- VERIFY: api:RunService.Stepped, api:RunService.PreSimulation, cd:reference/engine/classes/RunService

### `sched-renderstepped` — superseded (seen 2014-2023)
- OLD: `RunService.RenderStepped:Connect(fn)`
- NEW: `RunService.PreRender:Connect(fn) (client) — or BindToRenderStep with a priority for camera ordering`
- WHY: Docs: RenderStepped superseded by PreRender.
- OLD STILL OK WHEN: Existing code keeps working.
- API COVERAGE: `RunService.RenderStepped`
- DETECT: `\.RenderStepped\s*:\s*Connect`
- DETECTING FIXTURE: `RunService.RenderStepped:Connect(render)`
- VERIFY: api:RunService.RenderStepped, api:RunService.PreRender, cd:reference/engine/classes/RunService

### `sched-coroutine-wrap` — pattern (seen 2012-2021)
- OLD: `coroutine.wrap(function() ... end)()  -- fire-and-forget`
- NEW: `task.spawn(function() ... end)`
- WHY: Errors inside coroutine.wrap propagate to the resumer / are harder to trace; task.spawn reports errors with traceback via the scheduler.
- OLD STILL OK WHEN: Generators/iterators are a valid coroutine use.
- DETECT: `coroutine\.wrap\s*\(\s*function`
- DETECTING FIXTURE: `coroutine.wrap(function() work() end)()`
- VERIFY: cd:scripting/scheduler

## language

### `lang-ypcall` — deprecated (seen 2010-2018)
- OLD: `ypcall(f)`
- NEW: `pcall(f) (yield-safe in Luau)`
- WHY: ypcall is a deprecated alias.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `ypcall`
- DETECT: `\bypcall\s*\(`
- DETECTING FIXTURE: `ypcall(work)`
- VERIFY: api:ypcall, cd:reference/engine/globals/RobloxGlobals

### `lang-getfenv` — discouraged (seen 2008-2020)
- OLD: `getfenv/setfenv/loadstring tricks`
- NEW: `Plain modules and explicit dependencies`
- WHY: Disables Luau optimizations (imports, fastcalls, native codegen); loadstring is server-only and off by default; common in backdoors.
- OLD STILL OK WHEN: Never in new code.
- API COVERAGE: `getfenv`, `setfenv`
- DETECT: `\b(getfenv|setfenv|loadstring)\s*\(`
- DETECTING FIXTURE: `local env = getfenv(1)`
- VERIFY: luau:guides/performance, cd:luau/native-code-gen, api:getfenv, cd:reference/engine/globals/LuaGlobals, api:setfenv

### `lang-table-getn` — deprecated (seen 2006-2015)
- OLD: `table.getn(t) / table.foreach(t, f) / table.foreachi`
- NEW: `#t / for k, v in t do`
- WHY: Lua 5.0-era functions kept for compatibility.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `table.foreach`, `table.foreachi`, `table.getn`
- DETECT: `table\.(getn|foreach|foreachi)\s*\(`
- DETECTING FIXTURE: `local n = table.getn(values)`
- VERIFY: api:table.getn, api:table.foreach, cd:reference/engine/libraries/table, api:table.foreachi

### `lang-g-shared` — pattern (seen 2008-2020)
- OLD: `_G.Money = 5 / shared.Config`
- NEW: `ModuleScripts (require) — one per concern`
- WHY: _G/shared are untyped global state; not replicated; ordering races between scripts.
- OLD STILL OK WHEN: Quick debugging in Studio command bar.
- DETECT: `\b_G\.|\bshared\.`
- DETECTING FIXTURE: `_G.Money = 5`
- VERIFY: cd:scripting/module

### `lang-ternary` — pattern (seen 2006-2022)
- OLD: `local v = cond and a or b`
- NEW: `local v = if cond then a else b`
- WHY: and/or breaks when a is false/nil.
- OLD STILL OK WHEN: When a can never be falsy.
- NOTES: Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `\band\b[^\n;]+\bor\b`
- DETECTING FIXTURE: `local value = condition and first or fallback`
- VERIFY: luau:getting-started/syntax

### `lang-cframe-new-lookat` — superseded (seen 2008-2020)
- OLD: `CFrame.new(pos, lookAtPos)`
- NEW: `CFrame.lookAt(pos, lookAtPos, up?)`
- WHY: Docs: this overload has been replaced by CFrame.lookAt (handles up vector, degenerate cases).
- OLD STILL OK WHEN: Works still.
- DETECT: `CFrame\.new\s*\([^()]*,[^()]*\)\s*$`
- DETECTING FIXTURE: `local cf = CFrame.new(position, target)`
- VERIFY: cd:reference/engine/datatypes/CFrame

### `lang-collectgarbage` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `collectgarbage`
- NEW: `gcinfo() for Luau heap usage in KB; use engine profiling tools for broader memory`
- WHY: Roblox only permits collectgarbage("count"); other operations cannot control the engine collector. The documented alternative is gcinfo.
- OLD STILL OK WHEN: Existing collectgarbage("count") measurements; never assume collect/stop can force or disable GC.
- API COVERAGE: `collectgarbage`
- DETECT: `(?<![\w.:])collectgarbage\s*\(`
- DETECTING FIXTURE: `local kb = collectgarbage("count")`
- VERIFY: api:collectgarbage, api:gcinfo, cd:reference/engine/globals/LuaGlobals

## instances

### `inst-new-parent` — pattern (seen 2008-2019)
- OLD: `Instance.new("Part", workspace)  -- then set properties`
- NEW: `local p = Instance.new("Part"); set properties; p.Parent = workspace  -- parent last`
- WHY: Parenting first triggers replication/change events for every subsequent property set (slow, ordering issues).
- OLD STILL OK WHEN: Trivial one-offs in Studio command bar.
- DETECT: `Instance\.new\s*\(\s*[\"'][A-Za-z]+[\"']\s*,`
- DETECTING FIXTURE: `local p = Instance.new("Part", workspace)`
- VERIFY: cd:performance-optimization/improve

### `inst-lowercase` — deprecated (seen 2006-2014)
- OLD: `:connect(), :wait(), :disconnect(), :remove(), :clone(), :destroy(), :findFirstChild(), .className`
- NEW: `PascalCase: :Connect(), :Wait(), :Disconnect(), :Destroy(), :Clone(), :FindFirstChild(), .ClassName`
- WHY: Lowercase aliases are deprecated.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `Instance.clone`, `Instance.destroy`, `Instance.findFirstChild`, `Instance.getChildren`, `Instance.remove`
- DETECT: `:(connect|wait|disconnect|remove|clone|destroy|findFirstChild|getChildren)\s*\(`
- DETECTING FIXTURE: `signal:connect(callback)`
- VERIFY: api:Instance.findFirstChild, api:Instance.remove, api:Instance.clone, cd:reference/engine/classes/Instance, api:Instance.destroy, api:Instance.getChildren

### `inst-remove` — deprecated (seen 2006-2014)
- OLD: `part:Remove()`
- NEW: `part:Destroy() (or part.Parent = nil to reuse)`
- WHY: Remove is deprecated; Destroy locks parent and disconnects events.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `Instance.Remove`
- DETECT: `:Remove\s*\(`
- DETECTING FIXTURE: `part:Remove()`
- VERIFY: api:Instance.Remove, cd:reference/engine/classes/Instance

### `inst-getservice` — pattern (seen 2006-2019)
- OLD: `game.Players / game.Workspace.Map / game.ReplicatedStorage`
- NEW: `local Players = game:GetService("Players") at the top; workspace global or GetService("Workspace")`
- WHY: Direct indexing breaks if a service is renamed/not yet created; GetService is the canonical accessor.
- OLD STILL OK WHEN: workspace is fine.
- DETECT: `\bgame\.(Players|ReplicatedStorage|ServerStorage|ServerScriptService|Lighting|RunService|UserInputService)\b`
- DETECTING FIXTURE: `local players = game.Players`
- VERIFY: cd:scripting/services

### `inst-setprimarypartcframe` — deprecated (seen 2010-2021)
- OLD: `model:SetPrimaryPartCFrame(cf) / model:GetPrimaryPartCFrame()`
- NEW: `model:PivotTo(cf) / model:GetPivot()`
- WHY: Deprecated; PivotTo is faster and doesn't require PrimaryPart.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `Model.GetPrimaryPartCFrame`, `Model.SetPrimaryPartCFrame`
- DETECT: `(Set|Get)PrimaryPartCFrame`
- DETECTING FIXTURE: `model:SetPrimaryPartCFrame(cf)`
- VERIFY: api:Model.SetPrimaryPartCFrame, api:Model.GetPrimaryPartCFrame, cd:reference/engine/classes/Model

### `inst-makejoints` — deprecated (seen 2006-2018)
- OLD: `model:MakeJoints() / BreakJoints() / surface-based welds`
- NEW: `WeldConstraint instances (or Weld with C0/C1); destroy them to break`
- WHY: Surface joints and MakeJoints are deprecated.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `BasePart.BreakJoints`, `BasePart.MakeJoints`, `Model.BreakJoints`, `Model.MakeJoints`, `Workspace.BreakJoints`, `Workspace.MakeJoints`
- DETECT: `:(MakeJoints|BreakJoints)\s*\(`
- DETECTING FIXTURE: `model:MakeJoints()`
- VERIFY: api:Model.MakeJoints, api:BasePart.BreakJoints, cd:reference/engine/classes/BasePart, api:BasePart.MakeJoints, api:Model.BreakJoints, cd:reference/engine/classes/Model, api:Workspace.BreakJoints, cd:reference/engine/classes/Workspace, api:Workspace.MakeJoints

### `inst-hopperbin` — deprecated (seen 2006-2013)
- OLD: `HopperBin`
- NEW: `Tool (RequiresHandle = false for handle-less tools)`
- WHY: Deprecated class.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `HopperBin`
- DETECT: `HopperBin`
- DETECTING FIXTURE: `local bin = Instance.new("HopperBin")`
- VERIFY: api:HopperBin, cd:reference/engine/classes/HopperBin

### `inst-status` — deprecated (seen 2008-2012)
- OLD: `Humanoid:AddStatus/AddCustomStatus/RemoveStatus/RemoveCustomStatus/GetStatuses/HasStatus/HasCustomStatus and StatusAdded/Removed/CustomStatusAdded/Removed`
- NEW: `Attributes or your own state table`
- WHY: The built-in custom-status API is deprecated. Use explicit state with Attributes or owned tables and migrate its events/queries with the writers.
- OLD STILL OK WHEN: Only while replacing an explicitly understood legacy status system; do not depend on undocumented compatibility behaviour.
- NOTES: Deprecated status events and queries belong to the same removed system; migrate writers and observers together.
- API COVERAGE: `Humanoid.AddCustomStatus`, `Humanoid.AddStatus`, `Humanoid.CustomStatusAdded`, `Humanoid.CustomStatusRemoved`, `Humanoid.GetStatuses`, `Humanoid.HasCustomStatus`, `Humanoid.HasStatus`, `Humanoid.RemoveCustomStatus`, `Humanoid.RemoveStatus`, `Humanoid.StatusAdded`, `Humanoid.StatusRemoved`
- DETECT: `:(?:Add(?:Custom)?Status|Remove(?:Custom)?Status|GetStatuses|Has(?:Custom)?Status)\s*\(|\.(?:CustomStatus|Status)(?:Added|Removed)\b`
- DETECTING FIXTURE: `humanoid:AddCustomStatus("Slow")`
- VERIFY: api:Humanoid.AddCustomStatus, cd:reference/engine/classes/Humanoid, api:Humanoid.AddStatus, api:Humanoid.CustomStatusAdded, api:Humanoid.CustomStatusRemoved, api:Humanoid.GetStatuses, api:Humanoid.HasCustomStatus, api:Humanoid.HasStatus, api:Humanoid.RemoveCustomStatus, api:Humanoid.RemoveStatus, api:Humanoid.StatusAdded, api:Humanoid.StatusRemoved

### `inst-model-bounds` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Model.GetModelCFrame / Model.GetModelSize`
- NEW: `Model:GetPivot() for the model pivot; GetBoundingBox() for bounds CFrame and size, or GetExtentsSize() for size`
- WHY: The old CFrame method points through another deprecated primary-part API. Pivot, primary-part position and bounding-box center are not always equal.
- OLD STILL OK WHEN: A known legacy model can be left unchanged until pivot-sensitive behaviour is baselined.
- API COVERAGE: `Model.GetModelCFrame`, `Model.GetModelSize`
- DETECT: `[.:]GetModelCFrame\b|[.:]GetModelSize\b`
- DETECTING FIXTURE: `local cf = model:GetModelCFrame()`
- VERIFY: api:Model.GetModelCFrame, api:Model.GetModelSize, api:PVInstance.GetPivot, api:Model.GetBoundingBox, api:Model.GetExtentsSize, cd:reference/engine/classes/Model

### `inst-model-identity` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Model.ResetOrientationToIdentity / Model.SetIdentityOrientation`
- NEW: `Save model:GetPivot() yourself and restore with model:PivotTo(savedPivot)`
- WHY: These deprecated methods remain callable for compatibility but do nothing. Do not follow their stale preferred name to another deprecated API.
- OLD STILL OK WHEN: Only inert compatibility calls; never depend on them to reset orientation.
- API COVERAGE: `Model.ResetOrientationToIdentity`, `Model.SetIdentityOrientation`
- DETECT: `[.:]ResetOrientationToIdentity\b|[.:]SetIdentityOrientation\b`
- DETECTING FIXTURE: `model:ResetOrientationToIdentity()`
- VERIFY: api:Model.ResetOrientationToIdentity, api:Model.SetIdentityOrientation, api:PVInstance.GetPivot, api:PVInstance.PivotTo, cd:reference/engine/classes/Model

### `inst-model-aliases` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Model.breakJoints / Model.makeJoints / Model.move / Model.moveTo / BasePart.breakJoints / BasePart.makeJoints`
- NEW: `Explicit WeldConstraint lifecycle for joints; Model:MoveTo(position) when its collision-adjusting semantics are intended, PivotTo for an exact transform`
- WHY: Lowercase aliases are deprecated. Uppercase MakeJoints/BreakJoints are also deprecated, so do not stop at a spelling change.
- OLD STILL OK WHEN: Existing movement aliases can remain until touched; preserve MoveTo collision/offset behaviour.
- API COVERAGE: `BasePart.breakJoints`, `BasePart.makeJoints`, `Model.breakJoints`, `Model.makeJoints`, `Model.move`, `Model.moveTo`
- DETECT: `[.:]breakJoints\b|[.:]makeJoints\b|[.:]move\b|[.:]moveTo\b|[.:]breakJoints\b|[.:]makeJoints\b`
- DETECTING FIXTURE: `model:moveTo(position)`
- VERIFY: api:Model.breakJoints, api:Model.makeJoints, api:Model.move, api:Model.moveTo, api:BasePart.breakJoints, api:BasePart.makeJoints, api:Model.MoveTo, api:PVInstance.PivotTo, api:WeldConstraint, cd:reference/engine/classes/Model, cd:reference/engine/classes/BasePart

### `inst-lowercase-properties` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Object.className / Object.isA / Instance.archivable / Instance.childAdded / Instance.children / Instance.isDescendantOf`
- NEW: `ClassName / IsA / Archivable / ChildAdded / GetChildren / IsDescendantOf`
- WHY: These compatibility aliases use the modern member with the same receiver and operation.
- OLD STILL OK WHEN: Untouched working legacy code.
- API COVERAGE: `Instance.archivable`, `Instance.childAdded`, `Instance.children`, `Instance.isDescendantOf`, `Object.className`, `Object.isA`
- DETECT: `[.:]className\b|[.:]isA\b|[.:]archivable\b|[.:]childAdded\b|[.:]children\b|[.:]isDescendantOf\b`
- DETECTING FIXTURE: `if object:isA("Part") then inspect(object.className) end`
- VERIFY: api:Object.className, api:Object.isA, api:Instance.archivable, api:Instance.childAdded, api:Instance.children, api:Instance.isDescendantOf, api:Object.ClassName, api:Object.IsA, api:Instance.Archivable, api:Instance.ChildAdded, api:Instance.GetChildren, api:Instance.IsDescendantOf, cd:reference/engine/classes/Object, cd:reference/engine/classes/Instance

### `inst-value-changed-aliases` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `BoolValue.changed / BrickColorValue.changed / CFrameValue.changed / Color3Value.changed / IntValue.changed / NumberValue.changed / ObjectValue.changed / RayValue.changed / StringValue.changed / Vector3Value.changed`
- NEW: `valueObject.Changed:Connect(handler)`
- WHY: Lowercase changed is deprecated. ValueBase-derived Changed signals supply the new value rather than a property-name string.
- OLD STILL OK WHEN: Working compatibility listeners; preserve handler argument assumptions.
- NOTES: A receiver named value is not proof of a ValueBase; check its type.
- API COVERAGE: `BoolValue.changed`, `BrickColorValue.changed`, `CFrameValue.changed`, `Color3Value.changed`, `IntValue.changed`, `NumberValue.changed`, `ObjectValue.changed`, `RayValue.changed`, `StringValue.changed`, `Vector3Value.changed`
- DETECT: `[.:]changed\b|[.:]changed\b|[.:]changed\b|[.:]changed\b|[.:]changed\b|[.:]changed\b|[.:]changed\b|[.:]changed\b|[.:]changed\b|[.:]changed\b`
- DETECTING FIXTURE: `value.changed:Connect(onChanged)`
- VERIFY: api:BoolValue.changed, api:BrickColorValue.changed, api:CFrameValue.changed, api:Color3Value.changed, api:IntValue.changed, api:NumberValue.changed, api:ObjectValue.changed, api:RayValue.changed, api:StringValue.changed, api:Vector3Value.changed, api:NumberValue.Changed, cd:reference/engine/classes/BoolValue, cd:reference/engine/classes/BrickColorValue, cd:reference/engine/classes/CFrameValue, cd:reference/engine/classes/Color3Value, cd:reference/engine/classes/IntValue, cd:reference/engine/classes/NumberValue, cd:reference/engine/classes/ObjectValue, cd:reference/engine/classes/RayValue, cd:reference/engine/classes/StringValue, cd:reference/engine/classes/Vector3Value

### `inst-collection-tags` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `CollectionService.GetCollection / CollectionService.ItemAdded / CollectionService.ItemRemoved`
- NEW: `CollectionService:GetTagged(tag), GetInstanceAddedSignal(tag), GetInstanceRemovedSignal(tag)`
- WHY: Modern tag-based discovery and lifecycle signals replace the old collection API. The old class/collection argument is not automatically the new tag.
- OLD STILL OK WHEN: A legacy collection can remain during an explicit tag rollout.
- NOTES: Tag existing instances, enumerate once, then bind added/removed signals and cleanup.
- API COVERAGE: `CollectionService.GetCollection`, `CollectionService.ItemAdded`, `CollectionService.ItemRemoved`
- DETECT: `[.:]GetCollection\b|[.:]ItemAdded\b|[.:]ItemRemoved\b`
- DETECTING FIXTURE: `local items = CollectionService:GetCollection("Coin")`
- VERIFY: api:CollectionService.GetCollection, api:CollectionService.ItemAdded, api:CollectionService.ItemRemoved, api:CollectionService.GetTagged, api:CollectionService.GetInstanceAddedSignal, api:CollectionService.GetInstanceRemovedSignal, cd:reference/engine/classes/CollectionService

### `inst-service-aliases` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `ServiceProvider.getService / ServiceProvider.service / DataModel.workspace / DataModel.lighting`
- NEW: `game:GetService(serviceName); workspace global for Workspace`
- WHY: Deprecated service aliases should become explicit service retrieval; do not assume lowercase service properties exist for every service.
- OLD STILL OK WHEN: Untouched working compatibility access.
- API COVERAGE: `DataModel.lighting`, `DataModel.workspace`, `ServiceProvider.getService`, `ServiceProvider.service`
- DETECT: `[.:]getService\b|[.:]service\b|[.:]workspace\b|[.:]lighting\b`
- DETECTING FIXTURE: `local players = game:getService("Players")`
- VERIFY: api:ServiceProvider.getService, api:ServiceProvider.service, api:DataModel.workspace, api:DataModel.lighting, api:ServiceProvider.GetService, cd:reference/engine/classes/ServiceProvider, cd:reference/engine/classes/DataModel

### `asset-free-search-async` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `InsertService.GetFreeDecals / InsertService.GetFreeModels`
- NEW: `InsertService:GetFreeDecalsAsync / GetFreeModelsAsync`
- WHY: The asset-search methods have Async renames. Search results are not authorization to load or execute untrusted asset code.
- OLD STILL OK WHEN: Existing search tooling can migrate gradually with yield/error handling.
- API COVERAGE: `InsertService.GetFreeDecals`, `InsertService.GetFreeModels`
- DETECT: `[.:]GetFreeDecals\b|[.:]GetFreeModels\b`
- DETECTING FIXTURE: `local results = InsertService:GetFreeModels(query, page)`
- VERIFY: api:InsertService.GetFreeDecals, api:InsertService.GetFreeModels, api:InsertService.GetFreeDecalsAsync, api:InsertService.GetFreeModelsAsync, cd:reference/engine/classes/InsertService

### `asset-search-package-async` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `AssetService.GetAssetIdsForPackage / AssetService.SearchAudio`
- NEW: `AssetService:GetAssetIdsForPackageAsync / SearchAudioAsync`
- WHY: The documented replacement methods use Async names; preserve their paging and asset-permission semantics.
- OLD STILL OK WHEN: Existing tooling can migrate gradually after checking security context.
- API COVERAGE: `AssetService.GetAssetIdsForPackage`, `AssetService.SearchAudio`
- DETECT: `[.:]GetAssetIdsForPackage\b|[.:]SearchAudio\b`
- DETECTING FIXTURE: `local pages = AssetService:SearchAudio(params)`
- VERIFY: api:AssetService.GetAssetIdsForPackage, api:AssetService.SearchAudio, api:AssetService.GetAssetIdsForPackageAsync, api:AssetService.SearchAudioAsync, cd:reference/engine/classes/AssetService

## runtime

### `layout-localscript-rs` — pattern (seen 2008-now)
- OLD: `LocalScript placed in ReplicatedStorage or Workspace (never runs)`
- NEW: `Script with RunContext = Client in ReplicatedStorage (single entry), or LocalScript in StarterPlayerScripts`
- WHY: LocalScripts only run in specific client containers.
- OLD STILL OK WHEN: A stored LocalScript template that will be cloned into a runnable location; stored templates are not errors.
- NOTES: Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `Instance\.new\s*\(\s*["\']LocalScript["\']`
- DETECTING FIXTURE: `local script = Instance.new("LocalScript"); script.Parent = game:GetService("ReplicatedStorage")`
- VERIFY: cd:scripting/locations

### `layout-scripts-in-parts` — pattern (seen 2008-2021)
- OLD: `A Script copied into every door/lamp/coin model`
- NEW: `Tag instances + one module with a CollectionService binder`
- WHY: Hundreds of script copies are hard to update and waste memory.
- OLD STILL OK WHEN: Creator Store assets that must be self-contained (set explicit RunContext).
- NOTES: Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `Instance\.new\s*\(\s*["\']Script["\']`
- DETECTING FIXTURE: `local script = Instance.new("Script"); script.Parent = workspace.Door`
- VERIFY: cd:scripting/locations, api:CollectionService.GetInstanceAddedSignal

### `layout-signalbehavior` — pattern (seen 2006-2023)
- OLD: `Code assuming event handlers run immediately (Immediate signals)`
- NEW: `Code that works under SignalBehavior.Deferred (new templates, server authority)`
- WHY: Deferred is recommended and will become the default.
- OLD STILL OK WHEN: A legacy place deliberately using Immediate may remain while re-entrancy and signal-order assumptions are tested.
- NOTES: Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `\bSignalBehavior\.Immediate\b`
- DETECTING FIXTURE: `workspace.SignalBehavior = Enum.SignalBehavior.Immediate`
- VERIFY: api:Workspace.SignalBehavior, cd:scripting/events/deferred

## security

### `sec-filteringenabled` — removed (seen 2008-2018)
- OLD: `workspace.FilteringEnabled = false  -- 'turn off FE'`
- NEW: `Always-on client/server boundary: server authority + RemoteEvents`
- WHY: FilteringEnabled is deprecated and always effectively on; client changes never replicate (except owned physics).
- OLD STILL OK WHEN: Never.
- NOTES: Any tutorial that relies on FE off is obsolete.
- API COVERAGE: `Workspace.FilteringEnabled`
- DETECT: `FilteringEnabled`
- DETECTING FIXTURE: `workspace.FilteringEnabled = false`
- VERIFY: api:Workspace.FilteringEnabled, cd:projects/client-server, cd:reference/engine/classes/Workspace

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
- NOTES: Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `\bleaderstats\.[A-Za-z_]\w*\.Value\s*[+\-]?=`
- DETECTING FIXTURE: `player.leaderstats.Coins.Value += 10`
- VERIFY: cd:scripting/security/client-server-boundary

### `sec-remote-damage` — pattern (seen 2012-now)
- OLD: `damageRemote:FireServer(target, 50) → server: target.Humanoid:TakeDamage(dmg)`
- NEW: `client sends intent (attack id, aim); server computes damage from server weapon stats + validation`
- WHY: Client can send any target and any number.
- OLD STILL OK WHEN: Never.
- NOTES: Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `:TakeDamage\s*\(`
- DETECTING FIXTURE: `damageRemote.OnServerEvent:Connect(function(player, target, damage) target.Humanoid:TakeDamage(damage) end)`
- VERIFY: cd:scripting/security/client-server-boundary, cd:scripting/security/security-tactics

### `sec-invokeclient` — pattern (seen 2012-now)
- OLD: `remoteFunction:InvokeClient(player) on the server critical path`
- NEW: `RemoteEvent push from the client with rate limits, or compute on the server`
- WHY: Server yields forever if the client never returns; errors if client errors/disconnects.
- OLD STILL OK WHEN: Non-critical UI queries with timeout wrappers (rarely justified).
- DETECT: `:InvokeClient\s*\(`
- DETECTING FIXTURE: `remote:InvokeClient(player)`
- VERIFY: cd:scripting/events/remote

### `sec-require-assetid` — pattern (seen 2010-now)
- OLD: `require(123456789)  -- free model / 'admin' loader`
- NEW: `Code you own in the place (or packages you control); audit third-party models`
- WHY: Remote module requires are a classic backdoor vector; only works on the server and pulls code you don't control.
- OLD STILL OK WHEN: Your own published MainModule with pinned versions and review.
- DETECT: `require\s*\(\s*\d{5,}`
- DETECTING FIXTURE: `local admin = require(123456789)`
- VERIFY: cd:scripting/security/third-party-vulnerabilities

### `sec-secrets-replicated` — pattern (seen 2015-now)
- OLD: `local API_KEY = "..." in a ModuleScript in ReplicatedStorage`
- NEW: `HttpService:GetSecret("name") in server code (Secrets store)`
- WHY: Replicated modules can be decompiled by clients.
- OLD STILL OK WHEN: Never.
- DETECT: `(api[_-]?key|token|secret)\s*=\s*[\"']`
- DETECTING FIXTURE: `local api_key = "example-placeholder"`
- VERIFY: cd:cloud-services/secrets, api:HttpService.GetSecret

### `server-authority-opt` — pattern (seen 2012-now)
- OLD: `Remote-based movement anti-cheat heuristics as the only defence in competitive games`
- NEW: `Consider engine server authority mode (AuthorityMode.Server, full release 2026-07-09) with BindToSimulation + InputActions`
- WHY: Official docs call server authority the most reliable movement-exploit fix.
- OLD STILL OK WHEN: Most non-competitive games: classic model + validation is fine.
- NOTES: Beta: prototype separately. Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `:SetNetworkOwner\s*\(`
- DETECTING FIXTURE: `character.HumanoidRootPart:SetNetworkOwner(player)`
- VERIFY: cd:projects/server-authority/index, cd:scripting/security/network-ownership

## physics

### `phys-bodymovers` — deprecated (seen 2008-2021)
- OLD: `BodyVelocity / BodyGyro / BodyPosition / BodyForce / BodyAngularVelocity / BodyThrust / RocketPropulsion`
- NEW: `LinearVelocity / AlignOrientation / AlignPosition / VectorForce / AngularVelocity / VectorForce(+offset)/Torque / AlignPosition+AlignOrientation`
- WHY: BodyMover classes are deprecated; mover constraints are attachment-based, more stable, and configurable.
- OLD STILL OK WHEN: Existing places keep working; migrate when touching the system.
- NOTES: Map: MaxForce→MaxForce/MaxTorque, P/D→Responsiveness/MaxVelocity; RelativeTo options differ. Retune feel.
- API COVERAGE: `BodyAngularVelocity`, `BodyForce`, `BodyGyro`, `BodyMover`, `BodyPosition`, `BodyThrust`, `BodyVelocity`, `RocketPropulsion`
- DETECT: `\bBody(?:Mover|Velocity|Gyro|Position|Force|AngularVelocity|Thrust)\b|\bRocketPropulsion\b`
- DETECTING FIXTURE: `local velocity = Instance.new("BodyVelocity")`
- VERIFY: api:BodyVelocity, cd:physics/mover-constraints, api:BodyAngularVelocity, cd:reference/engine/classes/BodyAngularVelocity, api:BodyForce, cd:reference/engine/classes/BodyForce, api:BodyGyro, cd:reference/engine/classes/BodyGyro, api:BodyMover, cd:reference/engine/classes/BodyMover, api:BodyPosition, cd:reference/engine/classes/BodyPosition, api:BodyThrust, cd:reference/engine/classes/BodyThrust, cd:reference/engine/classes/BodyVelocity, api:RocketPropulsion, cd:reference/engine/classes/RocketPropulsion

### `phys-velocity` — deprecated (seen 2008-2021)
- OLD: `part.Velocity / part.RotVelocity`
- NEW: `part.AssemblyLinearVelocity / part.AssemblyAngularVelocity (or ApplyImpulse)`
- WHY: Deprecated; velocity is a property of the assembly.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- NOTES: Write velocity/impulses on the network owner.
- API COVERAGE: `BasePart.RotVelocity`, `BasePart.Velocity`
- DETECT: `\.(Velocity|RotVelocity)\s*=`
- DETECTING FIXTURE: `part.Velocity = direction`
- VERIFY: api:BasePart.Velocity, api:BasePart.RotVelocity, cd:reference/engine/classes/BasePart

### `phys-collision-groups` — deprecated (seen 2017-2022)
- OLD: `PhysicsService:CreateCollisionGroup / SetPartCollisionGroup / part.CollisionGroupId`
- NEW: `PhysicsService:RegisterCollisionGroup + CollisionGroupSetCollidable; part.CollisionGroup = "Name"`
- WHY: Old API deprecated.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- NOTES: Max 32 groups.
- API COVERAGE: `BasePart.CollisionGroupId`, `PhysicsService.CreateCollisionGroup`, `PhysicsService.SetPartCollisionGroup`
- DETECT: `CreateCollisionGroup|SetPartCollisionGroup|CollisionGroupId`
- DETECTING FIXTURE: `PhysicsService:CreateCollisionGroup("Players")`
- VERIFY: api:PhysicsService.CreateCollisionGroup, api:PhysicsService.SetPartCollisionGroup, api:BasePart.CollisionGroupId, cd:reference/engine/classes/BasePart, cd:reference/engine/classes/PhysicsService

### `render-collisionfidelity-runtime` — restricted (seen 2018-now)
- OLD: `meshPart.CollisionFidelity = Enum.CollisionFidelity.Box in a Script`
- NEW: `Set CollisionFidelity in Studio before publishing (PluginOrOpenCloud-only write)`
- WHY: Runtime scripts can't write it.
- OLD STILL OK WHEN: Studio/plugin tooling with the required write capability; never ordinary runtime game scripts.
- DETECT: `\.CollisionFidelity\s*=`
- DETECTING FIXTURE: `meshPart.CollisionFidelity = Enum.CollisionFidelity.Box`
- VERIFY: api:TriangleMeshPart.CollisionFidelity

### `phys-material-properties` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `BasePart.Elasticity / BasePart.Friction / BasePart.SpecificGravity`
- NEW: `BasePart.CustomPhysicalProperties / CurrentPhysicalProperties and PhysicalProperties.new`
- WHY: Legacy Elasticity and Friction no longer affect physics; SpecificGravity is deprecated. Density, friction, elasticity and their weights belong in PhysicalProperties.
- OLD STILL OK WHEN: Reading old values while diagnosing legacy content only; not to configure live physics.
- NOTES: Preserve the other physical values and weights; replacing the whole structure changes mass and contacts. SpecificGravity is not an interchangeable density value.
- API COVERAGE: `BasePart.Elasticity`, `BasePart.Friction`, `BasePart.SpecificGravity`
- DETECT: `[.:]Elasticity\b|[.:]Friction\b|[.:]SpecificGravity\b`
- DETECTING FIXTURE: `part.Friction = 0.3`
- VERIFY: api:BasePart.Elasticity, api:BasePart.Friction, api:BasePart.SpecificGravity, api:BasePart.CustomPhysicalProperties, api:BasePart.CurrentPhysicalProperties, api:PhysicalProperties.new, cd:reference/engine/classes/BasePart

### `phys-render-cframe` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `BasePart.GetRenderCFrame`
- NEW: `part.CFrame`
- WHY: Interpolation is already applied to CFrame; the old render-only accessor is obsolete.
- OLD STILL OK WHEN: Working read-only compatibility code can migrate gradually.
- API COVERAGE: `BasePart.GetRenderCFrame`
- DETECT: `[.:]GetRenderCFrame\b`
- DETECTING FIXTURE: `local cf = part:GetRenderCFrame()`
- VERIFY: api:BasePart.GetRenderCFrame, api:BasePart.CFrame, cd:reference/engine/classes/BasePart

### `phys-touch-events` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `BasePart.LocalSimulationTouched / BasePart.StoppedTouching`
- NEW: `BasePart.Touched / BasePart.TouchEnded; validate consequential contact on the server`
- WHY: The deprecated events are superseded by the regular touch events. Client contact remains untrusted.
- OLD STILL OK WHEN: Existing cosmetic observers can migrate gradually; never rely on a client touch for damage or rewards.
- API COVERAGE: `BasePart.LocalSimulationTouched`, `BasePart.StoppedTouching`
- DETECT: `[.:]LocalSimulationTouched\b|[.:]StoppedTouching\b`
- DETECTING FIXTURE: `part.LocalSimulationTouched:Connect(onTouch)`
- VERIFY: api:BasePart.LocalSimulationTouched, api:BasePart.StoppedTouching, api:BasePart.Touched, api:BasePart.TouchEnded, cd:reference/engine/classes/BasePart

### `phys-outfit-changed` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `BasePart.OutfitChanged`
- NEW: `Observe the concrete appearance objects/properties you own, or Player.CharacterAppearanceLoaded for initial avatar appearance`
- WHY: OutfitChanged is deprecated with no documented drop-in event. Shirt changes and initial avatar loading are different lifecycles.
- OLD STILL OK WHEN: Only a legacy observer whose behaviour has been checked in Studio; avoid for new systems.
- API COVERAGE: `BasePart.OutfitChanged`
- DETECT: `[.:]OutfitChanged\b`
- DETECTING FIXTURE: `part.OutfitChanged:Connect(refresh)`
- VERIFY: api:BasePart.OutfitChanged, api:Instance.GetPropertyChangedSignal, api:Player.CharacterAppearanceLoaded, cd:reference/engine/classes/BasePart

### `phys-lowercase-aliases` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `BasePart.brickColor / BasePart.getMass / BasePart.resize`
- NEW: `BasePart.BrickColor / GetMass / Resize`
- WHY: These lowercase members are deprecated aliases; keep each operation and receiver unchanged.
- OLD STILL OK WHEN: Untouched working compatibility code; rename when editing it.
- API COVERAGE: `BasePart.brickColor`, `BasePart.getMass`, `BasePart.resize`
- DETECT: `[.:]brickColor\b|[.:]getMass\b|[.:]resize\b`
- DETECTING FIXTURE: `local mass = part:getMass()`
- VERIFY: api:BasePart.brickColor, api:BasePart.getMass, api:BasePart.resize, api:BasePart.BrickColor, api:BasePart.GetMass, api:BasePart.Resize, cd:reference/engine/classes/BasePart

### `phys-bodymover-aliases` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `BodyAngularVelocity.angularvelocity / BodyAngularVelocity.maxTorque / BodyForce.force / BodyGyro.cframe / BodyGyro.maxTorque / BodyPosition.lastForce / BodyPosition.maxForce / BodyPosition.position / BodyThrust.force / BodyThrust.location / BodyVelocity.maxForce / BodyVelocity.velocity`
- NEW: `Migrate the owning BodyMover to the corresponding mover constraint; use PascalCase only as an interim compatibility cleanup`
- WHY: Both the lowercase aliases and their BodyMover families are deprecated. Renaming alone does not modernize the underlying force controller.
- OLD STILL OK WHEN: A stable legacy controller can remain while a constraint conversion is separately tuned and tested.
- NOTES: Map attachment frames, force/torque limits and responsiveness deliberately; no parameter-for-parameter equivalence is claimed.
- API COVERAGE: `BodyAngularVelocity.angularvelocity`, `BodyAngularVelocity.maxTorque`, `BodyForce.force`, `BodyGyro.cframe`, `BodyGyro.maxTorque`, `BodyPosition.lastForce`, `BodyPosition.maxForce`, `BodyPosition.position`, `BodyThrust.force`, `BodyThrust.location`, `BodyVelocity.maxForce`, `BodyVelocity.velocity`
- DETECT: `[.:]angularvelocity\b|[.:]maxTorque\b|[.:]force\b|[.:]cframe\b|[.:]maxTorque\b|[.:]lastForce\b|[.:]maxForce\b|[.:]position\b|[.:]force\b|[.:]location\b|[.:]maxForce\b|[.:]velocity\b`
- DETECTING FIXTURE: `bodyVelocity.velocity = direction * speed`
- VERIFY: api:BodyAngularVelocity.angularvelocity, api:BodyAngularVelocity.maxTorque, api:BodyForce.force, api:BodyGyro.cframe, api:BodyGyro.maxTorque, api:BodyPosition.lastForce, api:BodyPosition.maxForce, api:BodyPosition.position, api:BodyThrust.force, api:BodyThrust.location, api:BodyVelocity.maxForce, api:BodyVelocity.velocity, api:LinearVelocity, api:AngularVelocity, api:VectorForce, api:AlignPosition, api:AlignOrientation, cd:reference/engine/classes/BodyAngularVelocity, cd:reference/engine/classes/BodyForce, cd:reference/engine/classes/BodyGyro, cd:reference/engine/classes/BodyPosition, cd:reference/engine/classes/BodyThrust, cd:reference/engine/classes/BodyVelocity

### `phys-collision-group-queries` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `PhysicsService.CollisionGroupContainsPart / PhysicsService.GetCollisionGroupId / PhysicsService.GetCollisionGroupName / PhysicsService.GetCollisionGroups`
- NEW: `part.CollisionGroup for membership/name; PhysicsService:GetRegisteredCollisionGroups() for registered groups`
- WHY: Collision groups use names on BasePart; legacy numeric IDs and enumeration methods are deprecated.
- OLD STILL OK WHEN: Working callers may migrate gradually; update table consumers and persisted group references deliberately.
- API COVERAGE: `PhysicsService.CollisionGroupContainsPart`, `PhysicsService.GetCollisionGroupId`, `PhysicsService.GetCollisionGroupName`, `PhysicsService.GetCollisionGroups`
- DETECT: `[.:]CollisionGroupContainsPart\b|[.:]GetCollisionGroupId\b|[.:]GetCollisionGroupName\b|[.:]GetCollisionGroups\b`
- DETECTING FIXTURE: `local groups = PhysicsService:GetCollisionGroups()`
- VERIFY: api:PhysicsService.CollisionGroupContainsPart, api:PhysicsService.GetCollisionGroupId, api:PhysicsService.GetCollisionGroupName, api:PhysicsService.GetCollisionGroups, api:BasePart.CollisionGroup, api:PhysicsService.GetRegisteredCollisionGroups, cd:reference/engine/classes/PhysicsService

### `phys-unregister-group` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `PhysicsService.RemoveCollisionGroup`
- NEW: `PhysicsService:UnregisterCollisionGroup(name)`
- WHY: The documented current API names unregistration explicitly.
- OLD STILL OK WHEN: Untouched compatibility calls; verify the group is no longer needed before unregistering it.
- API COVERAGE: `PhysicsService.RemoveCollisionGroup`
- DETECT: `[.:]RemoveCollisionGroup\b`
- DETECTING FIXTURE: `PhysicsService:RemoveCollisionGroup("Old")`
- VERIFY: api:PhysicsService.RemoveCollisionGroup, api:PhysicsService.UnregisterCollisionGroup, cd:reference/engine/classes/PhysicsService

### `phys-attachment-axis` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Attachment.GetAxis / Attachment.GetSecondaryAxis / Attachment.SetAxis / Attachment.SetSecondaryAxis`
- NEW: `attachment.Axis / SecondaryAxis properties`
- WHY: The method-style accessors are deprecated; use the documented axis properties.
- OLD STILL OK WHEN: Existing accessors can migrate gradually; preserve object-space versus world-space intent.
- API COVERAGE: `Attachment.GetAxis`, `Attachment.GetSecondaryAxis`, `Attachment.SetAxis`, `Attachment.SetSecondaryAxis`
- DETECT: `[.:]GetAxis\b|[.:]GetSecondaryAxis\b|[.:]SetAxis\b|[.:]SetSecondaryAxis\b`
- DETECTING FIXTURE: `attachment:SetAxis(direction)`
- VERIFY: api:Attachment.GetAxis, api:Attachment.GetSecondaryAxis, api:Attachment.SetAxis, api:Attachment.SetSecondaryAxis, api:Attachment.Axis, api:Attachment.SecondaryAxis, cd:reference/engine/classes/Attachment

### `phys-attachment-orientation` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Attachment.Rotation / Attachment.WorldRotation`
- NEW: `Attachment.Orientation / WorldOrientation`
- WHY: The Rotation names are deprecated in favor of Orientation names. Preserve local versus world space and verify Euler-angle behaviour.
- OLD STILL OK WHEN: Untouched legacy attachments whose orientation is stable.
- API COVERAGE: `Attachment.Rotation`, `Attachment.WorldRotation`
- DETECT: `[.:]Rotation\b|[.:]WorldRotation\b`
- DETECTING FIXTURE: `attachment.Rotation = angles`
- VERIFY: api:Attachment.Rotation, api:Attachment.WorldRotation, api:Attachment.Orientation, api:Attachment.WorldOrientation, cd:reference/engine/classes/Attachment

### `phys-align-enums` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Enum.AlignType.Parallel / Enum.AlignType.Perpendicular`
- NEW: `Enum.AlignType.PrimaryAxisParallel / PrimaryAxisPerpendicular`
- WHY: The current enum names make primary-axis alignment explicit.
- OLD STILL OK WHEN: Untouched compatibility settings; verify constraint axis orientation.
- API COVERAGE: `Enum.AlignType.Parallel`, `Enum.AlignType.Perpendicular`
- DETECT: `Enum[.:]AlignType[.:]Parallel\b|Enum[.:]AlignType[.:]Perpendicular\b`
- DETECTING FIXTURE: `align.AlignType = Enum.AlignType.Parallel`
- VERIFY: api:Enum.AlignType.Parallel, api:Enum.AlignType.Perpendicular, api:Enum.AlignType.PrimaryAxisParallel, api:Enum.AlignType.PrimaryAxisPerpendicular, cd:reference/engine/enums/AlignType

## queries

### `query-findpartonray` — deprecated (seen 2008-2020)
- OLD: `workspace:FindPartOnRay(Ray.new(o, d), ignore) / FindPartOnRayWithIgnoreList / WithWhitelist`
- NEW: `workspace:Raycast(origin, direction, params) → RaycastResult? (.Instance, .Position, .Normal, .Material, .Distance)`
- WHY: Deprecated; Raycast supports params, collision groups, returns a result object.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- NOTES: direction vector length = distance (max 15,000 studs).
- API COVERAGE: `WorldRoot.FindPartOnRay`, `WorldRoot.FindPartOnRayWithIgnoreList`, `WorldRoot.FindPartOnRayWithWhitelist`, `WorldRoot.findPartOnRay`
- DETECT: `:(?:FindPartOnRay(?:WithIgnoreList|WithWhitelist)?|findPartOnRay)\s*\(`
- DETECTING FIXTURE: `workspace:FindPartOnRay(ray)`
- VERIFY: api:WorldRoot.FindPartOnRay, api:WorldRoot.Raycast, cd:workspace/raycasting, cd:reference/engine/classes/WorldRoot, api:WorldRoot.FindPartOnRayWithIgnoreList, api:WorldRoot.FindPartOnRayWithWhitelist, api:WorldRoot.findPartOnRay

### `query-filter-blacklist` — removed (seen 2020-2023)
- OLD: `params.FilterType = Enum.RaycastFilterType.Blacklist / Whitelist`
- NEW: `params.ExcludeInstances = {...} / params.IncludeInstances = {...} (2026 API); or FilterType = Exclude / Include`
- WHY: Enum items Blacklist/Whitelist no longer exist in Enum.RaycastFilterType (API 0.740 has only Exclude, Include) → code errors.
- OLD STILL OK WHEN: Never.
- NOTES: FilterDescendantsInstances + FilterType still work but are superseded by ExcludeInstances/IncludeInstances (can be combined; exclusion wins).
- DETECT: `RaycastFilterType\.(Blacklist|Whitelist)`
- DETECTING FIXTURE: `params.FilterType = Enum.RaycastFilterType.Blacklist -- removed enum item, intentional fixture`
- VERIFY: api:Enum.RaycastFilterType, api:RaycastParams.ExcludeInstances

### `query-filterdescendants` — superseded (seen 2020-2025)
- OLD: `params.FilterDescendantsInstances = {char}; params.FilterType = Enum.RaycastFilterType.Exclude`
- NEW: `params.ExcludeInstances = {char}`
- WHY: Docs: superseded by ExcludeInstances/IncludeInstances for new work.
- OLD STILL OK WHEN: Existing code keeps working.
- API COVERAGE: `OverlapParams.FilterDescendantsInstances`, `RaycastParams.FilterDescendantsInstances`
- DETECT: `FilterDescendantsInstances`
- DETECTING FIXTURE: `params.FilterDescendantsInstances = {character}`
- VERIFY: api:RaycastParams.FilterDescendantsInstances, api:RaycastParams.ExcludeInstances, api:OverlapParams.FilterDescendantsInstances, cd:reference/engine/datatypes/OverlapParams, cd:reference/engine/datatypes/RaycastParams

### `query-region3` — deprecated (seen 2012-2021)
- OLD: `workspace:FindPartsInRegion3(Region3.new(a, b)) / IsRegion3Empty`
- NEW: `workspace:GetPartBoundsInBox(cframe, size, overlapParams) / GetPartBoundsInRadius / GetPartsInPart`
- WHY: Deprecated; new queries support rotation, OverlapParams, collision groups, MaxParts.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `WorldRoot.FindPartsInRegion3`, `WorldRoot.FindPartsInRegion3WithIgnoreList`, `WorldRoot.FindPartsInRegion3WithWhiteList`, `WorldRoot.IsRegion3Empty`, `WorldRoot.IsRegion3EmptyWithIgnoreList`, `WorldRoot.findPartsInRegion3`
- DETECT: `:(?:FindPartsInRegion3(?:WithIgnoreList|WithWhiteList)?|IsRegion3Empty(?:WithIgnoreList)?|findPartsInRegion3)\s*\(`
- DETECTING FIXTURE: `workspace:FindPartsInRegion3(region)`
- VERIFY: api:WorldRoot.FindPartsInRegion3, api:WorldRoot.GetPartBoundsInBox, cd:reference/engine/classes/WorldRoot, api:WorldRoot.FindPartsInRegion3WithIgnoreList, api:WorldRoot.FindPartsInRegion3WithWhiteList, api:WorldRoot.IsRegion3Empty, api:WorldRoot.IsRegion3EmptyWithIgnoreList, api:WorldRoot.findPartsInRegion3

### `query-addtofilter` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `RaycastParams.AddToFilter / OverlapParams.AddToFilter`
- NEW: `Update ExcludeInstances or IncludeInstances on the matching parameter object`
- WHY: AddToFilter mutates the superseded FilterDescendantsInstances list, whose meaning depended on FilterType.
- OLD STILL OK WHEN: Existing correctly configured filters can remain; migrate the list and mode together.
- API COVERAGE: `OverlapParams.AddToFilter`, `RaycastParams.AddToFilter`
- DETECT: `:AddToFilter\s*\(`
- DETECTING FIXTURE: `params:AddToFilter(character)`
- VERIFY: api:RaycastParams.AddToFilter, api:OverlapParams.AddToFilter, api:RaycastParams.ExcludeInstances, api:RaycastParams.IncludeInstances, api:OverlapParams.ExcludeInstances, api:OverlapParams.IncludeInstances, cd:reference/engine/datatypes/RaycastParams, cd:reference/engine/datatypes/OverlapParams

### `query-filtertype` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `RaycastParams.FilterType / OverlapParams.FilterType`
- NEW: `Use ExcludeInstances / IncludeInstances explicitly on RaycastParams or OverlapParams`
- WHY: FilterType is superseded along with FilterDescendantsInstances. Exclude and Include enum items still exist for compatibility.
- OLD STILL OK WHEN: A working old-style filter can remain; changing only the mode or only the list can change query results.
- API COVERAGE: `OverlapParams.FilterType`, `RaycastParams.FilterType`
- DETECT: `\.FilterType\s*=`
- DETECTING FIXTURE: `params.FilterType = Enum.RaycastFilterType.Exclude`
- VERIFY: api:RaycastParams.FilterType, api:OverlapParams.FilterType, api:RaycastParams.ExcludeInstances, api:OverlapParams.IncludeInstances, cd:reference/engine/datatypes/RaycastParams, cd:reference/engine/datatypes/OverlapParams

## animation

### `anim-humanoid-load` — deprecated (seen 2014-2021)
- OLD: `humanoid:LoadAnimation(anim) / animationController:LoadAnimation(anim)`
- NEW: `animator:LoadAnimation(anim) where animator = humanoid:FindFirstChildOfClass("Animator")`
- WHY: Deprecated in favour of Animator (explicit, replicates correctly).
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- NOTES: Create the Animator on the server under the Humanoid/AnimationController so tracks replicate; the owning player can load/play animations for their character from the client. Detector requires receiver review because Animator:LoadAnimation is current.
- API COVERAGE: `AnimationController.LoadAnimation`, `Humanoid.LoadAnimation`
- DETECT: `:LoadAnimation\s*\(`
- DETECTING FIXTURE: `humanoid:LoadAnimation(animation)`
- VERIFY: api:Humanoid.LoadAnimation, api:AnimationController.LoadAnimation, api:Animator.LoadAnimation, cd:reference/engine/classes/AnimationController, cd:reference/engine/classes/Humanoid

### `anim-keyframereached` — pattern (seen 2014-2020)
- OLD: `track.KeyframeReached:Connect(function(name) if name == "Hit" ...)`
- NEW: `track:GetMarkerReachedSignal("Hit"):Connect(fn) with animation events/markers`
- WHY: Markers are explicit events in the Animation Editor; KeyframeReached relies on keyframe naming.
- OLD STILL OK WHEN: KeyframeReached still works.
- NOTES: Markers are cosmetic on clients — no authoritative damage from them.
- DETECT: `KeyframeReached`
- DETECTING FIXTURE: `track.KeyframeReached:Connect(onKeyframe)`
- VERIFY: api:AnimationTrack.GetMarkerReachedSignal

### `anim-r6-body-parts` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Humanoid.LeftLeg / Humanoid.RightLeg / Humanoid.Torso`
- NEW: `Inspect RigType and resolve the intended rig part explicitly; Humanoid.RootPart for the root driving part`
- WHY: These compatibility properties only work with R6 and are not a rig-independent body-part API.
- OLD STILL OK WHEN: An explicitly R6-only legacy rig with known behaviour.
- NOTES: R15 has upper/lower legs and feet. Choose the part needed by the feature; do not blindly map LeftLeg to one R15 segment.
- API COVERAGE: `Humanoid.LeftLeg`, `Humanoid.RightLeg`, `Humanoid.Torso`
- DETECT: `[.:]LeftLeg\b|[.:]RightLeg\b|[.:]Torso\b`
- DETECTING FIXTURE: `local leg = humanoid.LeftLeg`
- VERIFY: api:Humanoid.LeftLeg, api:Humanoid.RightLeg, api:Humanoid.Torso, api:Humanoid.RigType, api:Humanoid.RootPart, api:Instance.FindFirstChild, cd:reference/engine/classes/Humanoid

### `anim-humanoid-aliases` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Humanoid.loadAnimation / Humanoid.maxHealth / Humanoid.takeDamage`
- NEW: `Animator:LoadAnimation; Humanoid.MaxHealth / TakeDamage`
- WHY: PascalCase health members are current, but loadAnimation must migrate through Animator rather than the deprecated Humanoid:LoadAnimation alias.
- OLD STILL OK WHEN: Existing health aliases can migrate gradually; verify Animator creation and replication before migrating animations.
- API COVERAGE: `Humanoid.loadAnimation`, `Humanoid.maxHealth`, `Humanoid.takeDamage`
- DETECT: `[.:]loadAnimation\b|[.:]maxHealth\b|[.:]takeDamage\b`
- DETECTING FIXTURE: `humanoid:loadAnimation(animation)`
- VERIFY: api:Humanoid.loadAnimation, api:Humanoid.maxHealth, api:Humanoid.takeDamage, api:Animator.LoadAnimation, api:Humanoid.MaxHealth, api:Humanoid.TakeDamage, cd:reference/engine/classes/Humanoid

### `anim-playing-tracks` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Humanoid.GetPlayingAnimationTracks / AnimationController.GetPlayingAnimationTracks`
- NEW: `Animator:GetPlayingAnimationTracks()`
- WHY: The methods moved to Animator; resolve the same server-created Animator that owns the tracks.
- OLD STILL OK WHEN: Read-only legacy tooling can migrate gradually.
- API COVERAGE: `AnimationController.GetPlayingAnimationTracks`, `Humanoid.GetPlayingAnimationTracks`
- DETECT: `[.:]GetPlayingAnimationTracks\b|[.:]GetPlayingAnimationTracks\b`
- DETECTING FIXTURE: `local tracks = humanoid:GetPlayingAnimationTracks()`
- VERIFY: api:Humanoid.GetPlayingAnimationTracks, api:AnimationController.GetPlayingAnimationTracks, api:Animator.GetPlayingAnimationTracks, cd:reference/engine/classes/Humanoid, cd:reference/engine/classes/AnimationController

### `anim-played-signal` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Humanoid.AnimationPlayed / AnimationController.AnimationPlayed`
- NEW: `Animator.AnimationPlayed:Connect(handler)`
- WHY: The animation event belongs to the Animator that owns playback.
- OLD STILL OK WHEN: Existing observers can migrate when the rig lifecycle is updated.
- API COVERAGE: `AnimationController.AnimationPlayed`, `Humanoid.AnimationPlayed`
- DETECT: `[.:]AnimationPlayed\b|[.:]AnimationPlayed\b`
- DETECTING FIXTURE: `humanoid.AnimationPlayed:Connect(onTrack)`
- VERIFY: api:Humanoid.AnimationPlayed, api:AnimationController.AnimationPlayed, api:Animator.AnimationPlayed, cd:reference/engine/classes/Humanoid, cd:reference/engine/classes/AnimationController

### `anim-keyframe-provider-async` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `KeyframeSequenceProvider.GetAnimations / KeyframeSequenceProvider.GetKeyframeSequence / KeyframeSequenceProvider.GetKeyframeSequenceById`
- NEW: `GetAnimationsAsync / GetKeyframeSequenceAsync on KeyframeSequenceProvider`
- WHY: The synchronous methods are deprecated; use the yielding asynchronous API and handle failures.
- OLD STILL OK WHEN: Existing tooling can migrate gradually after checking call context and asset permissions.
- NOTES: Verify API security before moving provider calls from a plugin into game code.
- API COVERAGE: `KeyframeSequenceProvider.GetAnimations`, `KeyframeSequenceProvider.GetKeyframeSequence`, `KeyframeSequenceProvider.GetKeyframeSequenceById`
- DETECT: `[.:]GetAnimations\b|[.:]GetKeyframeSequence\b|[.:]GetKeyframeSequenceById\b`
- DETECTING FIXTURE: `provider:GetKeyframeSequence(id)`
- VERIFY: api:KeyframeSequenceProvider.GetAnimations, api:KeyframeSequenceProvider.GetKeyframeSequence, api:KeyframeSequenceProvider.GetKeyframeSequenceById, api:KeyframeSequenceProvider.GetAnimationsAsync, api:KeyframeSequenceProvider.GetKeyframeSequenceAsync, cd:reference/engine/classes/KeyframeSequenceProvider

### `anim-clip-provider-async` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `AnimationClipProvider.GetAnimationClip / AnimationClipProvider.GetAnimationClipById / AnimationClipProvider.GetAnimations`
- NEW: `AnimationClipProvider:GetAnimationClipAsync / GetAnimationsAsync`
- WHY: The old clip loads can freeze while loading; the documented Async variants yield instead.
- OLD STILL OK WHEN: Existing tooling can migrate gradually after checking permissions and failure paths.
- API COVERAGE: `AnimationClipProvider.GetAnimationClip`, `AnimationClipProvider.GetAnimationClipById`, `AnimationClipProvider.GetAnimations`
- DETECT: `[.:]GetAnimationClip\b|[.:]GetAnimationClipById\b|[.:]GetAnimations\b`
- DETECTING FIXTURE: `provider:GetAnimationClip(id)`
- VERIFY: api:AnimationClipProvider.GetAnimationClip, api:AnimationClipProvider.GetAnimationClipById, api:AnimationClipProvider.GetAnimations, api:AnimationClipProvider.GetAnimationClipAsync, api:AnimationClipProvider.GetAnimationsAsync, cd:reference/engine/classes/AnimationClipProvider

## players

### `async-loadcharacter` — deprecated (seen 2006-2025)
- OLD: `player:LoadCharacter()`
- NEW: `player:LoadCharacterAsync()`
- WHY: 2025-26 *Async rename; old name deprecated.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `Player.LoadCharacter`
- DETECT: `:LoadCharacter\s*\(`
- DETECTING FIXTURE: `player:LoadCharacter()`
- VERIFY: api:Player.LoadCharacter, api:Player.LoadCharacterAsync, cd:reference/engine/classes/Player

### `async-group` — deprecated (seen 2008-2025)
- OLD: `player:IsInGroup(id) / player:GetRankInGroup(id) / player:GetRoleInGroup(id)`
- NEW: `player:IsInGroupAsync(id); GroupService:GetRolesInGroupAsync(userId, groupId) (all public roles)`
- WHY: *Async renames; GetRankInGroupAsync/GetRoleInGroupAsync also superseded by GroupService:GetRolesInGroupAsync.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- NOTES: These yield: wrap in pcall, cache per session.
- API COVERAGE: `Player.GetRankInGroup`, `Player.GetRoleInGroup`, `Player.IsInGroup`
- DETECT: `:(IsInGroup|GetRankInGroup|GetRoleInGroup)\s*\(`
- DETECTING FIXTURE: `player:IsInGroup(groupId)`
- VERIFY: api:Player.IsInGroup, api:Player.IsInGroupAsync, api:GroupService.GetRolesInGroupAsync, api:Player.GetRankInGroup, cd:reference/engine/classes/Player, api:Player.GetRoleInGroup

### `async-friends` — deprecated (seen 2010-2025)
- OLD: `player:IsFriendsWith(userId) / GetFriendsOnline()`
- NEW: `player:IsFriendsWithAsync(userId) / GetFriendsOnlineAsync()`
- WHY: *Async rename.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `Player.GetFriendsOnline`, `Player.IsFriendsWith`, `Player.isFriendsWith`
- DETECT: `:(?:IsFriendsWith|isFriendsWith|GetFriendsOnline)\s*\(`
- DETECTING FIXTURE: `player:IsFriendsWith(userId)`
- VERIFY: api:Player.IsFriendsWith, api:Player.IsFriendsWithAsync, api:Player.GetFriendsOnline, cd:reference/engine/classes/Player, api:Player.isFriendsWith

### `async-humanoiddesc` — deprecated (seen 2019-2025)
- OLD: `humanoid:ApplyDescription(desc) / Players:GetHumanoidDescriptionFromUserId(id) / CreateHumanoidModelFromUserId / humanoid:PlayEmote`
- NEW: `ApplyDescriptionAsync / GetHumanoidDescriptionFromUserIdAsync / CreateHumanoidModelFromUserIdAsync / PlayEmoteAsync`
- WHY: *Async renames.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `Humanoid.ApplyDescription`, `Humanoid.PlayEmote`, `Players.CreateHumanoidModelFromUserId`, `Players.GetHumanoidDescriptionFromUserId`
- DETECT: `:(ApplyDescription|GetHumanoidDescriptionFromUserId|CreateHumanoidModelFromUserId|PlayEmote)\s*\(`
- DETECTING FIXTURE: `humanoid:ApplyDescription(description)`
- VERIFY: api:Humanoid.ApplyDescription, api:Players.GetHumanoidDescriptionFromUserId, api:Humanoid.PlayEmote, cd:reference/engine/classes/Humanoid, api:Players.CreateHumanoidModelFromUserId, cd:reference/engine/classes/Players

### `avatar-editor-async` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `AvatarEditorService.CheckApplyDefaultClothing / AvatarEditorService.ConformToAvatarRules / AvatarEditorService.GetAvatarRules / AvatarEditorService.GetBatchItemDetails / AvatarEditorService.GetFavorite / AvatarEditorService.GetInventory / AvatarEditorService.GetItemDetails / AvatarEditorService.GetOutfitDetails / AvatarEditorService.GetOutfits / AvatarEditorService.GetRecommendedAssets / AvatarEditorService.GetRecommendedBundles / AvatarEditorService.SearchCatalog`
- NEW: `Use each same-named AvatarEditorService method with the Async suffix`
- WHY: The pinned docs document same-behaviour Async renames. Preserve arguments, returned pages/data and existing inventory permission checks.
- OLD STILL OK WHEN: Working old callers can migrate as one reviewed rename set.
- API COVERAGE: `AvatarEditorService.CheckApplyDefaultClothing`, `AvatarEditorService.ConformToAvatarRules`, `AvatarEditorService.GetAvatarRules`, `AvatarEditorService.GetBatchItemDetails`, `AvatarEditorService.GetFavorite`, `AvatarEditorService.GetInventory`, `AvatarEditorService.GetItemDetails`, `AvatarEditorService.GetOutfitDetails`, `AvatarEditorService.GetOutfits`, `AvatarEditorService.GetRecommendedAssets`, `AvatarEditorService.GetRecommendedBundles`, `AvatarEditorService.SearchCatalog`
- DETECT: `[.:]CheckApplyDefaultClothing\b|[.:]ConformToAvatarRules\b|[.:]GetAvatarRules\b|[.:]GetBatchItemDetails\b|[.:]GetFavorite\b|[.:]GetInventory\b|[.:]GetItemDetails\b|[.:]GetOutfitDetails\b|[.:]GetOutfits\b|[.:]GetRecommendedAssets\b|[.:]GetRecommendedBundles\b|[.:]SearchCatalog\b`
- DETECTING FIXTURE: `local pages = AvatarEditorService:SearchCatalog(params)`
- VERIFY: api:AvatarEditorService.CheckApplyDefaultClothing, api:AvatarEditorService.ConformToAvatarRules, api:AvatarEditorService.GetAvatarRules, api:AvatarEditorService.GetBatchItemDetails, api:AvatarEditorService.GetFavorite, api:AvatarEditorService.GetInventory, api:AvatarEditorService.GetItemDetails, api:AvatarEditorService.GetOutfitDetails, api:AvatarEditorService.GetOutfits, api:AvatarEditorService.GetRecommendedAssets, api:AvatarEditorService.GetRecommendedBundles, api:AvatarEditorService.SearchCatalog, api:AvatarEditorService.CheckApplyDefaultClothingAsync, api:AvatarEditorService.ConformToAvatarRulesAsync, api:AvatarEditorService.GetAvatarRulesAsync, api:AvatarEditorService.GetBatchItemDetailsAsync, api:AvatarEditorService.GetFavoriteAsync, api:AvatarEditorService.GetInventoryAsync, api:AvatarEditorService.GetItemDetailsAsync, api:AvatarEditorService.GetOutfitDetailsAsync, api:AvatarEditorService.GetOutfitsAsync, api:AvatarEditorService.GetRecommendedAssetsAsync, api:AvatarEditorService.GetRecommendedBundlesAsync, api:AvatarEditorService.SearchCatalogAsync, cd:reference/engine/classes/AvatarEditorService

### `async-character-description` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Player.LoadCharacterWithHumanoidDescription`
- NEW: `Player:LoadCharacterWithHumanoidDescriptionAsync(description)`
- WHY: The character-loading method has an Async rename; loading replaces the character and yields.
- OLD STILL OK WHEN: Working old calls can migrate with the respawn lifecycle.
- API COVERAGE: `Player.LoadCharacterWithHumanoidDescription`
- DETECT: `[.:]LoadCharacterWithHumanoidDescription\b`
- DETECTING FIXTURE: `player:LoadCharacterWithHumanoidDescription(description)`
- VERIFY: api:Player.LoadCharacterWithHumanoidDescription, api:Player.LoadCharacterWithHumanoidDescriptionAsync, cd:reference/engine/classes/Player

### `async-avatar-model-description` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Players.CreateHumanoidModelFromDescription / Players.GetHumanoidDescriptionFromOutfitId`
- NEW: `Players:CreateHumanoidModelFromDescriptionAsync / GetHumanoidDescriptionFromOutfitIdAsync`
- WHY: These yielding avatar methods have explicit Async names in the current API.
- OLD STILL OK WHEN: Working old calls can migrate after preserving parameters and error handling.
- API COVERAGE: `Players.CreateHumanoidModelFromDescription`, `Players.GetHumanoidDescriptionFromOutfitId`
- DETECT: `[.:]CreateHumanoidModelFromDescription\b|[.:]GetHumanoidDescriptionFromOutfitId\b`
- DETECTING FIXTURE: `local description = Players:GetHumanoidDescriptionFromOutfitId(id)`
- VERIFY: api:Players.CreateHumanoidModelFromDescription, api:Players.GetHumanoidDescriptionFromOutfitId, api:Players.CreateHumanoidModelFromDescriptionAsync, api:Players.GetHumanoidDescriptionFromOutfitIdAsync, cd:reference/engine/classes/Players

### `async-description-reset` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Humanoid.ApplyDescriptionReset`
- NEW: `Humanoid:ApplyDescriptionResetAsync(description)`
- WHY: Use the Async rename while keeping reset semantics; ApplyDescriptionAsync is not a drop-in replacement for the reset variant.
- OLD STILL OK WHEN: A working old reset path can migrate gradually with avatar tests.
- API COVERAGE: `Humanoid.ApplyDescriptionReset`
- DETECT: `[.:]ApplyDescriptionReset\b`
- DETECTING FIXTURE: `humanoid:ApplyDescriptionReset(description)`
- VERIFY: api:Humanoid.ApplyDescriptionReset, api:Humanoid.ApplyDescriptionResetAsync, cd:reference/engine/classes/Humanoid

### `async-group-all-roles` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Player.GetRankInGroupAsync / Player.GetRoleInGroupAsync`
- NEW: `GroupService:GetRolesInGroupAsync(userId, groupId); check the documented roles result`
- WHY: Even the first-generation Async rank/role methods are deprecated because a user can hold multiple public roles.
- OLD STILL OK WHEN: Existing single-role displays can remain if their semantics are intentional; authorization must handle the complete result deliberately.
- NOTES: Do not blindly take the first role or compare the returned container to a number/string.
- API COVERAGE: `Player.GetRankInGroupAsync`, `Player.GetRoleInGroupAsync`
- DETECT: `[.:]GetRankInGroupAsync\b|[.:]GetRoleInGroupAsync\b`
- DETECTING FIXTURE: `local rank = player:GetRankInGroupAsync(groupId)`
- VERIFY: api:Player.GetRankInGroupAsync, api:Player.GetRoleInGroupAsync, api:GroupService.GetRolesInGroupAsync, cd:reference/engine/classes/Player

### `player-character-appearance` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Player.CharacterAppearance / Player.LoadCharacterAppearance / Players.GetCharacterAppearanceAsync`
- NEW: `CharacterAppearanceId for the avatar source; HumanoidDescription APIs and Humanoid:ApplyDescriptionAsync for appearance changes`
- WHY: URL- and instance-based appearance APIs are deprecated. The replacement depends on whether you set the avatar source, fetch a description or apply a specific accessory.
- OLD STILL OK WHEN: Legacy character assembly can remain until a rig/appearance migration is tested.
- API COVERAGE: `Player.CharacterAppearance`, `Player.LoadCharacterAppearance`, `Players.GetCharacterAppearanceAsync`
- DETECT: `[.:]CharacterAppearance\b|[.:]LoadCharacterAppearance\b|[.:]GetCharacterAppearanceAsync\b`
- DETECTING FIXTURE: `player:LoadCharacterAppearance(accessory)`
- VERIFY: api:Player.CharacterAppearance, api:Player.LoadCharacterAppearance, api:Players.GetCharacterAppearanceAsync, api:Player.CharacterAppearanceId, api:Players.GetHumanoidDescriptionFromUserIdAsync, api:Humanoid.ApplyDescriptionAsync, api:Humanoid.AddAccessory, cd:reference/engine/classes/Player, cd:reference/engine/classes/Players

### `player-appearance-loaded` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Player.AppearanceDidLoad`
- NEW: `Player:HasAppearanceLoaded() / CharacterAppearanceLoaded`
- WHY: Use the current explicit query and event for character appearance readiness.
- OLD STILL OK WHEN: Untouched compatibility checks; connect before relying on a one-time event and handle already-loaded characters.
- API COVERAGE: `Player.AppearanceDidLoad`
- DETECT: `[.:]AppearanceDidLoad\b`
- DETECTING FIXTURE: `if player.AppearanceDidLoad then ready() end`
- VERIFY: api:Player.AppearanceDidLoad, api:Player.HasAppearanceLoaded, api:Player.CharacterAppearanceLoaded, cd:reference/engine/classes/Player

### `player-service-aliases` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Players.NumPlayers / Players.getPlayers / Players.localPlayer / Players.numPlayers / Players.playerFromCharacter / Players.players`
- NEW: `Use #Players:GetPlayers(), Players.LocalPlayer, Players:GetPlayerFromCharacter(character)`
- WHY: Lowercase compatibility aliases and NumPlayers are deprecated. LocalPlayer is client-only.
- OLD STILL OK WHEN: Untouched working code, provided the client/server context remains correct.
- API COVERAGE: `Players.NumPlayers`, `Players.getPlayers`, `Players.localPlayer`, `Players.numPlayers`, `Players.playerFromCharacter`, `Players.players`
- DETECT: `[.:]NumPlayers\b|[.:]getPlayers\b|[.:]localPlayer\b|[.:]numPlayers\b|[.:]playerFromCharacter\b|[.:]players\b`
- DETECTING FIXTURE: `local count = Players.NumPlayers`
- VERIFY: api:Players.NumPlayers, api:Players.getPlayers, api:Players.localPlayer, api:Players.numPlayers, api:Players.playerFromCharacter, api:Players.players, api:Players.GetPlayers, api:Players.LocalPlayer, api:Players.GetPlayerFromCharacter, cd:reference/engine/classes/Players

### `player-userid-alias` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Player.userId`
- NEW: `Player.UserId`
- WHY: The lowercase userId property is a deprecated compatibility alias.
- OLD STILL OK WHEN: Untouched working code; keep stored IDs numeric and do not substitute display names.
- API COVERAGE: `Player.userId`
- DETECT: `[.:]userId\b`
- DETECTING FIXTURE: `local key = tostring(player.userId)`
- VERIFY: api:Player.userId, api:Player.UserId, cd:reference/engine/classes/Player

### `server-private-fields` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `DataModel.VIPServerId / DataModel.VIPServerOwnerId`
- NEW: `game.PrivateServerId / game.PrivateServerOwnerId`
- WHY: The old VIP names are deprecated aliases for current private-server metadata.
- OLD STILL OK WHEN: Untouched compatibility reads; a nonempty ID alone does not imply a player-owned private server.
- API COVERAGE: `DataModel.VIPServerId`, `DataModel.VIPServerOwnerId`
- DETECT: `[.:]VIPServerId\b|[.:]VIPServerOwnerId\b`
- DETECTING FIXTURE: `local id = game.VIPServerId`
- VERIFY: api:DataModel.VIPServerId, api:DataModel.VIPServerOwnerId, api:DataModel.PrivateServerId, api:DataModel.PrivateServerOwnerId, cd:reference/engine/classes/DataModel

## monetization

### `money-productinfo` — deprecated (seen 2012-2025)
- OLD: `MarketplaceService:GetProductInfo(id) / PlayerOwnsAsset(p, id) / PlayerOwnsBundle`
- NEW: `GetProductInfoAsync / PlayerOwnsAssetAsync / PlayerOwnsBundleAsync`
- WHY: *Async renames.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- NOTES: pcall + cache.
- API COVERAGE: `MarketplaceService.GetProductInfo`, `MarketplaceService.PlayerOwnsAsset`, `MarketplaceService.PlayerOwnsBundle`
- DETECT: `:(GetProductInfo|PlayerOwnsAsset|PlayerOwnsBundle)\s*\(`
- DETECTING FIXTURE: `MarketplaceService:GetProductInfo(id)`
- VERIFY: api:MarketplaceService.GetProductInfo, api:MarketplaceService.PlayerOwnsAsset, cd:reference/engine/classes/MarketplaceService, api:MarketplaceService.PlayerOwnsBundle

### `money-gamepass` — deprecated (seen 2012-2018)
- OLD: `GamePassService:PlayerHasPass(player, id)`
- NEW: `MarketplaceService:UserOwnsGamePassAsync(userId, passId) on the server`
- WHY: Deprecated service method.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `GamePassService.PlayerHasPass`
- DETECT: `PlayerHasPass`
- DETECTING FIXTURE: `GamePassService:PlayerHasPass(player, id)`
- VERIFY: api:GamePassService.PlayerHasPass, api:MarketplaceService.UserOwnsGamePassAsync, cd:reference/engine/classes/GamePassService

### `money-receipt` — pattern (seen 2014-now)
- OLD: `ProcessReceipt returns PurchaseGranted immediately after awarding in memory`
- NEW: `Record PurchaseId + grant in the profile, save durably, then PurchaseGranted; NotProcessedYet on failure; idempotent on repeat ids`
- WHY: ProcessReceipt can re-run (rejoin/another server); granting without durable record duplicates or loses purchases.
- OLD STILL OK WHEN: Never.
- NOTES: Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `\bProductPurchaseDecision\.PurchaseGranted\b`
- DETECTING FIXTURE: `return Enum.ProductPurchaseDecision.PurchaseGranted`
- VERIFY: cd:cloud-services/data-stores/player-data-purchasing, api:MarketplaceService.ProcessReceipt

### `money-badge` — deprecated (seen 2012-2025)
- OLD: `BadgeService:AwardBadge(userId, id) / UserHasBadge`
- NEW: `BadgeService:AwardBadgeAsync / UserHasBadgeAsync (server, pcall)`
- WHY: *Async renames.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `BadgeService.AwardBadge`, `BadgeService.UserHasBadge`
- DETECT: `:(AwardBadge|UserHasBadge)\s*\(`
- DETECTING FIXTURE: `BadgeService:AwardBadge(userId, badgeId)`
- VERIFY: api:BadgeService.AwardBadge, api:BadgeService.UserHasBadge, cd:reference/engine/classes/BadgeService

### `badge-info-enabled` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `BadgeService.IsDisabled`
- NEW: `BadgeService:GetBadgeInfoAsync(badgeId).IsEnabled (invert the old disabled check)`
- WHY: The old method is deprecated; the documented replacement exposes IsEnabled, which has the opposite polarity.
- OLD STILL OK WHEN: Existing checked callers can migrate gradually; never invert the boolean twice.
- API COVERAGE: `BadgeService.IsDisabled`
- DETECT: `[.:]IsDisabled\b`
- DETECTING FIXTURE: `local disabled = BadgeService:IsDisabled(id)`
- VERIFY: api:BadgeService.IsDisabled, api:BadgeService.GetBadgeInfoAsync, cd:reference/engine/classes/BadgeService

### `badge-islegal` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `BadgeService.IsLegal`
- NEW: `Remove IsLegal as an authorization check; use server-owned badge IDs and GetBadgeInfoAsync for metadata`
- WHY: IsLegal always returns true and cannot prove that a badge belongs to this experience.
- OLD STILL OK WHEN: Never as a security or eligibility check.
- API COVERAGE: `BadgeService.IsLegal`
- DETECT: `[.:]IsLegal\b`
- DETECTING FIXTURE: `if BadgeService:IsLegal(id) then grant(id) end`
- VERIFY: api:BadgeService.IsLegal, api:BadgeService.GetBadgeInfoAsync, cd:reference/engine/classes/BadgeService

### `money-premium-prompt` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `MarketplaceService.PromptPremiumPurchase`
- NEW: `MarketplaceService:PromptRobloxSubscriptionPurchase(player)`
- WHY: The API and docs supersede the Premium-specific prompt with the Roblox subscription prompt.
- OLD STILL OK WHEN: Existing working prompts can be migrated when touched; prompting alone never proves purchase completion.
- API COVERAGE: `MarketplaceService.PromptPremiumPurchase`
- DETECT: `[.:]PromptPremiumPurchase\b`
- DETECTING FIXTURE: `MarketplaceService:PromptPremiumPurchase(player)`
- VERIFY: api:MarketplaceService.PromptPremiumPurchase, api:MarketplaceService.PromptRobloxSubscriptionPurchase, cd:reference/engine/classes/MarketplaceService

## teleport

### `tp-client-teleport` — deprecated (seen 2010-2022)
- OLD: `TeleportService:Teleport(placeId, player) from a LocalScript; TeleportPartyAsync; TeleportToPrivateServer; TeleportToPlaceInstance`
- NEW: `server-side TeleportService:TeleportAsync(placeId, players, TeleportOptions)`
- WHY: Client teleports are deprecated and bypass 'Secure within universe' access control.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- NOTES: TeleportOptions: ServerInstanceId, ReservedServerAccessCode, ShouldReserveServer, SetTeleportData.
- DETECT: `TeleportService:(Teleport|TeleportPartyAsync|TeleportToPrivateServer|TeleportToPlaceInstance|TeleportToSpawnByName)\s*\(`
- DETECTING FIXTURE: `TeleportService:Teleport(placeId, player)`
- VERIFY: api:TeleportService.Teleport, api:TeleportService.TeleportAsync, cd:projects/teleport

### `tp-reserve` — deprecated (seen 2015-2025)
- OLD: `TeleportService:ReserveServer(placeId)`
- NEW: `TeleportService:ReserveServerAsync(placeId) or TeleportOptions.ShouldReserveServer = true`
- WHY: *Async rename.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `TeleportService.ReserveServer`
- DETECT: `:ReserveServer\s*\(`
- DETECTING FIXTURE: `TeleportService:ReserveServer(placeId)`
- VERIFY: api:TeleportService.ReserveServer, api:TeleportService.ReserveServerAsync, cd:reference/engine/classes/TeleportService

## data

### `data-player-save` — deprecated (seen 2008-2014)
- OLD: `player:SaveNumber('Coins', n) / LoadNumber / DataReady / WaitForDataReady / SaveInstance; DataComplexity/DataComplexityLimit/DataReady and lowercase compatibility variants`
- NEW: `DataStoreService profile per user key (UpdateAsync + session lock)`
- WHY: Legacy Data Persistence API removed/deprecated.
- OLD STILL OK WHEN: Never.
- API COVERAGE: `Player.DataComplexity`, `Player.DataComplexityLimit`, `Player.DataReady`, `Player.LoadBoolean`, `Player.LoadData`, `Player.LoadInstance`, `Player.LoadNumber`, `Player.LoadString`, `Player.SaveBoolean`, `Player.SaveData`, `Player.SaveInstance`, `Player.SaveNumber`, `Player.SaveString`, `Player.WaitForDataReady`, `Player.loadBoolean`, `Player.loadInstance`, `Player.loadNumber`, `Player.loadString`, `Player.saveBoolean`, `Player.saveInstance`, `Player.saveNumber`, `Player.saveString`, `Player.waitForDataReady`
- DETECT: `:(?:[Ss]ave|[Ll]oad)(?:Number|String|Boolean|Instance|Data)\s*\(|(?:[Ww]aitForDataReady|DataReady|DataComplexity(?:Limit)?)\b`
- DETECTING FIXTURE: `player:SaveNumber("Coins", amount)`
- VERIFY: api:Player.SaveNumber, api:Player.WaitForDataReady, cd:cloud-services/data-stores/index, api:Player.DataComplexity, cd:reference/engine/classes/Player, api:Player.DataComplexityLimit, api:Player.DataReady, api:Player.LoadBoolean, api:Player.LoadData, api:Player.LoadInstance, api:Player.LoadNumber, api:Player.LoadString, api:Player.SaveBoolean, api:Player.SaveData, api:Player.SaveInstance, api:Player.SaveString, api:Player.loadBoolean, api:Player.loadInstance, api:Player.loadNumber, api:Player.loadString, api:Player.saveBoolean, api:Player.saveInstance, api:Player.saveNumber, api:Player.saveString, api:Player.waitForDataReady

### `data-setasync-profile` — pattern (seen 2014-now)
- OLD: `store:SetAsync(key, profile) on every change / on leave only`
- NEW: `load once, mutate in memory, UpdateAsync on autosave (60–300 s, jittered), leave, BindToClose, purchases; session lock`
- WHY: SetAsync overwrites blindly (lost updates across servers), wastes budget, no lock.
- OLD STILL OK WHEN: SetAsync for brand-new keys or admin overwrite tools.
- DETECT: `:SetAsync\s*\(`
- DETECTING FIXTURE: `store:SetAsync(key, profile)`
- VERIFY: cd:cloud-services/data-stores/best-practices, cd:cloud-services/data-stores/player-data-purchasing

### `data-default-on-fail` — pattern (seen 2014-now)
- OLD: `local ok, data = pcall(GetAsync); if not ok then data = DEFAULT end  -- then saved later`
- NEW: `mark profile errored: play with defaults but never save it; block purchases/trades; retry; tell the player`
- WHY: Saving defaults after a failed load wipes the real profile.
- OLD STILL OK WHEN: Never.
- NOTES: Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `\bif\s+not\s+\w+\s+then\s+\w+\s*=\s*(?:DEFAULT\w*|\{)`
- DETECTING FIXTURE: `if not success then data = DEFAULT end`
- VERIFY: cd:cloud-services/data-stores/player-data-purchasing

### `data-onupdate` — deprecated (seen 2014-2019)
- OLD: `dataStore:OnUpdate(key, fn)`
- NEW: `MessagingService publish/subscribe to signal changes; re-read the store`
- WHY: Deprecated.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `GlobalDataStore.OnUpdate`
- DETECT: `:OnUpdate\s*\(`
- DETECTING FIXTURE: `store:OnUpdate(key, callback)`
- VERIFY: api:GlobalDataStore.OnUpdate, cd:cloud-services/cross-server-messaging, cd:reference/engine/classes/GlobalDataStore

### `data-old-limits` — outdated-fact (seen 2016-2024)
- OLD: `'60 + numPlayers × 10 requests/min per server' and '6-second write cooldown per key'`
- NEW: `Server default read/write: 60 + 40 × players per minute (configurable via SetRateLimitForRequestType); experience-wide 300 + CCU×40 (read) / ×20 (write); per-key throughput 25 MB/min read, 4 MB/min write; 4 MB value limit`
- WHY: Limit model changed; old numbers are wrong.
- OLD STILL OK WHEN: A deliberately lower project-specific budget is fine; do not present the old number as the current engine limit.
- NOTES: Check GetRequestBudgetForRequestType at runtime. Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `(?i)\b\w*(?:writecooldown|requestbudget)\w*\s*=\s*(?:6\b|60\s*\+)`
- DETECTING FIXTURE: `local writeCooldownSeconds = 6`
- VERIFY: cd:cloud-services/data-stores/error-codes-and-limits, api:DataStoreService.SetRateLimitForRequestType

### `data-datastore2` — discouraged (seen 2018-2023)
- OLD: `DataStore2 library (one data store per player + backups pattern)`
- NEW: `Single-key-per-player profiles in few data stores; official DataStore2 migration tool for existing games`
- WHY: Official best-practices: don't use DataStore2 for new experiences.
- OLD STILL OK WHEN: Existing games until migrated.
- DETECT: `DataStore2`
- DETECTING FIXTURE: `local profile = DataStore2("Coins", player)`
- VERIFY: cd:cloud-services/data-stores/best-practices

### `data-remove-version` — deprecated (seen 2021-2025)
- OLD: `dataStore:RemoveVersionAsync(key, version)`
- NEW: `Rely on versioning retention; manage via Open Cloud / Data Stores Manager`
- WHY: Deprecated.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `DataStore.RemoveVersionAsync`
- DETECT: `RemoveVersionAsync`
- DETECTING FIXTURE: `store:RemoveVersionAsync(key, version)`
- VERIFY: api:DataStore.RemoveVersionAsync, cd:reference/engine/classes/DataStore

### `data-shutdown-callback` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `DataModel.OnClose`
- NEW: `game:BindToClose(callback)`
- WHY: BindToClose allows shutdown callbacks instead of the deprecated single OnClose callback. Shutdown remains time bounded.
- OLD STILL OK WHEN: Untouched existing callback only until a reviewed save lifecycle is in place.
- NOTES: Coordinate with PlayerRemoving and ongoing saves; do not duplicate writes or promise unlimited shutdown time.
- API COVERAGE: `DataModel.OnClose`
- DETECT: `[.:]OnClose\b`
- DETECTING FIXTURE: `game.OnClose = saveAll`
- VERIFY: api:DataModel.OnClose, api:DataModel.BindToClose, cd:reference/engine/classes/DataModel

## rendering

### `phys-light-range-60` — outdated-fact (seen 2008-2023)
- OLD: `'Light Range max is 60 studs'`
- NEW: `Range is clamped to 120 studs (ExtendLightRangeTo120 is unused)`
- WHY: Engine limit changed.
- OLD STILL OK WHEN: A deliberately lower project-specific budget is fine; do not present the old number as the current engine limit.
- NOTES: Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `\bExtendLightRangeTo120\b`
- DETECTING FIXTURE: `Lighting.ExtendLightRangeTo120 = false`
- VERIFY: api:Lighting.ExtendLightRangeTo120, cd:reference/engine/classes/Lighting

### `async-preload` — deprecated (seen 2012-2020)
- OLD: `ContentProvider:Preload(id)`
- NEW: `ContentProvider:PreloadAsync({instancesOrIds}, callback?) — only for loading-screen/critical assets`
- WHY: Deprecated; preloading everything slows joins.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `ContentProvider.Preload`
- DETECT: `ContentProvider:Preload\s*\(`
- DETECTING FIXTURE: `ContentProvider:Preload(id)`
- VERIFY: api:ContentProvider.Preload, api:ContentProvider.PreloadAsync, cd:reference/engine/classes/ContentProvider

### `light-technology` — restricted (seen 2018-2025)
- OLD: `Lighting.Technology = Enum.Technology.Future  -- in a Script`
- NEW: `Set Lighting.LightingStyle = Realistic (and PrioritizeLightingQuality) in Studio's Properties window; runtime scripts can't change either`
- WHY: Technology is RobloxScriptSecurity (scripts can't read/write) and deprecated; its successors are Studio/plugin-only writes (PluginOrOpenCloud capability).
- OLD STILL OK WHEN: Never at runtime.
- NOTES: Runtime graphics presets change post effects, lights, shadows toggles, Atmosphere, particle rates instead.
- DETECT: `\.Technology\s*=`
- DETECTING FIXTURE: `Lighting.Technology = Enum.Technology.Future`
- VERIFY: api:Lighting.Technology, api:Lighting.LightingStyle, cd:environment/lighting

### `light-outlines` — removed (seen 2006-2016)
- OLD: `Lighting.Outlines = true`
- NEW: `Highlight instances or modelled/decal outlines`
- WHY: The outlines feature was removed; property deprecated.
- OLD STILL OK WHEN: Only inert legacy content; the setting cannot produce current outlines.
- API COVERAGE: `Lighting.Outlines`
- DETECT: `\.Outlines\s*=`
- DETECTING FIXTURE: `Lighting.Outlines = true`
- VERIFY: api:Lighting.Outlines, cd:reference/engine/classes/Lighting

### `light-fog-with-atmosphere` — outdated-fact (seen 2006-2020)
- OLD: `Setting Lighting.FogEnd/FogStart while an Atmosphere exists`
- NEW: `Tune Atmosphere Density/Offset/Haze/Color`
- WHY: Fog properties are ignored/hidden when Lighting contains an Atmosphere.
- OLD STILL OK WHEN: Places without Atmosphere (stylized) can still use fog.
- DETECT: `\.Fog(End|Start|Color)\s*=`
- DETECTING FIXTURE: `Lighting.FogEnd = 100`
- VERIFY: cd:reference/engine/classes/Atmosphere

### `light-compat-look` — deprecated (seen 2018-2024)
- OLD: `Technology = Compatibility for the old Roblox look`
- NEW: `Voxel-style lighting + ColorGradingEffect.TonemapperPreset = Retro, lights ≤ 1 brightness`
- WHY: Compatibility is deprecated and not selectable.
- OLD STILL OK WHEN: Existing authored appearances may remain, but deprecated Technology enum values cannot be selected for new work.
- NOTES: Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- API COVERAGE: `Enum.Technology.Compatibility`, `Enum.Technology.Legacy`, `Enum.Technology.Unified`
- DETECT: `\bTechnology\.(?:Compatibility|Legacy|Unified)\b`
- DETECTING FIXTURE: `local technology = Enum.Technology.Compatibility`
- VERIFY: api:Enum.Technology, api:ColorGradingEffect.TonemapperPreset, api:Enum.Technology.Compatibility, cd:reference/engine/enums/Technology, api:Enum.Technology.Legacy, api:Enum.Technology.Unified

### `render-highlight-31` — outdated-fact (seen 2022-2024)
- OLD: `'Only 31 Highlights can be visible at once'`
- NEW: `Client renders up to 255 simultaneous Highlights (extras silently ignored)`
- WHY: Limit changed.
- OLD STILL OK WHEN: A deliberately lower project-specific budget is fine; do not present the old number as the current engine limit.
- NOTES: Still reuse Highlights for performance. Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `(?i)\b\w*highlights?\w*\s*=\s*31\b`
- DETECTING FIXTURE: `local maxHighlights = 31`
- VERIFY: cd:effects/highlighting

### `render-surfaceappearance-swap` — restricted (seen 2021-now)
- OLD: `surfaceAppearance.ColorMap = "rbxassetid://..." at runtime`
- NEW: `Prebuild SurfaceAppearance variants in Studio and clone/swap the whole MeshPart or SurfaceAppearance; tint with SurfaceAppearance.Color; EmissiveStrength/EmissiveTint are writable`
- WHY: Map properties are PluginSecurity (docs: SurfaceAppearance can't generally be modified by scripts at runtime due to preprocessing).
- OLD STILL OK WHEN: Plugins / edit-time tools.
- DETECT: `\.(ColorMap|NormalMap|RoughnessMap|MetalnessMap)\s*=`
- DETECTING FIXTURE: `appearance.ColorMap = asset`
- VERIFY: api:SurfaceAppearance.ColorMap, api:SurfaceAppearance.Color, cd:art/modeling/surface-appearance

### `render-meshid-runtime` — restricted (seen 2017-now)
- OLD: `meshPart.MeshId = "rbxassetid://..." at runtime`
- NEW: `Clone a prebuilt MeshPart, or AssetService:CreateMeshPartAsync(meshContent) then ApplyMesh/replace`
- WHY: MeshId/MeshContent writes are NotAccessibleSecurity for scripts.
- OLD STILL OK WHEN: Studio edit time.
- DETECT: `\.MeshId\s*=`
- DETECTING FIXTURE: `meshPart.MeshId = asset`
- VERIFY: api:MeshPart.MeshId, api:AssetService.CreateMeshPartAsync

### `render-texture-realism` — pattern (seen 2008-2020)
- OLD: `Decals/Textures with baked lighting for 'realism', SmoothPlastic + BrickColor palettes`
- NEW: `PBR: MaterialVariant (tileable) / SurfaceAppearance (unique meshes) + Realistic lighting`
- WHY: Modern PBR pipeline gives physically consistent response.
- OLD STILL OK WHEN: Stylized games may keep flat textures.
- NOTES: Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `\.Material\s*=\s*Enum\.Material\.SmoothPlastic\b`
- DETECTING FIXTURE: `part.Material = Enum.Material.SmoothPlastic`
- VERIFY: cd:parts/materials, cd:art/modeling/surface-appearance

### `light-shadow-color` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Lighting.ShadowColor`
- NEW: `Remove the no-op setting; tune Lighting.Ambient / OutdoorAmbient for the intended scene lighting`
- WHY: ShadowColor is deprecated and has no current functionality. Ambient controls are artistic alternatives, not a replacement shadow-color channel.
- OLD STILL OK WHEN: Only inert legacy content; it cannot implement colored shadows.
- API COVERAGE: `Lighting.ShadowColor`
- DETECT: `[.:]ShadowColor\b`
- DETECTING FIXTURE: `Lighting.ShadowColor = Color3.new(0, 0, 0)`
- VERIFY: api:Lighting.ShadowColor, api:Lighting.Ambient, api:Lighting.OutdoorAmbient, cd:reference/engine/classes/Lighting

### `light-time-aliases` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Lighting.getMinutesAfterMidnight / Lighting.setMinutesAfterMidnight`
- NEW: `Lighting:GetMinutesAfterMidnight() / SetMinutesAfterMidnight(minutes)`
- WHY: The lowercase methods are deprecated aliases. Keep minutes as the unit.
- OLD STILL OK WHEN: Untouched working compatibility code.
- API COVERAGE: `Lighting.getMinutesAfterMidnight`, `Lighting.setMinutesAfterMidnight`
- DETECT: `[.:]getMinutesAfterMidnight\b|[.:]setMinutesAfterMidnight\b`
- DETECTING FIXTURE: `Lighting:setMinutesAfterMidnight(720)`
- VERIFY: api:Lighting.getMinutesAfterMidnight, api:Lighting.setMinutesAfterMidnight, api:Lighting.GetMinutesAfterMidnight, api:Lighting.SetMinutesAfterMidnight, cd:reference/engine/classes/Lighting

### `render-particle-spread` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `ParticleEmitter.VelocitySpread`
- NEW: `ParticleEmitter.SpreadAngle = Vector2.new(xDegrees, yDegrees)`
- WHY: SpreadAngle replaces the deprecated scalar cone spread with two angular dimensions.
- OLD STILL OK WHEN: Existing effects can remain until their appearance is compared; the mapping is not a universal visual equivalence.
- API COVERAGE: `ParticleEmitter.VelocitySpread`
- DETECT: `[.:]VelocitySpread\b`
- DETECTING FIXTURE: `emitter.VelocitySpread = 45`
- VERIFY: api:ParticleEmitter.VelocitySpread, api:ParticleEmitter.SpreadAngle, cd:reference/engine/classes/ParticleEmitter

## audio

### `audio-sound-props` — deprecated (seen 2008-2018)
- OLD: `sound.Pitch / MaxDistance / MinDistance / EmitterSize`
- NEW: `PlaybackSpeed / RollOffMaxDistance / RollOffMinDistance`
- WHY: Deprecated aliases.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `Sound.EmitterSize`, `Sound.MaxDistance`, `Sound.MinDistance`, `Sound.Pitch`
- DETECT: `\.(Pitch|MaxDistance|MinDistance|EmitterSize)\s*=`
- DETECTING FIXTURE: `sound.Pitch = 0.5`
- VERIFY: api:Sound.Pitch, api:Sound.MaxDistance, api:Sound.EmitterSize, cd:reference/engine/classes/Sound, api:Sound.MinDistance

### `audio-legacy-sound` — discouraged (seen 2008-2024)
- OLD: `Sound / SoundGroup / *SoundEffect for new audio systems`
- NEW: `Audio API: AudioPlayer → Wire → AudioEmitter / AudioDeviceOutput; AudioListener; effects (AudioReverb, AudioEqualizer...)`
- WHY: Audio docs: Sound/SoundGroup/SoundEffect are now discouraged in favour of audio objects (not deprecated).
- OLD STILL OK WHEN: Existing projects and simple one-shots.
- NOTES: Audio API adds routing, voice, acoustic simulation (occlusion/diffraction/reverb). Review candidate only: text matching cannot establish the surrounding architecture, execution side or intent; valid modern uses can match.
- DETECT: `Instance\.new\s*\(\s*["\'](?:Sound|SoundGroup|\w+SoundEffect)["\']`
- DETECTING FIXTURE: `local sound = Instance.new("Sound")`
- VERIFY: cd:audio/objects, api:AudioPlayer.Asset

### `audio-assetid` — deprecated (seen 2024-2025)
- OLD: `audioPlayer.AssetId = "..."`
- NEW: `audioPlayer.Asset = "rbxassetid://..."`
- WHY: Property renamed.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `AudioPlayer.AssetId`
- DETECT: `AudioPlayer.*\.AssetId|\.AssetId\s*=`
- DETECTING FIXTURE: `audioPlayer.AssetId = asset`
- VERIFY: api:AudioPlayer.AssetId, api:AudioPlayer.Asset, cd:reference/engine/classes/AudioPlayer

### `audio-acoustic-simulation` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `AudioEmitter.SimulationFidelity / AudioListener.SimulationFidelity`
- NEW: `AudioEmitter.AcousticSimulationEnabled / AudioListener.AcousticSimulationEnabled`
- WHY: The old fidelity property is deprecated in favor of an explicit acoustic-simulation enable flag.
- OLD STILL OK WHEN: An existing authored setup can remain until acoustic behaviour is compared; do not assign an enum to the new boolean.
- API COVERAGE: `AudioEmitter.SimulationFidelity`, `AudioListener.SimulationFidelity`
- DETECT: `[.:]SimulationFidelity\b|[.:]SimulationFidelity\b`
- DETECTING FIXTURE: `emitter.SimulationFidelity = fidelity`
- VERIFY: api:AudioEmitter.SimulationFidelity, api:AudioListener.SimulationFidelity, api:AudioEmitter.AcousticSimulationEnabled, api:AudioListener.AcousticSimulationEnabled, cd:reference/engine/classes/AudioEmitter, cd:reference/engine/classes/AudioListener

### `audio-search-subtype` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `AudioSearchParams.AudioSubtype`
- NEW: `AudioSearchParams.AudioSubType`
- WHY: The current API corrects the capital T in AudioSubType.
- OLD STILL OK WHEN: Untouched working compatibility queries.
- API COVERAGE: `AudioSearchParams.AudioSubtype`
- DETECT: `[.:]AudioSubtype\b`
- DETECTING FIXTURE: `params.AudioSubtype = subtype`
- VERIFY: api:AudioSearchParams.AudioSubtype, api:AudioSearchParams.AudioSubType, cd:reference/engine/classes/AudioSearchParams

### `audio-sound-aliases` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Sound.isPlaying / Sound.pause / Sound.play / Sound.stop`
- NEW: `Sound.IsPlaying / Pause / Play / Stop`
- WHY: These lowercase members are deprecated aliases. Existing Sound-based systems remain supported.
- OLD STILL OK WHEN: Untouched working audio; no need to redesign a stable Sound system just for these aliases.
- API COVERAGE: `Sound.isPlaying`, `Sound.pause`, `Sound.play`, `Sound.stop`
- DETECT: `[.:]isPlaying\b|[.:]pause\b|[.:]play\b|[.:]stop\b`
- DETECTING FIXTURE: `sound:play()`
- VERIFY: api:Sound.isPlaying, api:Sound.pause, api:Sound.play, api:Sound.stop, api:Sound.IsPlaying, api:Sound.Pause, api:Sound.Play, api:Sound.Stop, cd:reference/engine/classes/Sound

## ui

### `inst-message-hint` — deprecated (seen 2006-2014)
- OLD: `Instance.new("Message") / Instance.new("Hint")`
- NEW: `ScreenGui + TextLabel (client), or TextChatService system messages`
- WHY: Deprecated classes.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `Hint`, `Message`
- DETECT: `Instance\.new\s*\(\s*[\"'](Message|Hint)[\"']`
- DETECTING FIXTURE: `local hint = Instance.new("Hint")`
- VERIFY: api:Message, api:Hint, cd:reference/engine/classes/Hint, cd:reference/engine/classes/Message

### `ui-tween-methods` — deprecated (seen 2012-2020)
- OLD: `frame:TweenPosition(...) / TweenSize / TweenSizeAndPosition`
- NEW: `TweenService:Create(frame, TweenInfo.new(...), { Position = ..., Size = ... }):Play()`
- WHY: Deprecated; TweenService is general and cancellable.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `GuiObject.TweenPosition`, `GuiObject.TweenSize`, `GuiObject.TweenSizeAndPosition`
- DETECT: `:Tween(Position|Size|SizeAndPosition)\s*\(`
- DETECTING FIXTURE: `frame:TweenPosition(position)`
- VERIFY: api:GuiObject.TweenPosition, api:GuiObject.TweenSize, cd:reference/engine/classes/GuiObject, api:GuiObject.TweenSizeAndPosition

### `ui-text-props` — deprecated (seen 2008-2016)
- OLD: `label.FontSize / TextWrap / TextColor / BackgroundColor / BorderColor`
- NEW: `TextSize / TextWrapped / TextColor3 / BackgroundColor3 / BorderColor3`
- WHY: Deprecated aliases.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `GuiObject.BackgroundColor`, `GuiObject.BorderColor`, `TextBox.FontSize`, `TextBox.TextColor`, `TextBox.TextWrap`, `TextButton.FontSize`, `TextButton.TextColor`, `TextButton.TextWrap`, `TextLabel.FontSize`, `TextLabel.TextColor`, `TextLabel.TextWrap`
- DETECT: `\.(FontSize|TextWrap|TextColor|BackgroundColor|BorderColor)\s*=`
- DETECTING FIXTURE: `label.FontSize = size`
- VERIFY: api:TextLabel.FontSize, api:TextLabel.TextWrap, api:GuiObject.BackgroundColor, cd:reference/engine/classes/GuiObject, api:GuiObject.BorderColor, api:TextBox.FontSize, cd:reference/engine/classes/TextBox, api:TextBox.TextColor, api:TextBox.TextWrap, api:TextButton.FontSize, cd:reference/engine/classes/TextButton, api:TextButton.TextColor, api:TextButton.TextWrap, cd:reference/engine/classes/TextLabel, api:TextLabel.TextColor

### `ui-draggable` — deprecated (seen 2010-2023)
- OLD: `frame.Draggable = true`
- NEW: `UIDragDetector child`
- WHY: Deprecated; UIDragDetector supports more inputs.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `GuiObject.Draggable`
- DETECT: `\.Draggable\s*=`
- DETECTING FIXTURE: `frame.Draggable = true`
- VERIFY: api:GuiObject.Draggable, api:UIDragDetector, cd:reference/engine/classes/GuiObject

### `ui-guiinset` — pattern (seen 2016-2023)
- OLD: `Hard-coded 36-pixel topbar offset / IgnoreGuiInset juggling`
- NEW: `ScreenGui.ScreenInsets = CoreUISafeInsets (default) / DeviceSafeInsets / TopbarSafeInsets / None`
- WHY: Topbar and device cutouts vary by device and over time.
- OLD STILL OK WHEN: GuiService:GetGuiInset is a current API; only hard-coded offsets or incorrect assumptions require migration.
- DETECT: `36\)|GetGuiInset`
- DETECTING FIXTURE: `local inset = GuiService:GetGuiInset()`
- VERIFY: api:ScreenGui.ScreenInsets, cd:ui/on-screen-containers

### `ui-resetplayergui` — deprecated (seen 2014-2018)
- OLD: `StarterGui.ResetPlayerGuiOnSpawn = false`
- NEW: `screenGui.ResetOnSpawn = false per ScreenGui`
- WHY: Deprecated global switch.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `StarterGui.ResetPlayerGuiOnSpawn`
- DETECT: `ResetPlayerGuiOnSpawn`
- DETECTING FIXTURE: `StarterGui.ResetPlayerGuiOnSpawn = false`
- VERIFY: api:StarterGui.ResetPlayerGuiOnSpawn, cd:reference/engine/classes/StarterGui

### `ui-mouseclick` — pattern (seen 2008-now)
- OLD: `button.MouseButton1Click:Connect(fn)`
- NEW: `button.Activated:Connect(fn)`
- WHY: Activated works for mouse, touch and gamepad selection.
- OLD STILL OK WHEN: Mouse-only desktop tools.
- DETECT: `MouseButton1Click`
- DETECTING FIXTURE: `button.MouseButton1Click:Connect(activate)`
- VERIFY: api:GuiButton.Activated

### `ui-transparency` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `GuiObject.Transparency`
- NEW: `GuiObject.BackgroundTransparency; configure text/image transparency separately`
- WHY: GuiObject.Transparency is a deprecated compatibility property; BackgroundTransparency expresses the background only.
- OLD STILL OK WHEN: Existing GUI code may retain it temporarily; do not rename BasePart.Transparency.
- NOTES: The detector cannot infer receiver type. BasePart.Transparency is current and must not be changed.
- API COVERAGE: `GuiObject.Transparency`
- DETECT: `[.:]Transparency\b`
- DETECTING FIXTURE: `frame.Transparency = 0.5`
- VERIFY: api:GuiObject.Transparency, api:GuiObject.BackgroundTransparency, cd:reference/engine/classes/GuiObject

### `ui-translator-async` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `LocalizationService.GetTranslatorForPlayer`
- NEW: `LocalizationService:GetTranslatorForPlayerAsync(player)`
- WHY: The yielding translator lookup has the explicit Async name.
- OLD STILL OK WHEN: Working callers can migrate gradually with fallback translations and failure handling.
- API COVERAGE: `LocalizationService.GetTranslatorForPlayer`
- DETECT: `[.:]GetTranslatorForPlayer\b`
- DETECTING FIXTURE: `local translator = LocalizationService:GetTranslatorForPlayer(player)`
- VERIFY: api:LocalizationService.GetTranslatorForPlayer, api:LocalizationService.GetTranslatorForPlayerAsync, cd:reference/engine/classes/LocalizationService

### `ui-localization-table` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `LocalizationTable.GetContents / LocalizationTable.SetContents / LocalizationTable.GetString / LocalizationTable.RemoveKey / LocalizationTable.SetEntry`
- NEW: `GetEntries / SetEntries / GetTranslator / RemoveEntry / SetEntryValue as appropriate`
- WHY: The legacy table APIs used different data/access shapes. Modern entries and Translator APIs require a deliberate argument/result migration.
- OLD STILL OK WHEN: Offline localization tooling can remain until its export/import round trip is checked.
- NOTES: Not a name-only edit: read each replacement signature and preserve keys, context, source and locale values.
- API COVERAGE: `LocalizationTable.GetContents`, `LocalizationTable.GetString`, `LocalizationTable.RemoveKey`, `LocalizationTable.SetContents`, `LocalizationTable.SetEntry`
- DETECT: `[.:]GetContents\b|[.:]SetContents\b|[.:]GetString\b|[.:]RemoveKey\b|[.:]SetEntry\b`
- DETECTING FIXTURE: `local contents = localizationTable:GetContents()`
- VERIFY: api:LocalizationTable.GetContents, api:LocalizationTable.SetContents, api:LocalizationTable.GetString, api:LocalizationTable.RemoveKey, api:LocalizationTable.SetEntry, api:LocalizationTable.GetEntries, api:LocalizationTable.SetEntries, api:LocalizationTable.GetTranslator, api:LocalizationTable.RemoveEntry, api:LocalizationTable.SetEntryValue, cd:reference/engine/classes/LocalizationTable

### `ui-localization-language` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `LocalizationTable.DevelopmentLanguage / LocalizationTable.Root`
- NEW: `LocalizationTable.SourceLocaleId; set GuiBase2d.RootLocalizationTable on the intended UI root`
- WHY: The source locale belongs to the table. Current UI-root localization assigns the table from the UI object instead of assigning a target root from the table.
- OLD STILL OK WHEN: Existing localization content can migrate after checking table ownership and fallback behaviour.
- API COVERAGE: `LocalizationTable.DevelopmentLanguage`, `LocalizationTable.Root`
- DETECT: `[.:]DevelopmentLanguage\b|[.:]Root\b`
- DETECTING FIXTURE: `local locale = localizationTable.DevelopmentLanguage`
- VERIFY: api:LocalizationTable.DevelopmentLanguage, api:LocalizationTable.Root, api:LocalizationTable.SourceLocaleId, api:GuiBase2d.RootLocalizationTable, cd:reference/engine/classes/LocalizationTable

### `ui-auto-localize` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `GuiBase2d.Localize`
- NEW: `GuiBase2d.AutoLocalize`
- WHY: AutoLocalize is the current property name for automatic UI localization.
- OLD STILL OK WHEN: Untouched compatibility settings.
- API COVERAGE: `GuiBase2d.Localize`
- DETECT: `[.:]Localize\b`
- DETECTING FIXTURE: `label.Localize = true`
- VERIFY: api:GuiBase2d.Localize, api:GuiBase2d.AutoLocalize, cd:reference/engine/classes/GuiBase2d

### `ui-selection-groups` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `GuiService.AddSelectionParent / GuiService.AddSelectionTuple / GuiService.RemoveSelectionGroup`
- NEW: `GuiObject.SelectionGroup and explicit selection navigation properties`
- WHY: SelectionGroup supersedes the old named selection-group registry. Tree-based and tuple-based selection require different layout/navigation choices.
- OLD STILL OK WHEN: Existing gamepad menus can remain until focus navigation is compared on a controller.
- API COVERAGE: `GuiService.AddSelectionParent`, `GuiService.AddSelectionTuple`, `GuiService.RemoveSelectionGroup`
- DETECT: `[.:]AddSelectionParent\b|[.:]AddSelectionTuple\b|[.:]RemoveSelectionGroup\b`
- DETECTING FIXTURE: `GuiService:AddSelectionParent("Menu", frame)`
- VERIFY: api:GuiService.AddSelectionParent, api:GuiService.AddSelectionTuple, api:GuiService.RemoveSelectionGroup, api:GuiObject.SelectionGroup, api:GuiObject.NextSelectionUp, api:GuiObject.NextSelectionDown, cd:reference/engine/classes/GuiService

### `ui-layout-custom-sort` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `UIGridStyleLayout.SetCustomSortFunction / Enum.SortOrder.Custom`
- NEW: `LayoutOrder or Name sorting with Enum.SortOrder.LayoutOrder / Name`
- WHY: Custom comparator sorting is deprecated. Compute stable LayoutOrder values when the intended order is more complex than names.
- OLD STILL OK WHEN: Existing layouts can remain while a deterministic ordering migration is checked.
- API COVERAGE: `Enum.SortOrder.Custom`, `UIGridStyleLayout.SetCustomSortFunction`
- DETECT: `[.:]SetCustomSortFunction\b|Enum[.:]SortOrder[.:]Custom\b`
- DETECTING FIXTURE: `layout:SetCustomSortFunction(compare)`
- VERIFY: api:UIGridStyleLayout.SetCustomSortFunction, api:Enum.SortOrder.Custom, api:GuiObject.LayoutOrder, api:Enum.SortOrder.LayoutOrder, api:Enum.SortOrder.Name, cd:reference/engine/classes/UIGridStyleLayout, cd:reference/engine/enums/SortOrder

## input

### `input-mouse` — deprecated (seen 2006-2016)
- OLD: `local mouse = player:GetMouse(); mouse.KeyDown:Connect(...); mouse.Button1Down`
- NEW: `UserInputService / ContextActionService / Input Action System (InputContext/InputAction/InputBinding)`
- WHY: Mouse events are superseded by UserInputService; KeyDown deprecated.
- OLD STILL OK WHEN: Mouse.Hit for quick prototypes is still available.
- API COVERAGE: `Mouse.KeyDown`, `Mouse.KeyUp`, `Mouse.keyDown`
- DETECT: `GetMouse\s*\(|\.(?:KeyDown|KeyUp|keyDown)\b`
- DETECTING FIXTURE: `mouse.KeyDown:Connect(onKey)`
- VERIFY: api:Mouse.KeyDown, cd:input/input-action-system, cd:reference/engine/classes/Mouse, api:Mouse.KeyUp, api:Mouse.keyDown

### `input-modalenabled` — deprecated (seen 2014-2024)
- OLD: `UserInputService.ModalEnabled = true`
- NEW: `GuiService.TouchControlsEnabled = false (hide touch controls)`
- WHY: Renamed/superseded.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `UserInputService.ModalEnabled`
- DETECT: `ModalEnabled`
- DETECTING FIXTURE: `UserInputService.ModalEnabled = true`
- VERIFY: api:UserInputService.ModalEnabled, api:GuiService.TouchControlsEnabled, cd:reference/engine/classes/UserInputService

### `input-bindtypes` — deprecated (seen 2014-2016)
- OLD: `ContextActionService:BindActionToInputTypes(...)`
- NEW: `ContextActionService:BindAction(name, fn, touchButton, ...inputs)`
- WHY: Deprecated.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `ContextActionService.BindActionToInputTypes`
- DETECT: `BindActionToInputTypes`
- DETECTING FIXTURE: `ContextActionService:BindActionToInputTypes("Jump", callback, false, input)`
- VERIFY: api:ContextActionService.BindActionToInputTypes, cd:reference/engine/classes/ContextActionService

### `input-vr-service` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `UserInputService.GetUserCFrame / UserInputService.UserCFrameChanged / UserInputService.UserHeadCFrame`
- NEW: `VRService:GetUserCFrame / VRService.UserCFrameChanged; request Enum.UserCFrame.Head for head pose`
- WHY: VR pose APIs moved to VRService. The deprecated head property points through another superseded input-service API.
- OLD STILL OK WHEN: Existing VR code can migrate with device tests and coordinate-space checks.
- API COVERAGE: `UserInputService.GetUserCFrame`, `UserInputService.UserCFrameChanged`, `UserInputService.UserHeadCFrame`
- DETECT: `[.:]GetUserCFrame\b|[.:]UserCFrameChanged\b|[.:]UserHeadCFrame\b`
- DETECTING FIXTURE: `local pose = UserInputService:GetUserCFrame(Enum.UserCFrame.Head)`
- VERIFY: api:UserInputService.GetUserCFrame, api:UserInputService.UserCFrameChanged, api:UserInputService.UserHeadCFrame, api:VRService.GetUserCFrame, api:VRService.UserCFrameChanged, api:Enum.UserCFrame.Head, cd:reference/engine/classes/UserInputService

### `input-touch-movement-enums` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Enum.DevTouchMovementMode.Thumbstick / Enum.DevTouchMovementMode.DPad / Enum.DevTouchMovementMode.Thumbpad`
- NEW: `Enum.DevTouchMovementMode.DynamicThumbstick`
- WHY: The old touch movement modes are deprecated and the docs recommend DynamicThumbstick.
- OLD STILL OK WHEN: Existing saved settings only while touch controls are tested; the replacement changes interaction behaviour.
- API COVERAGE: `Enum.DevTouchMovementMode.DPad`, `Enum.DevTouchMovementMode.Thumbpad`, `Enum.DevTouchMovementMode.Thumbstick`
- DETECT: `Enum[.:]DevTouchMovementMode[.:]Thumbstick\b|Enum[.:]DevTouchMovementMode[.:]DPad\b|Enum[.:]DevTouchMovementMode[.:]Thumbpad\b`
- DETECTING FIXTURE: `mode = Enum.DevTouchMovementMode.DPad`
- VERIFY: api:Enum.DevTouchMovementMode.Thumbstick, api:Enum.DevTouchMovementMode.DPad, api:Enum.DevTouchMovementMode.Thumbpad, api:Enum.DevTouchMovementMode.DynamicThumbstick, cd:reference/engine/enums/DevTouchMovementMode

## chat

### `chat-legacy` — deprecated (seen 2016-2023)
- OLD: `Legacy Lua chat (Chat service ChatModules/ChatScript forks, Chat:Chat bubbles)`
- NEW: `TextChatService (TextChannels, TextChatCommands, BubbleChatConfiguration); filtering built in`
- WHY: Legacy chat system is retired in favour of TextChatService; ChatVersion is not script-writable.
- OLD STILL OK WHEN: Only migration/archive code; current player chat should use the supported TextChatService system.
- NOTES: Player.Chatted still exists for listening.
- DETECT: `ChatService|ChatModules|:Chat\s*\(`
- DETECTING FIXTURE: `Chat:Chat(part, text)`
- VERIFY: api:TextChatService.ChatVersion, cd:chat/in-experience-text-chat

### `chat-filter-player` — deprecated (seen 2016-2020)
- OLD: `Chat:FilterStringForPlayerAsync(text, player) / TextFilterResult:GetChatForUserAsync(userId)`
- NEW: `TextChatService for chat; TextService:FilterStringAsync followed by GetNonChatStringForBroadcastAsync / GetNonChatStringForUserAsync for non-chat user text`
- WHY: The old chat-result getter is deprecated and returns an empty string. Chat filtering belongs to TextChatService; non-chat displays still need the appropriate filtered result.
- OLD STILL OK WHEN: Never GetChatForUserAsync for working chat filtering: it returns an empty string. Keep supported non-chat filtering paths for non-chat text.
- API COVERAGE: `Chat.FilterStringForPlayerAsync`, `TextFilterResult.GetChatForUserAsync`
- DETECT: `:(?:FilterStringForPlayerAsync|GetChatForUserAsync)\s*\(`
- DETECTING FIXTURE: `Chat:FilterStringForPlayerAsync(text, player)`
- VERIFY: api:Chat.FilterStringForPlayerAsync, api:TextService.FilterStringAsync, api:TextFilterResult.GetChatForUserAsync, cd:reference/engine/classes/TextFilterResult, cd:reference/engine/classes/Chat

## streaming

### `render-streamingenabled-runtime` — restricted (seen 2018-now)
- OLD: `workspace.StreamingEnabled = true in a Script`
- NEW: `Set in Studio (write security PluginSecurity); design scripts for partial worlds`
- WHY: Not scriptable.
- OLD STILL OK WHEN: Studio/plugin setup with the required write permission; never ordinary runtime game scripts.
- DETECT: `\.StreamingEnabled\s*=`
- DETECTING FIXTURE: `workspace.StreamingEnabled = true`
- VERIFY: api:Workspace.StreamingEnabled, cd:workspace/streaming/index

### `stream-pausemode` — superseded (seen 2019-2022)
- OLD: `workspace.StreamingPauseMode`
- NEW: `Workspace.StreamingIntegrityMode = PauseOutsideLoadedArea (Studio setting); Player.GameplayPaused`
- WHY: Superseded setting (both Studio-only).
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `Enum.StreamingPauseMode.ClientPhysicsPause`, `Enum.StreamingPauseMode.Default`, `Enum.StreamingPauseMode.Disabled`
- DETECT: `StreamingPauseMode`
- DETECTING FIXTURE: `workspace.StreamingPauseMode = mode`
- VERIFY: api:Workspace.StreamingPauseMode, api:Workspace.StreamingIntegrityMode, api:Enum.StreamingPauseMode.ClientPhysicsPause, cd:reference/engine/enums/StreamingPauseMode, api:Enum.StreamingPauseMode.Default, api:Enum.StreamingPauseMode.Disabled

### `stream-interpolation-throttling` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Workspace.InterpolationThrottling`
- NEW: `Remove this obsolete setting; measure current replication/rendering behaviour before tuning supported systems`
- WHY: The deprecated setting no longer takes effect and writing it is PluginSecurity, not a game-script capability.
- OLD STILL OK WHEN: Only inert saved legacy settings; never a runtime performance toggle.
- API COVERAGE: `Workspace.InterpolationThrottling`
- DETECT: `[.:]InterpolationThrottling\b`
- DETECTING FIXTURE: `workspace.InterpolationThrottling = mode`
- VERIFY: api:Workspace.InterpolationThrottling, cd:reference/engine/classes/Workspace

## terrain

### `terrain-legacy-cells` — removed (seen 2008-2016)
- OLD: `Terrain:SetCell / GetCell / SetCells / AutowedgeCell`
- NEW: `FillBlock/FillBall/WriteVoxels/ReadVoxels (smooth terrain)`
- WHY: Legacy terrain engine removed.
- OLD STILL OK WHEN: Never.
- API COVERAGE: `Terrain.AutowedgeCell`, `Terrain.AutowedgeCells`, `Terrain.GetCell`, `Terrain.SetCell`, `Terrain.SetCells`
- DETECT: `:(SetCell|GetCell|SetCells|AutowedgeCells?)\s*\(`
- DETECTING FIXTURE: `workspace.Terrain:SetCell(0, 0, 0, 1, 0, 0)`
- VERIFY: api:Terrain.SetCell, api:Terrain.WriteVoxels, cd:reference/engine/classes/Terrain, api:Terrain.AutowedgeCell, api:Terrain.AutowedgeCells, api:Terrain.GetCell, api:Terrain.SetCells

### `terrain-legacy-water` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Terrain.GetWaterCell / Terrain.SetWaterCell`
- NEW: `Terrain:ReadVoxels / WriteVoxels or FillBlock with Enum.Material.Water`
- WHY: Legacy cell-based water APIs belong to the removed terrain engine. Smooth terrain uses material and occupancy volumes.
- OLD STILL OK WHEN: Never for current terrain generation; migration must convert cell coordinates and resolution deliberately.
- API COVERAGE: `Terrain.GetWaterCell`, `Terrain.SetWaterCell`
- DETECT: `[.:]GetWaterCell\b|[.:]SetWaterCell\b`
- DETECTING FIXTURE: `workspace.Terrain:SetWaterCell(0, 0, 0, 0, 0)`
- VERIFY: api:Terrain.GetWaterCell, api:Terrain.SetWaterCell, api:Terrain.ReadVoxels, api:Terrain.WriteVoxels, api:Terrain.FillBlock, api:Enum.Material.Water, cd:reference/engine/classes/Terrain

### `terrain-smooth-flags` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Terrain.IsSmooth / TerrainRegion.IsSmooth / Terrain.ConvertToSmooth / TerrainRegion.ConvertToSmooth`
- NEW: `Remove legacy smooth/voxel migration branches; use current terrain read/write APIs`
- WHY: The legacy terrain engine is removed. Terrain.IsSmooth is always true; these conversion-era flags/functions are obsolete.
- OLD STILL OK WHEN: Only inert compatibility checks during removal of old content.
- API COVERAGE: `Terrain.ConvertToSmooth`, `Terrain.IsSmooth`, `TerrainRegion.ConvertToSmooth`, `TerrainRegion.IsSmooth`
- DETECT: `[.:]IsSmooth\b|[.:]IsSmooth\b|[.:]ConvertToSmooth\b|[.:]ConvertToSmooth\b`
- DETECTING FIXTURE: `if workspace.Terrain.IsSmooth then build() end`
- VERIFY: api:Terrain.IsSmooth, api:TerrainRegion.IsSmooth, api:Terrain.ConvertToSmooth, api:TerrainRegion.ConvertToSmooth, api:Terrain.ReadVoxels, api:Terrain.WriteVoxels, cd:reference/engine/classes/Terrain, cd:reference/engine/classes/TerrainRegion

## pathfinding

### `path-old` — deprecated (seen 2014-2019)
- OLD: `PathfindingService:ComputeRawPathAsync / ComputeSmoothPathAsync / FindPathAsync with ClosestNoPath checks`
- NEW: `PathfindingService:CreatePath(agentParams) then path:ComputeAsync(start, goal); Status Success/NoPath; Blocked event`
- WHY: Deprecated methods and PathStatus values.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `Enum.PathStatus.ClosestNoPath`, `Enum.PathStatus.ClosestOutOfRange`, `PathfindingService.ComputeRawPathAsync`, `PathfindingService.ComputeSmoothPathAsync`
- DETECT: `Compute(Raw|Smooth)PathAsync|ClosestNoPath|ClosestOutOfRange`
- DETECTING FIXTURE: `PathfindingService:ComputeRawPathAsync(start, finish, distance)`
- VERIFY: api:PathfindingService.ComputeRawPathAsync, api:Enum.PathStatus, api:Path.ComputeAsync, api:Enum.PathStatus.ClosestNoPath, cd:reference/engine/enums/PathStatus, api:Enum.PathStatus.ClosestOutOfRange, cd:reference/engine/classes/PathfindingService, api:PathfindingService.ComputeSmoothPathAsync

### `path-waypoints` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `Path.GetPointCoordinates`
- NEW: `Path:GetWaypoints() and each waypoint.Position / Action`
- WHY: The old method returns coordinates; GetWaypoints supplies structured waypoints including jump actions.
- OLD STILL OK WHEN: Existing simple paths can migrate gradually; update loops to read .Position.
- API COVERAGE: `Path.GetPointCoordinates`
- DETECT: `[.:]GetPointCoordinates\b`
- DETECTING FIXTURE: `local points = path:GetPointCoordinates()`
- VERIFY: api:Path.GetPointCoordinates, api:Path.GetWaypoints, cd:reference/engine/classes/Path

### `path-emptycutoff` — deprecated (seen legacy code; pinned 2026 snapshot)
- OLD: `PathfindingService.EmptyCutoff`
- NEW: `Remove the ineffective setting; pass supported agent parameters to PathfindingService:CreatePath`
- WHY: EmptyCutoff belonged to the removed legacy voxel pathfinding system.
- OLD STILL OK WHEN: Only inert legacy settings; do not tune modern pathfinding through it.
- API COVERAGE: `PathfindingService.EmptyCutoff`
- DETECT: `[.:]EmptyCutoff\b`
- DETECTING FIXTURE: `PathfindingService.EmptyCutoff = 0.2`
- VERIFY: api:PathfindingService.EmptyCutoff, api:PathfindingService.CreatePath, cd:reference/engine/classes/PathfindingService

## camera

### `camera-old` — deprecated (seen 2008-2017)
- OLD: `camera.CoordinateFrame / camera.focus / camera:Interpolate(cf, focus, t)`
- NEW: `camera.CFrame / camera.Focus / TweenService on camera.CFrame (Scriptable)`
- WHY: Deprecated.
- OLD STILL OK WHEN: Untouched working legacy code may remain while behaviour is baselined; use the replacement for new work and check the notes before migrating.
- API COVERAGE: `Camera.CoordinateFrame`, `Camera.Interpolate`, `Camera.focus`
- DETECT: `\.CoordinateFrame\b|\.focus\b|:Interpolate\s*\(`
- DETECTING FIXTURE: `camera.CoordinateFrame = cf`
- VERIFY: api:Camera.CoordinateFrame, api:Camera.Interpolate, cd:reference/engine/classes/Camera, api:Camera.focus
