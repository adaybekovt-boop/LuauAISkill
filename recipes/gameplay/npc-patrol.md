# Recipe: NPC patrol at scale (one manager, LOD, non-blocking pathfinding)

## When NOT to use
Do not assume a valid static route remains traversable after world or streaming changes.

Evidence: brain/noise CLI-EXECUTED (`examples/tests/npc.spec.luau`, 5 tests) · manager/mover TYPECHECKED ·
**not run in Studio**. Side: server. Chapter: [NPC / AI](../../handbook/roblox/20-npc-ai.md).
Continues in [NPC chase](npc-chase.md) (perception, hearing, catching).

## Architecture
```text
Studio: NPC Model (Humanoid + HumanoidRootPart + Head) tagged "Npc", attribute PatrolRoute = "RouteA"
        workspace.PatrolRoutes.RouteA/ 01, 02, 03 ... (invisible anchored parts, sorted by name)
Server: NpcService (ONE Heartbeat connection)
   each frame: round-robin, ≤ 8 thinks and ≤ 1 ms
   think interval by distance to nearest player: <60 → 0.1 s · <150 → 0.3 s · <300 → 1 s · beyond → sleep (stop)
   think: perceive → Brain.think → act (Patrol: next route point when arrived) → Mover.update
   Mover: ComputeAsync in its own thread (generation token, ≤ 4 concurrent, ≥ 0.75 s between replans per NPC)
          waypoint following by distance checks (no MoveToFinished:Wait) · Blocked → replan
          no progress 1.5 s → jump + replan · 3× → give up (brain moves on)
```
Why this beats "a Script with while-true in every NPC":
| Naive | Problem | Here |
|---|---|---|
| per-NPC `while true do ... task.wait() end` | 100 NPCs = 100 threads doing full work every frame | one loop, budgeted, LOD |
| `MoveToFinished:Wait()` inside the loop | blocks that NPC's logic up to 8 s; can't react | distance checks each think |
| `ComputeAsync` every frame | pathfinding is the most expensive call | throttled + capped |
| client-owned NPC physics | exploiters fling NPCs; jitter | `root:SetNetworkOwner(nil)` |

