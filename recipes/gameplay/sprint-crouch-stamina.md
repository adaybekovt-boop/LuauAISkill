# Recipe: sprint, crouch, stamina (client feel + server authority)

## When NOT to use
Do not treat local movement presentation as proof that stamina and speed rules were respected.

Evidence: stamina model CLI-EXECUTED (`examples/tests/movement.spec.luau`, 4 tests) · client/server TYPECHECKED ·
**not run in Studio**. Chapters: [character controllers](../../handbook/roblox/13-character-controllers.md),
[input](../../handbook/roblox/19-input.md), [security](../../handbook/roblox/04-security.md).

## Architecture
```text
Client (owns its character's physics → must own the feel):
  Input Action System: PlayContext/Sprint (Shift, L3, touch button), PlayContext/Crouch (C, B, touch button)
  every PreSimulation: sprint allowed? (held · not crouched · moving forward · local stamina) → WalkSpeed
                       → SprintState:FireServer(on) ONLY when it changes
  crouch toggle: CameraOffset spring down; standing up requires headroom (Blockcast upward)
  local-only attributes on the character: Sprinting / Crouching / StaminaLocal (camera, footsteps, UI)
Server:
  SprintState: rate limit → boolean → can start? (else deny) → state
  10 Hz: same Stamina model drains only while the root actually moves → at 0 force stop (FireClient false)
         Player attribute "Stamina" (rounded, on change) → client corrects drift > 10
  2 Hz speed check from server-observed displacement: > expected × 1.25 + 4 for 3 samples → hook (log by default)
```
Why:
- **The client must set WalkSpeed**: player characters are simulated by their owner; server-side WalkSpeed
  changes arrive late and feel awful. The server can't read the client's WalkSpeed, so it validates displacement.
- **Same pure `Stamina` model on both sides** → prediction matches authority; only drift needs correcting.
- **Send on change**: a sprint toggle is 2 messages, not 60/s.
- **No automatic punishment**: knockback, conveyors, seats and server teleports produce "speeding" — the check
  exempts known cases (`SeatPart`, Physics/Ragdoll/FallingDown states, `MovementExemptUntil` attribute that your
  teleport/knockback code sets) and only reports.

## Code
<!-- code: examples/movement/ReplicatedStorage/Movement/Config.luau -->
```luau
-- file: examples/movement/ReplicatedStorage/Movement/Config.luau
--!strict
-- Movement tuning shared by client (feel) and server (validation). Units: studs, seconds.
local Config = {
	WALK_SPEED = 16, -- Humanoid default
	SPRINT_SPEED = 24,
	CROUCH_SPEED = 8,
	CROUCH_CAMERA_DROP = 1.6, -- Humanoid.CameraOffset.Y while crouched
	SPRINT_MIN_FORWARD = 0.5, -- MoveDirection · look must exceed this to sprint (no sideways/backwards sprint)
	STAMINA = {
		max = 100,
		drainPerSecond = 18,
		regenPerSecond = 22,
		regenDelay = 1.2, -- seconds after sprinting stops before regen starts
		startThreshold = 15, -- can't start sprinting below this (prevents stutter-sprinting at 0)
	},
	-- Server speed validation: allowed horizontal speed = expected * (1 + SPEED_TOLERANCE) + SPEED_SLACK.
	SPEED_TOLERANCE = 0.25,
	SPEED_SLACK = 4,
}
return table.freeze(Config)
```
<!-- /code -->

<!-- code: examples/movement/ReplicatedStorage/Movement/Stamina.luau -->
```luau
-- file: examples/movement/ReplicatedStorage/Movement/Stamina.luau
--!strict
-- Pure stamina model used identically by client (prediction/UI) and server (authority). CLI-tested.
-- Status: TYPECHECKED + CLI-EXECUTED (examples/tests/movement.spec.luau).
export type Params = {
	max: number,
	drainPerSecond: number,
	regenPerSecond: number,
	regenDelay: number,
	startThreshold: number,
}
export type Stamina = { value: number, sinceDrain: number, params: Params }

local Stamina = {}

function Stamina.new(params: Params): Stamina
	return { value = params.max, sinceDrain = math.huge, params = params }
end

-- Advance by dt. Returns true while `draining` is allowed to continue (false = ran out → force stop).
function Stamina.step(s: Stamina, dt: number, draining: boolean): boolean
	local p = s.params
	dt = math.clamp(dt, 0, 1) -- a long hitch must not grant or drain a huge amount at once
	if draining then
		s.value = math.max(0, s.value - p.drainPerSecond * dt)
		s.sinceDrain = 0
		return s.value > 0
	end
	s.sinceDrain += dt
	if s.sinceDrain >= p.regenDelay then
		s.value = math.min(p.max, s.value + p.regenPerSecond * dt)
	end
	return true
end

function Stamina.canStart(s: Stamina): boolean
	return s.value >= s.params.startThreshold
end

return table.freeze(Stamina)
```
<!-- /code -->

