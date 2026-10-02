# Performance: measure → find the bottleneck → fix → measure

## TL;DR
- Measure the limiting subsystem on target hardware.
- Profile realistic player counts and workloads.
- Reduce frequency and repeated work before micro-optimizing.
- Budget physics, rendering, networking, and memory separately.
- Keep before/after captures for performance claims.

Read when: low FPS, stutter, server lag (low heartbeat), memory growth, long load times, mobile crashes.
Luau-level details: [luau/06](../luau/06-performance-memory.md). Graphics budgets: [graphics/07 tiers](../graphics/07-quality-tiers.md).
Recipe: [performance pass on a heavy scene](../../recipes/graphics/heavy-scene-performance-pass.md).

## Budgets and truths
- 60 FPS = 16.67 ms/frame; 30 FPS = 33.33 ms. Consistency beats average: one 400 ms frame among 59 fast ones is a
  visible hitch. Target p95/p99 frame time, not mean FPS.
- Most Roblox players are on phones/tablets. Profile on a mid-range mobile device; a desktop with a 60 FPS cap hides
  4 ms vs 16 ms differences.
- The server has no renderer but runs physics, scripts, replication for everyone: its "heartbeat" (up to 60 Hz)
  dropping hurts every client (latency, rubber-banding).

## Tools (and what each answers)
| Tool | Open | Answers |
|---|---|---|
| MicroProfiler | Ctrl+F6 (Studio/desktop client); mobile: Settings → MicroProfiler On → browse `http://<device-ip>:1338` | which engine task made this frame long; your `debug.profilebegin` labels |
| Developer Console | F9 (client), server tabs if permitted | Memory (LuaHeap, InstanceCount, PlaceScriptMemory, PhysicsParts, Graphics*), Network, Scripts rate, Log |
| Render Stats | Shift+F2 (client) / Studio Render Stats | draw calls, triangles, timing |
| Script Profiler | Studio → Script Profiler (client/server) | which Luau functions take CPU (native-marked functions shown) |
| Luau heap profiler | Studio memory tools | which scripts/tables hold memory; snapshot diff |
| Scene Analysis | Studio during play/test | instance composition, triangle/draw composition, script memory, unparented instances |
| Network simulator | Studio | latency/packet loss behaviour |
| Device emulator | Studio | layout per screen, not GPU speed |

### Reading the MicroProfiler
Frame bar colours: **orange** = worker jobs (scripts/physics/animation) longer than render; **blue** = render
thread bound (draw calls, lighting, object density); **red** = render bound + GPU wait > 2.5 ms (fill-rate,
textures, effects). Colour is a hint; frame time is the goal. Threads: `RBX Main` (input, Humanoid, animation,
tweens, sound, script resumes), `RBX Worker` (network, physics, pathfinding), GPU/render thread (prepare →
perform → present). Ctrl+F finds the worst instance of a label in the dump.

| MicroProfiler label | Meaning | Usual fix |
|---|---|---|
| `RunService.PreRender`/`PreSimulation`/`PostSimulation`/`Heartbeat` (+ your labels) | Luau per-frame work | throttle, move off per-frame, fewer connections, [luau/06](../luau/06-performance-memory.md) |
| `physicsStepped`, `worldStep` | physics simulation | anchor static parts, fewer assemblies/constraints, simpler collision |
| `stepHumanoid` | Humanoid control | fewer Humanoids, disable unused states, AnimationController for static NPCs |
| `stepAnimation` | animation | animate NPCs on clients, only near players, fewer tracks |
| `updateInvalidatedFastClusters` (> 4 ms) | avatar/skinned mesh rebuilds | avoid resizing/re-parenting avatar parts; pool NPCs; animate via `Motor6D.Transform`, not C0/C1 |
| `Perform/Scene/computeLightingPerform`, `LightGridCPU`, `ShadowMapSystem` | lights & shadows | fewer/smaller shadow-casting lights, `CastShadow=false` on small parts |
| `Perform/Scene/UpdateView` | render prep + particles | fewer emitters/particles, avoid per-frame emitter property changes |
| `Perform/Scene/RenderView` | draw + post | fewer draw calls, less transparency, cheaper post |
| `ProcessPackets` | incoming network | fewer/smaller remotes and property changes |
| `Allocate Bandwidth and Run Senders` | outgoing (server) | replicate less, stop server-side tweens |
| `GC` | Luau garbage collection cycle | reduce allocations in hot paths |

## Workflow
1. Reproduce: fixed route/camera, same device, same player count, same graphics level; warm up 30 s.
2. Capture baseline (MicroProfiler dump, p50/p95 frame time, memory numbers).
3. Classify frame bars (orange/blue/red) → pick the top label by total time.
4. Form one hypothesis; change one thing; recapture under identical conditions.
5. Keep the change only if the metric improved and visuals/gameplay are unchanged. Record numbers.

## CPU: scripts
| Problem | Fix |
|---|---|
| Expensive work bound to `Heartbeat/PreRender` | run at 5–20 Hz with an accumulator; event-driven where possible |
| One connection per object per frame (100 NPC scripts each on Heartbeat) | one manager loop iterating a registry; LOD tick rates by distance |
| Scanning `GetDescendants()`/`GetTagged()` each frame | maintain registries via events/tags |
| Big one-shot work (map gen, deserialization) freezes a frame | chunk across frames (`task.wait()` every N items / time budget), or parallel Luau |
| Server `TweenService` on replicated parts | tween on clients (server tweens replicate every frame and jitter) |
| Raycasts/overlap queries per frame for many actors | cache, reduce frequency, spatial partition, `OverlapParams.MaxParts` |