## Code
Manager:
<!-- code: examples/npc/ServerScriptService/Npc/NpcService.luau -->
```luau
-- file: examples/npc/ServerScriptService/Npc/NpcService.luau
--!strict
-- NpcService: ONE Heartbeat loop drives every NPC tagged "Npc" (no per-NPC scripts or loops).
-- Per frame: round-robin over NPCs, at most MAX_THINKS_PER_FRAME thinks and ~1 ms of work. Each NPC thinks at an
-- interval chosen by distance to the nearest player (LOD); far NPCs sleep. Thinking = perceive → Brain → Mover.
-- NPC model contract: Model tagged "Npc" with Humanoid + HumanoidRootPart (+ Head). Optional attributes:
--   PatrolRoute (string: Folder name under workspace.PatrolRoutes, parts sorted by name), SightRange (60),
--   HalfFov (70), Hearing (40), WalkSpeed (9), RunSpeed (19).
-- Status: TYPECHECKED (Brain/Noise CLI-EXECUTED). Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Binder = require(ReplicatedStorage.Lib.Binder)
local Brain = require(ServerScriptService.Npc.Brain)
local Mover = require(ServerScriptService.Npc.Mover)
local Noise = require(ServerScriptService.Npc.Noise)
local Perception = require(ServerScriptService.Npc.Perception)

local MAX_THINKS_PER_FRAME = 8
local FRAME_BUDGET = 0.001 -- seconds of NPC logic per Heartbeat
local SLEEP_DISTANCE = 300
local CATCH_DISTANCE = 4
local CATCH_COOLDOWN = 1.2
local BRAIN: Brain.Params = { detectGrace = 0.6, loseSightTime = 2.5, investigateTime = 8, searchTime = 10 }

type Npc = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	mover: Mover.Mover,
	memory: Brain.Memory,
	nextThink: number,
	route: { Vector3 },
	routeIndex: number,
	atGoal: boolean,
	lastCatch: number,
	sight: number,
	halfFov: number,
	hearing: number,
	walkSpeed: number,
	runSpeed: number,
}

local NpcService = {}
local npcs: { Npc } = {}
local cursor = 1
local noise = Noise.new(1.5)
local random = Random.new()

-- Called when a chasing NPC reaches a player. Replace with your damage/jumpscare logic.
NpcService.onCatch = function(_npc: Model, player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:TakeDamage(35)
	end
end

-- Gameplay code reports loud events (doors slamming, gunshots): loudness 1 ≈ heard at `Hearing` studs.
function NpcService.noise(pos: Vector3, loudness: number)
	Noise.emit(noise, pos, loudness, os.clock())
end

local function number(model: Model, name: string, default: number): number
	local v = model:GetAttribute(name)
	return if type(v) == "number" and v == v then v else default
end

local function loadRoute(model: Model): { Vector3 }
	local routes = Workspace:FindFirstChild("PatrolRoutes")
	local name = model:GetAttribute("PatrolRoute")
	local folder = routes and type(name) == "string" and routes:FindFirstChild(name)
	local points = {}
	if folder then
		local parts = folder:GetChildren()
		table.sort(parts, function(a: Instance, b: Instance)
			return a.Name < b.Name
		end)
		for _, p in parts do
			if p:IsA("BasePart") then
				table.insert(points, p.Position)
			end
		end
	end
	return points
end

type Target = { player: Player, character: Model, root: BasePart, dist: number }

local function targets(): { Target }
	local out = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.RootPart
		if character and humanoid and root and humanoid.Health > 0 then
			table.insert(out, { player = player, character = character, root = root, dist = 0 })
		end
	end
	return out
end

local function think(npc: Npc, now: number, players: { Target })
	local pos = npc.root.Position
	local nearest = math.huge
	for _, t in players do
		t.dist = (t.root.Position - pos).Magnitude
		nearest = math.min(nearest, t.dist)
	end
	-- LOD: think less often when nobody is near; sleep entirely when far.
	if nearest > SLEEP_DISTANCE then
		if npc.mover.goal then
			Mover.stop(npc.mover)
		end
		npc.nextThink = now + 2
		return
	end
	local interval = if nearest < 60 then 0.1 elseif nearest < 150 then 0.3 else 1

	-- Perceive: nearest visible player (hidden players only while the chase is fresh).
	local head = npc.model:FindFirstChild("Head")
	local eye = if head and head:IsA("BasePart") then head.Position else pos + Vector3.new(0, 1.5, 0)
	local look = npc.root.CFrame.LookVector
	local seen: Target? = nil
	local seePos: Vector3? = nil
	for _, t in players do
		if t.dist > npc.sight or (seen and t.dist >= seen.dist) then
			continue
		end
		if t.character:GetAttribute("Hidden") == true
			and not (npc.memory.state == "Chase" and now - npc.memory.lastSeenTime < 1) then
			continue -- respect hiding spots unless the monster saw you hide
		end
		local p = Perception.canSee(eye, look, npc.model, t.character, npc.sight, npc.halfFov)
		if p then
			seen, seePos = t, p
		end
	end
	local hearPos = Noise.loudest(noise, pos, npc.hearing, now)

	local state, run = Brain.think(npc.memory, { now = now, seePos = seePos, hearPos = hearPos, atGoal = npc.atGoal },
		BRAIN)
	npc.humanoid.WalkSpeed = if run then npc.runSpeed else npc.walkSpeed
	npc.model:SetAttribute("State", state) -- visible in Studio's Properties while debugging

	-- Act.
	if state == "Patrol" then
		if #npc.route > 0 then
			if npc.atGoal then
				npc.routeIndex = npc.routeIndex % #npc.route + 1
			end
			Mover.setGoal(npc.mover, npc.route[npc.routeIndex], false, now)
		end
	elseif state == "Search" and npc.atGoal and npc.memory.goal then
		-- Wander around the last known position.
		local g = npc.memory.goal :: Vector3
		local jitter = Vector3.new(random:NextNumber(-12, 12), 0, random:NextNumber(-12, 12))
		Mover.setGoal(npc.mover, g + jitter, false, now)
	elseif npc.memory.goal then
		local goal = npc.memory.goal :: Vector3
		local direct = seen ~= nil and math.abs(goal.Y - pos.Y) < 4
		Mover.setGoal(npc.mover, goal, direct, now)
	end
	npc.atGoal = Mover.update(npc.mover, now)

	if state == "Chase" and seen and seen.dist <= CATCH_DISTANCE and now - npc.lastCatch >= CATCH_COOLDOWN then
		npc.lastCatch = now
		NpcService.onCatch(npc.model, seen.player)
	end
	npc.nextThink = now + interval * random:NextNumber(0.9, 1.1) -- jitter spreads thinks across frames
end

local noiseTimer = 0
local function step(dt: number)
	local now = os.clock()
	local players = targets()
	-- Movement noise from players: sprinting is loud, walking quiet, crouch-walking silent (speed-based).
	noiseTimer += dt
	if noiseTimer >= 0.25 then
		noiseTimer = 0
		Noise.prune(noise, now)
		for _, t in players do
			local v = t.root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			if speed > 18 then
				Noise.emit(noise, t.root.Position, 1, now)
			elseif speed > 10 then
				Noise.emit(noise, t.root.Position, 0.35, now)
			end
		end
	end
	local count = #npcs
	if count == 0 then
		return
	end
	local started = os.clock()
	local thinks = 0
	for _ = 1, count do
		if thinks >= MAX_THINKS_PER_FRAME or os.clock() - started > FRAME_BUDGET then
			break
		end
		if cursor > #npcs then
			cursor = 1
		end
		local npc = npcs[cursor]
		cursor += 1
		if now >= npc.nextThink and npc.humanoid.Health > 0 then
			thinks += 1
			think(npc, now, players)
		end
	end
end

function NpcService.start()
	Binder.bind("Npc", function(inst, cleanup)
		if not inst:IsA("Model") then
			return
		end
		local humanoid = inst:FindFirstChildOfClass("Humanoid")
		local root = inst:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or not root:IsA("BasePart") then
			warn("[Npc] missing Humanoid/HumanoidRootPart:", inst:GetFullName())
			return
		end
		if not root.Anchored then
			root:SetNetworkOwner(nil) -- server simulates it: no client flinging, smooth authoritative movement
		end
		local npc: Npc = {
			model = inst,
			humanoid = humanoid,
			root = root,
			mover = Mover.new(humanoid, root, { AgentRadius = 2, AgentHeight = 5, AgentCanJump = true }),
			memory = Brain.new(os.clock()),
			nextThink = os.clock() + random:NextNumber(0, 0.5),
			route = loadRoute(inst),
			routeIndex = 1,
			atGoal = true,
			lastCatch = -math.huge,
			sight = number(inst, "SightRange", 60),
			halfFov = number(inst, "HalfFov", 70),
			hearing = number(inst, "Hearing", 40),
			walkSpeed = number(inst, "WalkSpeed", 9),
			runSpeed = number(inst, "RunSpeed", 19),
		}
		table.insert(npcs, npc)
		cleanup:add(function()
			Mover.destroy(npc.mover)
			local i = table.find(npcs, npc)
			if i then
				table.remove(npcs, i)
			end
		end)
	end)
	RunService.Heartbeat:Connect(step)
end

return NpcService
```
<!-- /code -->

