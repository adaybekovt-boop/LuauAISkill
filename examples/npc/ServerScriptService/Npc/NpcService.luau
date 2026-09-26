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