<!-- code: examples/movement/ServerScriptService/MovementServer.server.luau -->
```luau
-- file: examples/movement/ServerScriptService/MovementServer.server.luau
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
```
<!-- /code -->

<!-- code: examples/movement/StarterPlayer/StarterPlayerScripts/MovementClient.client.luau -->
```luau
-- file: examples/movement/StarterPlayer/StarterPlayerScripts/MovementClient.client.luau
--!strict
-- Sprint / crouch / stamina (client feel). Input via the Input Action System (stable): actions are created here if
-- they weren't authored in Studio under ReplicatedStorage.Inputs.PlayContext. The server owns stamina; the client
-- predicts it for instant response and accepts corrections/forced stops.
-- Publishes local-only attributes on the character ("Sprinting", "Crouching") for the camera and footsteps.
-- Status: TYPECHECKED (stamina model CLI-EXECUTED). Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Movement.Config)
local Stamina = require(ReplicatedStorage.Movement.Stamina)
local Spring = require(ReplicatedStorage.Lib.Spring)

local player = Players.LocalPlayer :: Player
local sprintRemote = ReplicatedStorage:WaitForChild("SprintState", 30) :: RemoteEvent

---------------------------------------------------------------- input actions
local function ensure(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local inputs = ensure(ReplicatedStorage, "Folder", "Inputs")
local context = ensure(inputs, "InputContext", "PlayContext") :: InputContext

local function boolAction(name: string, keys: { Enum.KeyCode }, touchButton: GuiButton?): InputAction
	local existing = context:FindFirstChild(name)
	if existing and existing:IsA("InputAction") then
		return existing -- authored in Studio: keep the designer's bindings
	end
	local action = Instance.new("InputAction")
	action.Name = name
	action.Type = Enum.InputActionType.Bool
	for _, key in keys do
		local binding = Instance.new("InputBinding")
		binding.KeyCode = key
		binding.Parent = action
	end
	if touchButton then
		local binding = Instance.new("InputBinding")
		binding.UIButton = touchButton
		binding.Parent = action
	end
	action.Parent = context
	return action
end

-- Touch buttons only on touch devices (the Input Action System maps a GuiButton to the action).
local sprintButton: TextButton? = nil
local crouchButton: TextButton? = nil
if UserInputService.TouchEnabled then
	local gui = Instance.new("ScreenGui")
	gui.Name = "MovementButtons"
	gui.ResetOnSpawn = false
	local function button(text: string, y: number): TextButton
		local b = Instance.new("TextButton")
		b.Text = text
		b.AnchorPoint = Vector2.new(1, 1)
		b.Position = UDim2.new(1, -24, y, 0)
		b.Size = UDim2.fromScale(0.09, 0.09)
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = b
		b.Parent = gui
		return b
	end
	sprintButton = button("Run", 0.62)
	crouchButton = button("Crouch", 0.74)
	gui.Parent = player:WaitForChild("PlayerGui")
end

local sprintAction = boolAction("Sprint", { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 }, sprintButton)
local crouchAction = boolAction("Crouch", { Enum.KeyCode.C, Enum.KeyCode.ButtonB }, crouchButton)

---------------------------------------------------------------- state
local stamina = Stamina.new(Config.STAMINA)
local wantSprint = false
local sprinting = false
local crouching = false
local cameraDrop = Spring.new(6, 1)

sprintAction.Pressed:Connect(function()
	wantSprint = true
end)
sprintAction.Released:Connect(function()
	wantSprint = false
end)

local function headroom(root: BasePart, character: Model): boolean
	local params = RaycastParams.new()
	params.ExcludeInstances = { character }
	-- Box the width of the character swept upward: anything above means "can't stand".
	return Workspace:Blockcast(root.CFrame, Vector3.new(1.8, 1, 1), Vector3.new(0, 2.5, 0), params) == nil
end

crouchAction.Pressed:Connect(function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not root then
		return
	end
	if crouching and not headroom(root, character) then
		return -- stay crouched under low ceilings
	end
	crouching = not crouching
end)

local function setSprinting(on: boolean)
	if sprinting ~= on then
		sprinting = on
		sprintRemote:FireServer(on) -- only on change, never per frame
	end
end

sprintRemote.OnClientEvent:Connect(function(on: boolean)
	if not on then
		sprinting = false -- server forced a stop (out of stamina or denied)
		wantSprint = false
	end
end)

player.CharacterAdded:Connect(function()
	sprinting, crouching, wantSprint = false, false, false
	stamina.value = Config.STAMINA.max
	cameraDrop.position, cameraDrop.velocity, cameraDrop.target = 0, 0, 0
end)

---------------------------------------------------------------- per frame
RunService.PreSimulation:Connect(function(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local forward = if flatLook.Magnitude > 1e-3 then humanoid.MoveDirection:Dot(flatLook.Unit) else 0
	local moving = humanoid.MoveDirection.Magnitude > 0.1

	local want = wantSprint and not crouching and forward > Config.SPRINT_MIN_FORWARD
	if want and not sprinting and not Stamina.canStart(stamina) then
		want = false
	end
	if not Stamina.step(stamina, dt, want and moving) then
		want = false
	end
	setSprinting(want)

	-- Correct prediction drift toward the server's authoritative value.
	local serverValue = player:GetAttribute("Stamina")
	if type(serverValue) == "number" and math.abs(serverValue - stamina.value) > 10 then
		stamina.value = serverValue
	end

	humanoid.WalkSpeed = if sprinting then Config.SPRINT_SPEED
		elseif crouching then Config.CROUCH_SPEED
		else Config.WALK_SPEED
	cameraDrop.target = if crouching then Config.CROUCH_CAMERA_DROP else 0
	humanoid.CameraOffset = Vector3.new(0, -Spring.step(cameraDrop, dt), 0)
	-- Local-only attributes (client-set attributes don't replicate): consumed by camera/footstep/UI scripts.
	-- Set only on change: attribute writes fire change signals and aren't free.
	local staminaShown = math.floor(stamina.value)
	if character:GetAttribute("Sprinting") ~= sprinting then
		character:SetAttribute("Sprinting", sprinting)
	end
	if character:GetAttribute("Crouching") ~= crouching then
		character:SetAttribute("Crouching", crouching)
	end
	if character:GetAttribute("StaminaLocal") ~= staminaShown then
		character:SetAttribute("StaminaLocal", staminaShown)
	end
end)
```
<!-- /code -->

