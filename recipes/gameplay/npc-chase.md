# Recipe: NPC chase (vision cone + LOS, hearing via noise events, fair detection, search, hiding)

## When NOT to use
Do not spawn an unbounded independent pathfinding loop per NPC; budget population-level work.

Evidence: brain/noise CLI-EXECUTED (`examples/tests/npc.spec.luau`) · perception/manager TYPECHECKED ·
**not run in Studio**. Side: server. Builds on [NPC patrol](npc-patrol.md) (same manager and mover).

## Architecture
```text
think(npc):
  vision: for each living player (nearest first): distance ≤ SightRange → inside HalfFov cone → raycast eye→head
          (skip players with attribute Hidden=true unless the chase is < 1 s old)
  hearing: Noise.loudest(events, npc, Hearing) — events from player movement speed (server-observed) and
           NpcService.noise(pos, loudness) calls from gameplay (doors, gunshots)
  Brain (pure FSM):
     sees target: first 0.6 s → Investigate (turn/walk toward) → then Chase (run)
     Chase, lost sight: keep going to last seen position 2.5 s → Search there (wander) 10 s → Patrol
     hears noise (not already investigating) → Investigate → arrive/timeout → Search → Patrol
  act: Chase with LOS on similar height → Mover direct MoveTo (precise, cheap); otherwise pathfind to goal
  catch: Chase + within 4 studs → NpcService.onCatch (default 35 damage, 1.2 s cooldown)
```
Design choices for a *fair* monster:
- **Detection grace** (0.6 s of continuous sight) — players get a moment to break line of sight; instant
  detection feels unfair.
- **Last known position, not omniscience** — after losing sight it goes where it last saw you, then searches.
- **Hearing is gameplay data**, not audio: sprinting (speed > 18) is loud, walking quiet, crouch-walking silent.
  Players can reason about it.
- **Hiding works** unless the monster saw you hide (chase < 1 s old).
- **Readable intent**: expose `State` for audio/animation cues on clients (e.g. a scream on entering Chase).

## Code
Brain (pure, tested):
<!-- code: examples/npc/ServerScriptService/Npc/Brain.luau -->
```luau
-- file: examples/npc/ServerScriptService/Npc/Brain.luau
--!strict
-- Pure decision logic for a horror-style monster: Patrol → Investigate → Chase → Search → Patrol.
-- No Roblox APIs (positions are stored, never computed) → CLI-tested in examples/tests/npc.spec.luau.
-- Status: TYPECHECKED + CLI-EXECUTED.
export type State = "Patrol" | "Investigate" | "Chase" | "Search"
export type Params = {
	detectGrace: number, -- seconds of continuous sight before a chase starts (fairness)
	loseSightTime: number, -- keep chasing to the last seen position this long after losing sight
	investigateTime: number,
	searchTime: number,
}
export type Memory = {
	state: State,
	since: number, -- when the current state started
	seenSince: number?, -- start of the current continuous sighting
	lastSeenPos: Vector3?,
	lastSeenTime: number,
	goal: Vector3?, -- where to go in Investigate/Search/Chase
}
export type Senses = {
	now: number,
	seePos: Vector3?, -- target position if visible this think
	hearPos: Vector3?, -- loudest audible noise, if any
	atGoal: boolean, -- mover reports arrival
}

local Brain = {}

function Brain.new(now: number): Memory
	return { state = "Patrol", since = now, seenSince = nil, lastSeenPos = nil, lastSeenTime = -math.huge, goal = nil }
end

local function enter(m: Memory, state: State, now: number, goal: Vector3?)
	if m.state ~= state then
		m.state = state
		m.since = now
	end
	m.goal = goal
end

-- A new noise interrupts anything except an ongoing investigation (which already has a goal).
local function heardNew(m: Memory): boolean
	return m.state ~= "Investigate"
end

-- Returns the state to act on and whether to run (true) or walk.
function Brain.think(m: Memory, s: Senses, p: Params): (State, boolean)
	local now = s.now
	if s.seePos then
		m.seenSince = m.seenSince or now
		m.lastSeenPos = s.seePos
		m.lastSeenTime = now
		if m.state == "Chase" or now - (m.seenSince :: number) >= p.detectGrace then
			enter(m, "Chase", now, s.seePos)
		else
			enter(m, "Investigate", now, s.seePos) -- noticed something: turn toward it, walk, give the player a moment
		end
	else
		m.seenSince = nil
		if m.state == "Chase" then
			if now - m.lastSeenTime > p.loseSightTime then
				enter(m, "Search", now, m.lastSeenPos)
			end
		elseif s.hearPos ~= nil and heardNew(m) then
			enter(m, "Investigate", now, s.hearPos)
		elseif m.state == "Investigate" and (s.atGoal or now - m.since > p.investigateTime) then
			enter(m, "Search", now, m.goal)
		elseif m.state == "Search" and now - m.since > p.searchTime then
			enter(m, "Patrol", now, nil)
		end
	end
	return m.state, m.state == "Chase"
end

return table.freeze(Brain)
```
<!-- /code -->