Time-sliced work pattern:
```luau
--!strict
local function processBudgeted<T>(items: { T }, budgetSeconds: number, fn: (T) -> ())
	local start = os.clock()
	for i, item in items do
		fn(item)
		if os.clock() - start > budgetSeconds then
			task.wait()                -- yield to next frame, keep frame time bounded
			start = os.clock()
		end
	end
end
processBudgeted({ 1, 2, 3 }, 0.002, function(n: number) print(n) end)
```

## CPU: physics
- Anchor everything that doesn't move. Unanchored decorative debris = continuous cost + network ownership churn.
- Collision: `CanCollide`, `CanTouch`, `CanQuery` all false for pure decoration; mesh `CollisionFidelity` Box/Hull
  for small/medium props (set in Studio — not scriptable at runtime); build big complex colliders from simple
  invisible parts.
- Fewer constraints/joints per mechanism; no self-collision in ragdolls (NoCollisionConstraint / limits).
- Adaptive timestepping (default `Workspace.PhysicsSteppingMethod = Adaptive`, 60/120/240 Hz per mechanism) — keep
  it unless you need fixed accuracy.
- Sleep system: resting assemblies sleep; don't keep nudging them (setting `CFrame`/velocity wakes them).

## CPU: Humanoids & animation
- Humanoid is expensive. Static NPCs: `AnimationController` + `Animator`, no Humanoid. Moving NPCs: consider custom
  movement (AlignPosition/LinearVelocity or CFrame on anchored root) + AnimationController.
- `Humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)` etc. for states NPCs never use.
- Play NPC animations on clients (client creates Animator for server NPCs), only for NPCs near the camera.
- Pool frequently respawned NPC/character models.

## GPU / render thread
- **Draw calls**: identical `MeshPart`s (same mesh content + same SurfaceAppearance/texture/material) are instanced
  into one draw call. Upload each mesh once and duplicate in Studio; importing a whole map at once creates
  duplicate mesh ids that break instancing.
- Decals, Textures, particles, SurfaceGuis batch poorly — keep counts low in dense views.
- Triangles: `MeshPart.RenderFidelity` Automatic/Performance for distant/small meshes; avoid Precise en masse.
- Shadows: shadow-casting lights are the most expensive lights. `Light.Shadows = false` for fills; small parts
  `CastShadow = false`; limit `Range`/`Angle`; toggle lights per room. Engine disables shadows below graphics
  quality level 4 automatically.
- Transparency overdraw: stacked semi-transparent layers (glass, fog cards, smoke, UI blur) multiply pixel cost;
  large full-screen particles are fill-rate killers on mobile.
- LOD: enable streaming and set models' `Model.LevelOfDetail` to SLIM (Studio setting) for distant lightweight
  representations; `Workspace.EnableSLIMAvatars` for avatars. See [streaming](10-streaming.md).
- Post-processing (Bloom, DepthOfField, SunRays) costs full-screen passes — scale by quality tier.

## Network
- Replicate on change, not per frame. Send deltas/ids, not whole inventories. Cap client→server message rate.
- Creating/destroying large instance trees at runtime (maps) is heavy → stream, chunk, or clone client-side for
  cosmetic content. Strip Animation Editor metadata (`AnimSaves`) from rigs before cloning them often.
- Effects: server sends "explosion at P", clients create visuals locally.

## Memory
- Watch `LuaHeap` and `InstanceCount` in the Developer Console over time (server especially — it lives for hours).
- Leaks: connections on `Player`/character not disconnected (enable `Workspace.PlayerCharacterDestroyBehavior`),
  per-player tables not cleared, caches without eviction, instances parented to nil but referenced.
- Textures: GPU memory depends on pixel count (1024² = 4× 512²), not file size. Most props ≤ 512²; small UI ≤ 256².
  Use trim sheets/texture atlases; tint one texture with `SurfaceAppearance.Color` instead of uploading variants.
- Audio can be large — don't preload every sound.
- Enable instance streaming for large worlds; reduce `Persistent` models; lower stream radii on low-memory devices.

## Load times
`ContentProvider:PreloadAsync` only for loading-screen images, key UI and the spawn area. Never preload all of
Workspace; never wait on `ContentProvider.RequestQueueSize` reaching 0. Offer "skip" on long loads.

## Parallel Luau
- Put scripts under `Actor`s (one actor per independent unit: NPC, chunk worker). Scripts in the same actor run
  serially; more actors = better load balancing.
- `task.desynchronize()` or `signal:ConnectParallel(fn)` to run in parallel; `task.synchronize()` before writing
  Instances. `require` is not allowed in the parallel phase (require first).
- Thread safety per member (`python tools/api.py X.Y` → "parallel: safe / read-only / serial"); unspecified = Unsafe.
- Communicate with `Actor:SendMessage` + `BindToMessageParallel`, or `SharedTable` for large shared state.
- Good fits: many raycasts for hit validation, procedural generation math, pathfinding-grid computations, NPC
  sensing. Bad fits: code that mostly writes Instance properties.

Sources: cd:performance-optimization/index, cd:performance-optimization/identify, cd:performance-optimization/improve,
cd:performance-optimization/design, cd:performance-optimization/microprofiler/index,
cd:performance-optimization/microprofiler/use-microprofiler, cd:performance-optimization/microprofiler/tag-table,
cd:performance-optimization/scene-analysis, cd:scripting/multithreading, cd:physics/adaptive-timestepping,
cd:physics/sleep-system, cd:studio/optimization/scriptprofiler, cd:studio/optimization/memory-usage,
cd:studio/developer-console, cd:workspace/streaming/slim.
