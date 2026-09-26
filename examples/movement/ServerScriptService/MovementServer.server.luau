--!strict
-- Server side of sprint/stamina: authoritative stamina, forced stops, and a conservative speed check.
-- Player characters are client-simulated, so the server can't read the client's WalkSpeed; it observes
-- displacement and flags implausible speeds. Punishment is left to a human-tuned hook (false positives exist:
-- knockback, conveyors, seats, server teleports).
-- Status: TYPECHECKED (stamina model CLI-EXECUTED). Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
local Validate = require(ReplicatedStorage.Lib.Validate)
local Config = require(ReplicatedStorage.Movement.Config)
local Stamina = require(ReplicatedStorage.Movement.Stamina)

local TICK = 0.1 -- stamina simulation rate (10 Hz is plenty)
local SPEED_WINDOW = 0.5 -- seconds between speed samples
local VIOLATIONS_TO_FLAG = 3 -- consecutive samples over the limit
local SPRINT_GRACE = 1 -- seconds after a sprint stop during which sprint speed is still tolerated

local sprintRemote = Instance.new("RemoteEvent")
sprintRemote.Name = "SprintState"
sprintRemote.Parent = ReplicatedStorage

type State = {
	sprinting: boolean,
	stoppedAt: number,
	stamina: Stamina.Stamina,
	sentStamina: number,
	lastPos: Vector3?,
	lastSample: number,
	violations: number,
}
local states: { [Player]: State } = {}
local limiter = TokenBucket.new({ Sprint = { capacity = 6, rate = 3 } })

-- Replace with your policy (log to analytics, set back, kick after review...). Default: log.
local function onSpeedViolation(player: Player, speed: number, allowed: number)
	warn(`[Movement] {player.Name} moved {math.floor(speed)} studs/s (allowed {math.floor(allowed)})`)
end

local function stateOf(player: Player): State
	local existing = states[player]
	if existing then
		return existing
	end
	local s: State = {
		sprinting = false,
		stoppedAt = -math.huge,
		stamina = Stamina.new(Config.STAMINA),
		sentStamina = -1,
		lastPos = nil,
		lastSample = os.clock(),
		violations = 0,
	}
	states[player] = s
	return s
end

local function setSprinting(player: Player, s: State, on: boolean, tellClient: boolean)
	if s.sprinting == on then
		return
	end
	s.sprinting = on
	if not on then
		s.stoppedAt = os.clock()
	end
	if tellClient then
		sprintRemote:FireClient(player, on)
	end
end

sprintRemote.OnServerEvent:Connect(function(player: Player, want: unknown)
	if not limiter:allow(player, "Sprint", os.clock()) then
		return
	end
	local on = Validate.boolean(want)
	if on == nil then
		return
	end
	local s = stateOf(player)
	if on and not Stamina.canStart(s.stamina) then
		sprintRemote:FireClient(player, false) -- deny: client predicted wrong
		return
	end
	setSprinting(player, s, on, false)
end)

local function horizontalSpeed(root: BasePart): number
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

local function exempt(humanoid: Humanoid, character: Model): boolean
	local state = humanoid:GetState()
	return humanoid.SeatPart ~= nil
		or state == Enum.HumanoidStateType.Physics
		or state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.FallingDown
		or character:GetAttribute("MovementExemptUntil") ~= nil
			and os.clock() < (character:GetAttribute("MovementExemptUntil") :: number)
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	if accumulator < TICK then
		return
	end
	local step = accumulator
	accumulator = 0
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local s = stateOf(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.RootPart
		if not character or not humanoid or not root or humanoid.Health <= 0 then
			setSprinting(player, s, false, false)
			s.lastPos = nil
			continue
		end
		-- Stamina: drain only while actually moving, so standing still with Shift held costs nothing.
		local moving = horizontalSpeed(root) > Config.WALK_SPEED * 0.5
		if not Stamina.step(s.stamina, step, s.sprinting and moving) then
			setSprinting(player, s, false, true) -- out of stamina: force stop on the client
		end
		local rounded = math.floor(s.stamina.value + 0.5)
		if rounded ~= s.sentStamina then
			s.sentStamina = rounded
			player:SetAttribute("Stamina", rounded) -- public and harmless; drives the client's UI correction
		end
		-- Speed check from displacement between samples (server-observed positions).
		if now - s.lastSample >= SPEED_WINDOW then
			local pos = root.Position
			local last = s.lastPos
			local elapsed = now - s.lastSample
			s.lastPos, s.lastSample = pos, now
			if last and not exempt(humanoid, character) then
				local d = pos - last
				local speed = Vector3.new(d.X, 0, d.Z).Magnitude / elapsed
				local sprintOk = s.sprinting or now - s.stoppedAt < SPRINT_GRACE
				local expected = if sprintOk then Config.SPRINT_SPEED else Config.WALK_SPEED
				local allowed = expected * (1 + Config.SPEED_TOLERANCE) + Config.SPEED_SLACK
				if speed > allowed then
					s.violations += 1
					if s.violations == VIOLATIONS_TO_FLAG then
						onSpeedViolation(player, speed, allowed)
					end
				else
					s.violations = 0
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	states[player] = nil
	limiter:forget(player)
end)