Hearing (pure, tested):
<!-- code: examples/npc/ServerScriptService/Npc/Noise.luau -->
```luau
-- file: examples/npc/ServerScriptService/Npc/Noise.luau
--!strict
-- Gameplay noise events for AI hearing (not audio). Pure; portable vectors (.X/.Y/.Z only) → CLI-tested.
-- A noise of loudness L is audible to a listener with hearing range H if distance ≤ L × H.
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Event = { pos: Vector3, loudness: number, time: number }
export type Noise = { events: { Event }, maxAge: number }

local Noise = {}

function Noise.new(maxAge: number): Noise
	return { events = {}, maxAge = maxAge }
end

function Noise.emit(n: Noise, pos: Vector3, loudness: number, now: number)
	table.insert(n.events, { pos = pos, loudness = loudness, time = now })
end

function Noise.prune(n: Noise, now: number)
	local keep = {}
	for _, e in n.events do
		if now - e.time <= n.maxAge then
			table.insert(keep, e)
		end
	end
	n.events = keep
end

-- Position of the most audible recent event for this listener, or nil.
function Noise.loudest(n: Noise, listener: Vector3, hearingRange: number, now: number): Vector3?
	local best: Event? = nil
	local bestScore = 0
	for _, e in n.events do
		if now - e.time > n.maxAge then
			continue
		end
		local dx, dy, dz = e.pos.X - listener.X, e.pos.Y - listener.Y, e.pos.Z - listener.Z
		local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
		if dist <= e.loudness * hearingRange then
			local score = e.loudness / math.max(dist, 1)
			if score > bestScore then
				best, bestScore = e, score
			end
		end
	end
	return if best then best.pos else nil
end

return Noise
```
<!-- /code -->

Vision:
<!-- code: examples/npc/ServerScriptService/Npc/Perception.luau -->
```luau
-- file: examples/npc/ServerScriptService/Npc/Perception.luau
--!strict
-- Vision for NPCs: cheap checks first (distance, view cone), raycast last. Server-side, server positions only.
-- Status: TYPECHECKED. Not run in Studio.
local Workspace = game:GetService("Workspace")

local Perception = {}

-- Returns the target's head position if `eye` can see it. `look` is the NPC's facing direction.
function Perception.canSee(eye: Vector3, look: Vector3, npc: Model, target: Model, range: number,
	halfFovDeg: number): Vector3?
	local head = target:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local offset = head.Position - eye
	local dist = offset.Magnitude
	if dist > range or dist < 1e-3 then
		return nil
	end
	if look:Dot(offset / dist) < math.cos(math.rad(halfFovDeg)) then
		return nil
	end
	local params = RaycastParams.new()
	params.ExcludeInstances = { npc }
	local hit = Workspace:Raycast(eye, offset, params)
	if hit and not hit.Instance:IsDescendantOf(target) then
		return nil -- something in the way
	end
	return head.Position
end

return Perception
```
<!-- /code -->
The perceive/act glue is in `NpcService.luau` (embedded in [NPC patrol](npc-patrol.md)).

## Hiding spots
A locker/closet uses the [interaction system](interaction-system.md): a `Hide` handler moves the character inside,
sets `character:SetAttribute("Hidden", true)` on the server, and clears it on exit. Because the attribute is set by
the server, clients can't fake being hidden.

## How to test
| Scenario | Expected |
|---|---|
| Step into view for 0.3 s, step back behind a wall | NPC turns/walks toward you (Investigate) but doesn't chase |
| Stay visible 1 s | Chase: runs, uses direct MoveTo on flat ground, pathfinding around corners |
| Break LOS and hide | goes to last seen spot, searches ~10 s, returns to patrol |
| Sprint behind it (out of view) within 40 studs | turns and investigates the noise |
| Crouch-walk behind it | not heard |
| Hide in a locker while not seen | not detected; while seen entering → still caught |
| Two players | chases the nearest visible one |

## Tuning knobs
`SightRange`, `HalfFov`, `Hearing`, `WalkSpeed`/`RunSpeed` (attributes per NPC); `BRAIN` timings in NpcService;
darkness: reduce `SightRange` when the target stands in an unlit zone (server-side zone attribute), never by reading
client lighting.

Sources: cd:characters/pathfinding, cd:workspace/raycasting, cd:reference/engine/classes/Humanoid,
cd:reference/engine/classes/WorldRoot, cd:scripting/attributes.
