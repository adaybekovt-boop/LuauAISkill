# Recipe: performance pass on a heavy scene (measure → fix → measure)

## When NOT to use
Do not optimize by visual guesswork; capture the limiting subsystem and a reproducible baseline first.

## Architecture
Measure the scene, identify its bottleneck, change one subsystem, and compare the same capture.

Evidence: procedure based on the creator-docs performance guides; no numbers here are measurements — **your
MicroProfiler captures are the only evidence**. Chapter: [performance](../../handbook/roblox/08-performance.md).

## 0. Set up a repeatable measurement
- Pick 3 fixed camera positions (the heaviest view, a typical view, a combat/NPC-heavy moment) and a 30 s route.
- Devices: your PC **and** a low/mid phone (Device Emulator is not a performance test).
- Record: frame time (ms) avg + p95, MicroProfiler capture (Ctrl+F6, then dump), Developer Console (F9) → Memory
  (LuaHeap, Instances, Graphics…), Render stats (Shift+F2), server heartbeat (Server Stats / server MicroProfiler).
- Change **one thing at a time**; re-measure the same shots; keep a table.

## 1. Classify the bottleneck (MicroProfiler)
| Evidence | Bound | Go to |
|---|---|---|
| long `Render`/`Prepare`/GPU wait, many draw calls, high triangle counts | rendering | 2 |
| `computeLightingPerform`, `ShadowMapSystem` large | lighting/shadows | 3 |
| script labels (`Heartbeat`, your `debug.profilebegin` names) large | Luau | 4 |
| `stepHumanoid`, `stepAnimation`, `Physics` | characters/physics | 5 |
| spikes labelled `GC` | allocations | 4 |
| `ProcessPackets`, network queues | replication | 6 |
| memory climbing over time | leaks | 7 |

## 2. Rendering
- Instance counts: merge static decoration (unions/meshes), reuse identical meshes (instancing works best with
  identical MeshId + material), remove invisible/buried parts, `CastShadow = false` on small props.
- Level of detail: `Model.LevelOfDetail`/`ModelLevelOfDetail` for distant models (SLIM needs a published place +
  Team Create), streaming for large maps; fog to hide the streaming edge.
- Transparency: overlapping transparent parts/particles are expensive (overdraw) — reduce particle `Rate`/`Size`,
  avoid layered glass.
- Textures: size budget (guideline 256² per ~2×2×2 studs of object), fewer unique textures on mobile.

## 3. Lighting
- Count shadowed local lights visible at once; turn off `Shadows` on fills; shrink `Range` where pools overlap.
- Emissive + fewer real lights for repetitive fixtures (see [Backrooms office](backrooms-fluorescent-office.md)).
- Client-side culling of lights in rooms the camera can't see, or rely on streaming.

## 4. Luau
- One loop per system, not per object; event-driven instead of polling; LOD/time budgets for AI.
- Hot paths: avoid per-frame table/closure allocation (`GC` spikes), cache `FindFirstChild` results, use `buffer` for
  packed data, `--!native` only for measured numeric hot spots.
- Label your work: `debug.profilebegin("Npc.think")` … `debug.profileend()` to see it in captures.

## 5. Characters & physics
- NPCs: disable unused Humanoid states, animate on clients near the camera only, anchor/sleep far NPCs.
- Unanchored decoration: anchor what doesn't need physics; fewer constraints; simple collision fidelity
  (set in Studio — `CollisionFidelity` is not script-writable).

## 6. Networking
- Remote traffic: send on change, batch, cap rates; don't tween on the server (it replicates every frame).
- Creating/destroying big hierarchies replicates everything — chunk it.

## 7. Memory
- Leaks: connections not disconnected, per-player tables not cleared, caches without eviction, instances parented to
  nil but referenced. Compare LuaHeap/Instances after 10 minutes of play; Luau heap snapshots for detail.

## 8. Report template
```text
Scene / device / quality level:
Baseline: avg __ ms, p95 __ ms, draw calls __, memory __ MB (capture: file name)
Change 1: ______ → avg __ ms, p95 __ ms (kept / reverted)
Change 2: ...
Unverified: (anything not re-measured on a phone)
```

Sources: cd:performance-optimization/identify, cd:performance-optimization/improve,
cd:performance-optimization/microprofiler/use-microprofiler, cd:performance-optimization/test-on-hardware,
cd:performance-optimization/design, cd:workspace/streaming/index, cd:studio/developer-console.