Path follower:
<!-- code: examples/npc/ServerScriptService/Npc/Mover.luau -->
```luau
-- file: examples/npc/ServerScriptService/Npc/Mover.luau
--!strict
-- Mover: non-blocking path following for one Humanoid NPC. The manager calls update() on each think; nothing here
-- waits on MoveToFinished, so one manager thread can drive hundreds of NPCs.
--   * ComputeAsync runs in its own thread; a generation token discards results of superseded plans
--   * replans are throttled per NPC and capped globally (concurrent ComputeAsync calls)
--   * Path.Blocked ahead of us → replan; no progress for STUCK_TIME → jump, then replan; repeated → give up
--   * direct mode: plain MoveTo toward a visible target on similar height (cheaper and more precise)
-- Status: TYPECHECKED. Not run in Studio.
local PathfindingService = game:GetService("PathfindingService")

local ARRIVE_DISTANCE = 3
local REPLAN_INTERVAL = 0.75
local GOAL_MOVED = 4 -- replan only if the goal moved more than this
local STUCK_TIME = 1.5
local MAX_STUCK = 3
local MAX_CONCURRENT_PLANS = 4
local MOVETO_REFRESH = 3 -- Humanoid:MoveTo gives up after ~8 s; refresh well before

export type Mover = {
	humanoid: Humanoid,
	root: BasePart,
	agent: { [string]: any },
	goal: Vector3?,
	waypoints: { PathWaypoint },
	index: number,
	generation: number,
	lastPlan: number,
	blocked: RBXScriptConnection?,
	progressDist: number,
	progressTime: number,
	stuckCount: number,
	lastMoveTo: number,
	failed: boolean, -- no path / gave up; the brain treats this like "arrived" and moves on
}

local inFlight = 0
local Mover = {}

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function Mover.new(humanoid: Humanoid, root: BasePart, agent: { [string]: any }): Mover
	return {
		humanoid = humanoid,
		root = root,
		agent = agent,
		goal = nil,
		waypoints = {},
		index = 1,
		generation = 0,
		lastPlan = -math.huge,
		blocked = nil,
		progressDist = math.huge,
		progressTime = 0,
		stuckCount = 0,
		lastMoveTo = -math.huge,
		failed = false,
	}
end

local function moveTo(m: Mover, pos: Vector3, now: number)
	m.humanoid:MoveTo(pos)
	m.lastMoveTo = now
end

local function plan(m: Mover, now: number)
	local goal = m.goal
	if not goal or inFlight >= MAX_CONCURRENT_PLANS or now - m.lastPlan < REPLAN_INTERVAL then
		return -- try again on a later think
	end
	m.lastPlan = now
	m.generation += 1
	local gen = m.generation
	inFlight += 1
	task.spawn(function()
		local path = PathfindingService:CreatePath(m.agent)
		local ok = pcall(path.ComputeAsync, path, m.root.Position, goal)
		inFlight -= 1
		if gen ~= m.generation then
			return -- superseded while computing
		end
		if m.blocked then
			m.blocked:Disconnect()
			m.blocked = nil
		end
		if not ok or path.Status ~= Enum.PathStatus.Success then
			m.waypoints, m.failed = {}, true
			return
		end
		m.waypoints, m.index, m.failed = path:GetWaypoints(), 2, false -- waypoint 1 is the start position
		m.progressDist, m.progressTime = math.huge, os.clock()
		m.blocked = path.Blocked:Connect(function(blockedIndex: number)
			if gen == m.generation and blockedIndex >= m.index then
				m.lastPlan = -math.huge -- allow an immediate replan
				plan(m, os.clock())
			end
		end)
		local wp = m.waypoints[m.index]
		if wp then
			moveTo(m, wp.Position, os.clock())
		end
	end)
end

-- Set a destination. `direct` = walk straight at it (caller verified line of sight and similar height).
function Mover.setGoal(m: Mover, goal: Vector3, direct: boolean, now: number)
	local moved = m.goal == nil or (goal - (m.goal :: Vector3)).Magnitude > GOAL_MOVED
	m.goal = goal
	if direct then
		m.generation += 1 -- cancel any path in progress
		m.waypoints = {}
		m.failed = false
		if moved or now - m.lastMoveTo > 0.25 then
			moveTo(m, goal, now)
		end
		return
	end
	if moved or (#m.waypoints == 0 and not m.failed) then
		m.stuckCount = 0
		plan(m, now)
	end
end

function Mover.stop(m: Mover)
	m.generation += 1
	m.goal, m.waypoints, m.failed = nil, {}, false
	m.humanoid:MoveTo(m.root.Position)
end

-- Advance along the path. Returns true when the goal is reached (or unreachable: check m.failed).
function Mover.update(m: Mover, now: number): boolean
	local goal = m.goal
	if not goal then
		return true
	end
	if flat(m.root.Position, goal) <= ARRIVE_DISTANCE and math.abs(m.root.Position.Y - goal.Y) < 6 then
		return true
	end
	if m.failed then
		return true
	end
	local wp = m.waypoints[m.index]
	local target = if wp then wp.Position else goal
	local dist = flat(m.root.Position, target)
	if wp and dist <= ARRIVE_DISTANCE then
		m.index += 1
		wp = m.waypoints[m.index]
		if wp then
			if wp.Action == Enum.PathWaypointAction.Jump then
				m.humanoid.Jump = true
			end
			moveTo(m, wp.Position, now)
			m.progressDist, m.progressTime = math.huge, now
		end
		return false
	end
	if now - m.lastMoveTo > MOVETO_REFRESH then
		moveTo(m, target, now)
	end
	-- Stuck detection: must get at least 0.5 studs closer every STUCK_TIME.
	if dist < m.progressDist - 0.5 then
		m.progressDist, m.progressTime = dist, now
	elseif now - m.progressTime > STUCK_TIME then
		m.stuckCount += 1
		m.progressDist, m.progressTime = dist, now
		if m.stuckCount > MAX_STUCK then
			m.failed = true
			return true
		end
		m.humanoid.Jump = true
		m.lastPlan = -math.huge
		plan(m, now)
	end
	return false
end

function Mover.destroy(m: Mover)
	m.generation += 1
	if m.blocked then
		m.blocked:Disconnect()
		m.blocked = nil
	end
end

return Mover
```
<!-- /code -->

