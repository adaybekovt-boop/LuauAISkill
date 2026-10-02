# Recipe: bodycam camera controller (layer on the default camera, comfort-aware)

## When NOT to use
Do not use for a fixed-camera game or as a mandatory motion effect; provide comfort controls.

Evidence: TYPECHECKED · **not run in Studio** (camera feel must be tuned by eye). Side: client only.
Chapter: [camera](../../handbook/roblox/14-camera.md). Visual look (grain, vignette, colour, timestamp overlay):
[camera aesthetics](../graphics/camera-aesthetics.md).

## Architecture
```text
Default PlayerModule camera (LockFirstPerson) handles look input, collisions, device support
RenderStep Camera-1  "BodycamRestore": put back the default camera's own last CFrame (prevents feedback drift)
RenderStep Camera    default camera computes this frame
RenderStep Camera+1  "BodycamLayer":
    position = head CFrame × chest MOUNT − stride bob
    rotation = lagged(real rotation, sharpness 10)  → swing on fast turns
             × drift (math.noise, 0.7°, ~0.3 Hz) × roll (stride phase, 0.9°)
    FOV = 90 + spring(sprint kick 6)
Reduced Motion (GuiService.ReducedMotionEnabled) → all motion × 0.2
```
Why:
- **Layer, don't replace**: keeping the default camera means mouse/gamepad/touch look, first-person body hiding
  and device quirks keep working. A fully `Scriptable` rig means re-implementing all of that.
- **Restore step**: the default PlayerModule camera derives its next orientation from the current
  `Camera.CFrame` (observed PlayerModule behaviour, not a documented contract); without restoring, your
  lag/drift/roll feeds back and accumulates. The restore step is harmless if that behaviour ever changes.
- **Stride phase, not time**: bob stops when you stop, speeds up when you run.
- **Smooth noise, low frequency, small angles** — reads as handheld, not as shaking. Random per-frame jitter is
  nausea-inducing.

