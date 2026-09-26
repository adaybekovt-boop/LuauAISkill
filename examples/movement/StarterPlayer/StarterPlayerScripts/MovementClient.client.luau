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
