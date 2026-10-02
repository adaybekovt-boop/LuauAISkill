# Recipe: realistic flashlight (two-cone beam, hand lag, visible to others)

## When NOT to use
Do not copy this visual preset unchanged into an unrelated scene or treat it as a measured performance budget.

Evidence: TYPECHECKED · **not run in Studio** (beam look must be tuned by eye).
Chapter: [local lights → flashlight](../../handbook/graphics/03-local-lights.md#flashlight-essentials).

## Why most Roblox flashlights look fake
One SpotLight = a flat disc with a hard edge and no falloff inside. Real torches have a **hot centre** and a **wide dim
spill**; the beam also lags a little behind fast head turns and is slightly warm (incandescent) or cold (LED).

## Architecture
```text
Own flashlight (client-only part, never replicated):
  every PreRender: position = camera × hold offset (right hand, below eye); rotation lerps toward the camera (hand lag)
  core SpotLight: Angle 32, Brightness 2.6, Range 55, Shadows ON  (the one shadowed light the player carries)
  spill SpotLight: Angle 85, Brightness 0.5, Range 30, Shadows off
  toggle (F / DPadUp / touch) → Toggle remote; pitch → Pitch unreliable remote, ≤ 5/s, only on > 3° change
Server: validates + stores character attributes FlashlightOn, FlashPitch (2° steps)
Other clients: Attachment on the other player's root at head height, SpotLight (no shadows), pitch smoothed by a spring
```
Why: the owner needs zero latency (local part), others need a plausible beam (replicated state, local light), and
shadow cost stays at one moving shadowed light per client.

## Code
<!-- code: examples/lighting/ServerScriptService/FlashlightServer.server.luau -->
```luau
-- file: examples/lighting/ServerScriptService/FlashlightServer.server.luau
--!strict
-- Flashlight state for other players' views: the server stores FlashlightOn and FlashPitch (quantized) as
-- character attributes. Clients render the lights themselves. Rate-limited; pitch is cosmetic but still validated.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
local Validate = require(ReplicatedStorage.Lib.Validate)

local folder = Instance.new("Folder")
folder.Name = "FlashlightRemotes"
local toggle = Instance.new("RemoteEvent")
toggle.Name = "Toggle"
toggle.Parent = folder
local pitch = Instance.new("UnreliableRemoteEvent")
pitch.Name = "Pitch"
pitch.Parent = folder
folder.Parent = ReplicatedStorage

local limiter = TokenBucket.new({ Toggle = { capacity = 4, rate = 2 }, Pitch = { capacity = 8, rate = 6 } })

toggle.OnServerEvent:Connect(function(player: Player, on: unknown)
	local value = Validate.boolean(on)
	local character = player.Character
	if value == nil or not character or not limiter:allow(player, "Toggle", os.clock()) then
		return
	end
	character:SetAttribute("FlashlightOn", value)
end)

pitch.OnServerEvent:Connect(function(player: Player, degrees: unknown)
	local value = Validate.number(degrees, -80, 80)
	local character = player.Character
	if value == nil or not character or not limiter:allow(player, "Pitch", os.clock()) then
		return
	end
	character:SetAttribute("FlashPitch", math.round(value / 2) * 2) -- 2° steps: invisible, fewer changes
end)

Players.PlayerRemoving:Connect(function(player: Player)
	limiter:forget(player)
end)
```
<!-- /code -->

<!-- code: examples/lighting/StarterPlayer/StarterPlayerScripts/Flashlight.client.luau -->
```luau
-- file: examples/lighting/StarterPlayer/StarterPlayerScripts/Flashlight.client.luau
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
```
<!-- /code -->

## Tuning
| Parameter | Effect | Range |
|---|---|---|
| core Angle | beam width | 25–45 |
| core Brightness | hot spot intensity | 2–4 (watch bloom on white walls) |
| spill Brightness | soft surround | 0.3–0.8 |
| Range | throw distance | 40–70 (engine clamps at 120) |
| lag sharpness (18) | hand inertia | 12 (heavy) – 25 (snappy) |
| Colour | mood | incandescent (255, 236, 205) · LED (240, 245, 255) |
Scene support: the flashlight looks best with low Ambient and some specular surfaces (wet floors, varnish).

## Variations
- **Battery**: server-side charge drained while on (inventory `Battery` item refills); client dims the core as it
  drops below 20 % and adds brief flickers — the server stays authoritative about "on".
- **Viewmodel**: attach the light to a flashlight mesh in a first-person viewmodel instead of the invisible part.
- **Volumetric look**: no real volumetrics; fake with dust particles in front of the camera only while the light is on.

## How to test
Toggle in a dark room: instant on/off; flick the mouse: beam trails slightly, no jitter; second client sees your
beam and its pitch following within ~0.2 s; 10 players with flashlights on: frame time acceptable (others' lights have
no shadows).

Sources: cd:effects/light-sources, cd:reference/engine/classes/SpotLight, cd:reference/engine/classes/UnreliableRemoteEvent,
cd:scripting/attributes.