## Code
<!-- code: examples/movement/StarterPlayer/StarterPlayerScripts/BodycamCamera.client.luau -->
```luau
-- file: examples/movement/StarterPlayer/StarterPlayerScripts/BodycamCamera.client.luau
--!strict
-- Bodycam camera as a layer ON TOP of the default first-person camera (runs right after it each frame):
-- chest mount offset, rotational lag on fast turns, low-frequency handheld drift, stride-driven bob/roll,
-- wide FOV with a sprint kick. All motion scales down with Reduced Motion. V toggles it.
-- The default PlayerModule camera derives its next orientation from Camera.CFrame (observed behaviour, not a
-- documented contract), so the layer is removed again just BEFORE it runs (restore step) — otherwise offsets
-- would accumulate into drift.
-- The post-processing "look" (grain, vignette, colour) lives in the camera-aesthetics graphics recipe.
-- Status: TYPECHECKED. Not run in Studio.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Spring = require(ReplicatedStorage.Lib.Spring)

local player = Players.LocalPlayer :: Player
local STEP_NAME = "BodycamLayer"
local RESTORE_NAME = "BodycamRestore"

local MOUNT = CFrame.new(0, -1.1, -0.35) -- camera space: chest height, slightly forward of the eyes
local BASE_FOV = 90 -- vertical degrees (≈ 120° horizontal on 16:9)
local SPRINT_FOV_KICK = 6
local LAG_SHARPNESS = 10 -- higher = tighter follow; lower = more swing on fast turns
local DRIFT_DEG = 0.7 -- handheld wander amplitude
local BOB_HEIGHT = 0.07 -- studs at walk speed
local ROLL_DEG = 0.9

local enabled = false
local lagged: CFrame? = nil
local defaultCFrame: CFrame? = nil -- what the default camera produced last frame (before our layer)
local strideDistance = 0
local bobAmount = Spring.new(3, 1)
local fovKick = Spring.new(4, 1)
local seed = math.random() * 1000

-- 0..1 motion scale: players with Reduced Motion get a much calmer camera.
local function motionScale(): number
	return if GuiService.ReducedMotionEnabled then 0.2 else 1
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not camera or not character or not humanoid or not root then
		return
	end
	local base = camera.CFrame -- the default camera already wrote this frame's first-person CFrame
	defaultCFrame = base
	local scale = motionScale()

	-- 1. Rotational lag: smoothed orientation chases the real one (exponential, framerate-independent).
	local rotation = base.Rotation
	local current = lagged or rotation
	current = current:Lerp(rotation, math.min(1, Spring.alpha(LAG_SHARPNESS / math.max(scale, 0.25), dt)))
	lagged = current

	-- 2. Stride phase from distance travelled (not time), amplitude from speed.
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	strideDistance += speed * dt
	bobAmount.target = if grounded then math.clamp(speed / 16, 0, 1.5) else 0
	local amount = Spring.step(bobAmount, dt) * scale
	local phase = strideDistance / 5.5 * math.pi -- one full sine per two steps
	local bob = math.abs(math.sin(phase)) * BOB_HEIGHT * amount
	local roll = math.sin(phase) * math.rad(ROLL_DEG) * amount

	-- 3. Handheld drift: smooth noise at low frequency (never math.random per frame).
	local t = os.clock()
	local driftPitch = math.noise(t * 0.35, seed) * math.rad(DRIFT_DEG) * scale
	local driftYaw = math.noise(seed, t * 0.3) * math.rad(DRIFT_DEG) * scale

	-- 4. Compose: position follows the real head + mount; orientation uses the lagged rotation + layers.
	local position = (base * MOUNT).Position + Vector3.new(0, -bob, 0)
	camera.CFrame = CFrame.new(position) * current * CFrame.Angles(driftPitch, driftYaw, roll)

	fovKick.target = if character:GetAttribute("Sprinting") == true then SPRINT_FOV_KICK * scale else 0
	camera.FieldOfView = BASE_FOV + Spring.step(fovKick, dt)
end

-- Runs just before the default camera: hand it back its own last output so our layer never feeds back.
local function restore()
	local camera = Workspace.CurrentCamera
	if camera and defaultCFrame then
		camera.CFrame = defaultCFrame
	end
end

local function setEnabled(on: boolean)
	if on == enabled then
		return
	end
	enabled = on
	local camera = Workspace.CurrentCamera
	if on then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		lagged, defaultCFrame = nil, nil
		RunService:BindToRenderStep(RESTORE_NAME, Enum.RenderPriority.Camera.Value - 1, restore)
		RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, update)
	else
		RunService:UnbindFromRenderStep(STEP_NAME)
		RunService:UnbindFromRenderStep(RESTORE_NAME)
		restore()
		defaultCFrame = nil
		player.CameraMode = Enum.CameraMode.Classic
		if camera then
			camera.FieldOfView = 70 -- restore the default
		end
	end
end

ContextActionService:BindAction("ToggleBodycam", function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		setEnabled(not enabled)
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.V)

setEnabled(true)
```
<!-- /code -->
Reads the local `Sprinting` attribute published by [sprint/crouch/stamina](sprint-crouch-stamina.md).

## Tuning table
| Parameter | Subtle | Strong ("found footage") | Notes |
|---|---|---|---|
| `BASE_FOV` (vertical) | 80 | 95 | > 100 distorts edges a lot; offer an FOV slider |
| `LAG_SHARPNESS` | 16 | 7 | lower = more swing; too low feels like input lag |
| `DRIFT_DEG` | 0.3 | 1.2 | keep frequency ≤ 0.5 Hz |
| `BOB_HEIGHT` | 0.04 | 0.1 | 0 when Reduced Motion |
| `ROLL_DEG` | 0.4 | 1.5 | roll is the #1 motion-sickness trigger |

## How to test
- Walk/sprint/stop: bob starts/stops smoothly; sprint widens FOV slightly.
- Fast 180° mouse flick: view swings and settles within ~0.3 s, no overshoot loop.
- Stand still for 60 s: the view wanders a little but does not drift away (restore step works).
- Enable Reduced Motion (Roblox settings): camera nearly static.
- Toggle V repeatedly, die and respawn: camera returns to Classic mode, FOV 70, no leftover render steps.

## Pitfalls
- Don't also tween `Camera.CFrame` or FOV from another script — one owner per property.
- Aiming: weapons that ray from the screen centre (`ViewportPointToRay`) aim where the lagged camera looks, which
  is what the player sees — keep it that way; don't aim from the head's direction.
- Mouse lock: `LockFirstPerson` handles it; if you switch to `Scriptable`, re-apply `MouseBehavior` every frame.

Sources: cd:workspace/camera/index, cd:reference/engine/classes/Camera, cd:reference/engine/classes/RunService,
cd:reference/engine/classes/GuiService, cd:production/publishing/accessibility.