## Setup notes
- Authoring the actions in Studio (`ReplicatedStorage.Inputs.PlayContext.Sprint` with bindings) is the recommended
  workflow; the script only creates what's missing and keeps designer bindings.
- Optional: enable `Workspace.PlayerScriptsUseInputActionSystem` in Studio so the default movement uses the same
  system (Studio-only property).
- Crouch here lowers speed + camera. To fit through low vents you also need a smaller collision footprint (crouch
  animation + custom collision, or lowering `HipHeight` with a rig that tolerates it) — test on your rig.

## How to test
| # | Scenario | Expected |
|---|---|---|
| 1 | Hold Shift while walking forward | 24 studs/s, FOV kick (bodycam layer), stamina drains |
| 2 | Hold Shift while strafing/backwards | no sprint |
| 3 | Hold Shift standing still | no drain |
| 4 | Drain to 0 | client stops; server forces stop even if the client ignores it; can't restart below 15 |
| 5 | Crouch under a low beam, press C | stays crouched until clear |
| 6 | Die while sprinting/crouched | respawn walks normally, full stamina |
| 7 | Exploit script: `humanoid.WalkSpeed = 60` locally | moves fast locally; server logs a violation after ~1.5 s |
| 8 | Touch device (Studio device emulator) | Run/Crouch buttons work |

## Variations
- Toggle sprint (accessibility setting): flip `wantSprint` on `Pressed` instead of hold.
- Slide: from sprint + crouch → short `LinearVelocity` burst on the client; server tolerance via
  `MovementExemptUntil` for the burst duration.
- Server authority mode (released 2026-07) removes the need for displacement checks by simulating movement on the server —
  see [server authority](../../handbook/roblox/05-server-authority.md).

Sources: cd:input/input-action-system, cd:reference/engine/classes/InputAction,
cd:reference/engine/classes/InputBinding, cd:reference/engine/classes/Humanoid, cd:physics/network-ownership,
cd:scripting/security/security-tactics, cd:reference/engine/classes/WorldRoot.
