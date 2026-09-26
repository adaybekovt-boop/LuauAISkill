--!strict
-- Realistic flashlight.
--   Own light: client-only part following the camera with a little rotational lag; TWO SpotLights — a narrow hot
--   core (shadows on) and a wide dim spill (no shadows) — because a single cone looks like a flat disc.
--   Other players: a light on their root at head height, aimed by the replicated FlashPitch attribute
--   (shadows off: many shadowed lights are expensive). F / gamepad DPadUp / touch button toggles.
-- Status: TYPECHECKED. Not run in Studio.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Spring = require(ReplicatedStorage.Lib.Spring)

local player = Players.LocalPlayer :: Player
local remotes = ReplicatedStorage:WaitForChild("FlashlightRemotes", 30)
assert(remotes, "FlashlightRemotes missing (is FlashlightServer running?)")
local toggleRemote = remotes:WaitForChild("Toggle", 30) :: RemoteEvent
local pitchRemote = remotes:WaitForChild("Pitch", 30) :: UnreliableRemoteEvent

local WARM = Color3.fromRGB(255, 236, 205) -- incandescent-ish; LED torches are closer to (240, 245, 255)
local HOLD_OFFSET = CFrame.new(0.6, -0.5, -0.8) -- camera space: right hand, below eye level

local function spot(parent: Instance, angle: number, brightness: number, range: number, shadows: boolean): SpotLight
	local s = Instance.new("SpotLight")
	s.Angle = angle
	s.Brightness = brightness
	s.Range = range -- local lights are clamped to 120 studs by the engine
	s.Color = WARM
	s.Shadows = shadows
	s.Face = Enum.NormalId.Front
	s.Parent = parent
	return s
end

---------------------------------------------------------------- own flashlight
local holder = Instance.new("Part")
holder.Name = "LocalFlashlight"
holder.Size = Vector3.new(0.2, 0.2, 0.2)
holder.Transparency = 1
holder.Anchored = true
holder.CanCollide = false
holder.CanQuery = false
holder.CanTouch = false
holder.CastShadow = false
local core = spot(holder, 32, 2.6, 55, true)
local spill = spot(holder, 85, 0.5, 30, false)
holder.Parent = Workspace -- client-created: exists only on this client

local on = false
local lagged: CFrame? = nil
local lastSentPitch = math.huge
local lastPitchSend = 0

local function setOn(value: boolean)
	on = value
	core.Enabled, spill.Enabled = value, value
	toggleRemote:FireServer(value)
end
setOn(false)

ContextActionService:BindAction("Flashlight", function(_n: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		setOn(not on)
	end
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.F, Enum.KeyCode.DPadUp)

player.CharacterAdded:Connect(function()
	setOn(false)
end)

RunService.PreRender:Connect(function(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera or not on then
		return
	end
	local target = camera.CFrame * HOLD_OFFSET
	-- Rotation lags slightly behind the view (hand inertia); position stays glued to the camera.
	local rot = (lagged or target.Rotation):Lerp(target.Rotation, Spring.alpha(18, dt))
	lagged = rot
	holder.CFrame = CFrame.new(target.Position) * rot
	-- Tell the server our pitch at most 5×/s and only when it changed noticeably.
	local now = os.clock()
	local look = camera.CFrame.LookVector
	local pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
	if now - lastPitchSend > 0.2 and math.abs(pitch - lastSentPitch) > 3 then
		lastPitchSend, lastSentPitch = now, pitch
		pitchRemote:FireServer(pitch)
	end
end)

---------------------------------------------------------------- other players' flashlights
type Remote = { attachment: Attachment, light: SpotLight, character: Model, pitch: Spring.Spring }
local others: { [Model]: Remote } = {}

local function refresh(character: Model)
	local wantOn = character:GetAttribute("FlashlightOn") == true
	local r = others[character]
	if wantOn and not r then
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = "RemoteFlashlight"
		attachment.Position = Vector3.new(0.5, 1.2, -0.8)
		attachment.Parent = root
		local light = spot(attachment, 40, 2, 45, false)
		others[character] = { attachment = attachment, light = light, character = character, pitch = Spring.new(3, 1) }
	elseif not wantOn and r then
		r.attachment:Destroy()
		others[character] = nil
	end
end

local function watch(p: Player)
	if p == player then
		return
	end
	local function onCharacter(character: Model)
		character:GetAttributeChangedSignal("FlashlightOn"):Connect(function()
			refresh(character)
		end)
		character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(game) and others[character] then
				others[character] = nil
			end
		end)
		refresh(character)
	end
	p.CharacterAdded:Connect(onCharacter)
	if p.Character then
		onCharacter(p.Character)
	end
end
Players.PlayerAdded:Connect(watch)
for _, p in Players:GetPlayers() do
	watch(p)
end

RunService.PostSimulation:Connect(function(dt: number)
	for character, r in others do
		local pitch = character:GetAttribute("FlashPitch")
		r.pitch.target = if type(pitch) == "number" then math.rad(pitch) else 0
		-- Smooth between the 5 Hz updates so the beam doesn't step.
		r.attachment.Orientation = Vector3.new(math.deg(Spring.step(r.pitch, dt)), 0, 0)
	end
end)
