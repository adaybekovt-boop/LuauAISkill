# NPC / AI: pathfinding, perception, decision making, scaling to many NPCs

Read when: enemies, monsters (horror), patrols, companions, crowds, "100 NPCs lag the server".
Related: [animation](16-animation.md), [performance](08-performance.md#cpu-humanoids--animation), [combat](15-combat.md),
recipes [NPC patrol](../../recipes/gameplay/npc-patrol.md), [NPC chase](../../recipes/gameplay/npc-chase.md).

## Architecture: one manager, many data records
Don't give every NPC its own Script with a Heartbeat loop. One server `NpcService` owns a registry of NPC records
and ticks them with **budgets and LOD**:
```text
NpcService.step(dt) on Heartbeat:
  for each NPC in round-robin slice (max N per frame / time budget):
     lod = distance to nearest player → tick interval (near: 0.1 s, mid: 0.3 s, far: 1–2 s, very far: sleep)
     if now >= npc.nextThink: perceive() → decide() → act(); npc.nextThink = now + interval(lod)
  movement is continuous (Humanoid:MoveTo / constraints), thinking is sparse
```
Record: `{ model, humanoid, root, state, target, path, waypointIndex, nextThink, lastSeenPos, lastHeard, ... }`.
Rules: thinking at 2–10 Hz is plenty; perception queries are the expensive part — cache and amortize; pathfinding is
`ComputeAsync` (yields; worker threads) — rate-limit re-paths per NPC (e.g. ≥ 0.5–1 s and only if target moved
> N studs).

## Decision making (pick the simplest that fits)
| Model | Use | Notes |
|---|---|---|
| Finite state machine | most enemies: Idle, Patrol, Investigate, Chase, Attack, Search, Return, Stunned, Dead | explicit transitions + timeouts; easy to debug (show state as attribute/BillboardGui in Studio) |
| Hierarchical FSM | bosses, complex creatures | sub-states per state |
| Behavior tree (pattern, not an engine feature) | many reusable behaviours, designers compose | build as plain Luau node functions returning Success/Failure/Running; avoid framework bloat |
| Utility AI | choosing among many actions by scores (hunger, threat, ammo) | normalized score curves; add inertia to avoid flip-flopping |
| GOAP | rarely needed in Roblox | heavy |

## Perception
| Sense | Implementation (server) |
|---|---|
| Vision | distance ≤ range → angle within FOV (`dot(look, dirToTarget) ≥ cos(halfFov)`) → raycast from NPC eyes to target head (exclude NPC; only static/world geometry in include list or exclude characters except target) → remember `lastSeenPos`, `lastSeenTime`; lighting-based stealth: reduce range if target in darkness (read a server-side "lit" attribute of zones) |
| Hearing | gameplay emits noise events `{pos, loudness, source}` (footsteps when sprinting, doors, gunshots) into a spatial list; NPC hears if `loudness / distance > threshold` (optionally attenuated by walls via a raycast count) → Investigate |
| Proximity/touch | cheap distance checks each think |
| Memory | decay suspicion over time; last known position for Search state |
Order checks cheap → expensive; raycast only for candidates passing distance and cone.

## Pathfinding essentials
```luau
--!strict
local PathfindingService = game:GetService("PathfindingService")
local path = PathfindingService:CreatePath({
	AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, AgentCanClimb = false,
	WaypointSpacing = 4,
	Costs = { Water = 20, DangerZone = math.huge },  -- materials by name, PathfindingModifier labels, PathfindingLink labels
})

local function followPath(humanoid: Humanoid, root: BasePart, goal: Vector3): boolean
	local ok = pcall(function() path:ComputeAsync(root.Position, goal) end)
	if not ok or path.Status ~= Enum.PathStatus.Success then return false end
	for _, wp in path:GetWaypoints() do
		if wp.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
		humanoid:MoveTo(wp.Position)
		local reached = humanoid.MoveToFinished:Wait()   -- MoveTo gives up after ~8 s
		if not reached then return false end              -- stuck → caller re-plans (bounded)
	end
	return true
end
print(followPath)
```
Production details (see recipes): connect `path.Blocked` to re-plan when a waypoint ahead is blocked; generation
token so an old path loop stops when a new plan starts; stuck detection (no progress for 1–2 s → jump/re-plan/
teleport-back rules); partial paths when target unreachable; direct `MoveTo` without pathfinding when there's line of
sight on flat ground (cheaper). `Enum.PathStatus` values other than `Success` and `NoPath` are deprecated.
- `PathfindingModifier` (child of a part/volume: `Label`, `PassThrough`) to mark regions (costly or passable);
  `PathfindingLink` (two attachments) for jumps/teleporters/ladders with custom labels in `Costs`.
- Navmesh is computed around static geometry; moving doors → mark with modifiers or re-plan on `Blocked`.

## Movement options for NPCs
| Option | Cost | Use |
|---|---|---|
| Humanoid + `MoveTo` | highest (stepHumanoid) | few smart NPCs needing climbing/jumping/tools |
| Humanoid with unused states disabled | lower | most enemies |
| AnimationController + `AlignPosition`/`LinearVelocity` on root | lower | many mobs, flying creatures |
| Anchored root moved by CFrame along path (server at 10–20 Hz) + client-side interpolation/animation | lowest | crowds, ambient NPCs |
Set NPC `HumanoidRootPart:SetNetworkOwner(nil)` for server-controlled NPCs near players (prevents clients from
owning and flinging them; smoother authoritative movement).

## Scaling to 100+ NPCs
- Budget per frame (e.g. ≤ 1–2 ms of NPC logic on server) — time-sliced round-robin.
- Distance LOD for thinking, animation (animate on clients only near camera), and even simulation (freeze/anchor far
  NPCs; despawn beyond range and respawn from data when players approach).
- Share perception work: one spatial grid of players/noise events updated once per tick; NPCs query the grid.
- Pathfinding: cap concurrent `ComputeAsync` jobs (queue), reuse paths for NPCs heading to the same goal, prefer
  direct movement when visible.
- Parallel Luau for pure computations (vision cones, utility scores) with results applied serially.
- Pool NPC models; avoid re-creating Humanoids.

## Horror monster specifics
Readable intent (audio tells, animation anticipation), fair detection (grace time before chase, e.g. 0.5–1 s of
visibility), search behaviour at last seen position, give-up timers, no teleporting behind the player unless it's a
designed scare, respect hiding spots (tag + server check), and difficulty via perception parameters rather than speed
alone.

## Debugging
Studio: Visualization of navigation mesh (Studio settings → Navigation mesh), draw paths with temporary parts/beams
(Studio only), expose `State` as an attribute to watch in Properties, log state transitions with reasons (throttled).

Sources: cd:characters/pathfinding, cd:reference/engine/classes/PathfindingService, cd:reference/engine/classes/Path,
cd:reference/engine/classes/PathfindingModifier, cd:reference/engine/classes/PathfindingLink,
cd:reference/engine/classes/Humanoid, cd:performance-optimization/improve, cd:scripting/multithreading,
cd:physics/network-ownership.