<!-- code: examples/npc/ServerScriptService/NpcServer.server.luau -->
```luau
-- file: examples/npc/ServerScriptService/NpcServer.server.luau
--!strict
-- Starts the NPC manager. Other systems report loud events with NpcService.noise(position, loudness).
-- Status: TYPECHECKED. Not run in Studio.
local ServerScriptService = game:GetService("ServerScriptService")

local NpcService = require(ServerScriptService.Npc.NpcService)

NpcService.start()
```
<!-- /code -->

## How to test
- 1 NPC, 4-point route around obstacles: loops forever; `State` attribute shows `Patrol`.
- Put a wall across the route at runtime: `Blocked` or stuck detection replans around it; if impossible, it
  gives up that point and continues.
- 50 NPCs (duplicate them): server FPS stable; MicroProfiler shows one `Heartbeat` script entry with bounded
  time; NPCs far from all players stop moving.
- Walk away 300+ studs and come back: NPCs resume.
- Navigation mesh visualization (Studio settings) to check routes are on walkable areas.

## Scaling further
- Hundreds of ambient NPCs: replace Humanoid + MoveTo with an anchored root moved along precomputed paths at
  10–20 Hz and animate on clients near the camera only ([performance](../../handbook/roblox/08-performance.md)).
- Disable unused Humanoid states on NPCs (`SetStateEnabled` for Climbing, Swimming, FallingDown...) to cut
  `stepHumanoid` cost — test carefully.
- Despawn beyond range, respawn from data when players approach.

Sources: cd:characters/pathfinding, cd:reference/engine/classes/PathfindingService, cd:reference/engine/classes/Path,
cd:reference/engine/classes/Humanoid, cd:physics/network-ownership, cd:performance-optimization/improve.
