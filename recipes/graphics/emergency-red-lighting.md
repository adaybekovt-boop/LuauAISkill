# Recipe: emergency red lighting (power failure event)

Evidence: TYPECHECKED · **not run in Studio**. Related: [lighting controller](lighting-controller-presets.md),
[realistic flashlight](realistic-flashlight.md) (players will need it).

## Architecture
```text
Server: Workspace attribute PowerState = Normal | Emergency | Blackout (gameplay decides: generator broke, round event)
Clients:
  EmergencyLights: "MainLight" fixtures on only in Normal; "EmergencyLight" fixtures on only in Emergency
                   Rotating=true → the fixture's Attachment (with a SpotLight) spins ~150°/s; else a 0.5 Hz breathing pulse
  LightingController: PowerState Emergency → EmergencyRed preset (dark, slight red grade, bloom on red sources)
Blackout: everything off, flashlights only
```
Why: one replicated attribute drives everything; each client animates locally (no per-frame traffic); the red look
comes mostly from **local lights**, the global grade only supports it.

## Preset
<!-- code: examples/lighting/ReplicatedStorage/LightingPresets.luau#EmergencyRed -->
```luau
-- file: examples/lighting/ReplicatedStorage/LightingPresets.luau (region EmergencyRed)
-- Power failure: main lights off, red emergency lights (local lights do the colouring; the grade only supports it).
Presets.EmergencyRed = {
	lighting = {
		ClockTime = 0,
		Brightness = 0,
		Ambient = rgb(6, 1, 1),
		OutdoorAmbient = rgb(0, 0, 0),
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0.2,
		ExposureCompensation = 0.2,
		ShadowSoftness = 0.3,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.35, Offset = 0, Color = rgb(40, 12, 12), Decay = rgb(15, 4, 4), Glare = 0, Haze = 0.8 },
	colorCorrection = { Brightness = 0, Contrast = 0.2, Saturation = 0.1, TintColor = rgb(255, 235, 235) },
	bloom = { Intensity = 0.5, Size = 24, Threshold = 1.4 },
}
```
<!-- /code -->

## Code
<!-- code: examples/lighting/ServerScriptService/PowerServer.server.luau -->
```luau
-- file: examples/lighting/ServerScriptService/PowerServer.server.luau
--!strict
-- Building power state for everyone: Workspace attribute PowerState = "Normal" | "Emergency" | "Blackout".
-- Clients switch lights and presets locally (EmergencyLights / LightingController). Game logic (a generator puzzle,
-- a round event) calls setPower; a demo cycle runs when Workspace attribute PowerDemo is true.
-- Status: TYPECHECKED. Not run in Studio.
local Workspace = game:GetService("Workspace")

type PowerState = "Normal" | "Emergency" | "Blackout"

local function setPower(state: PowerState)
	Workspace:SetAttribute("PowerState", state)
end

setPower("Normal")

if Workspace:GetAttribute("PowerDemo") == true then
	while true do
		task.wait(20)
		setPower("Emergency")
		task.wait(15)
		setPower("Blackout")
		task.wait(8)
		setPower("Normal")
	end
end
```
<!-- /code -->

<!-- code: examples/lighting/StarterPlayer/StarterPlayerScripts/EmergencyLights.client.luau -->
```luau
-- file: examples/lighting/StarterPlayer/StarterPlayerScripts/EmergencyLights.client.luau
--!strict
-- Reacts to the Workspace attribute "PowerState" on each client (cosmetic, synced by the replicated attribute):
--   "MainLight"      parts: normal lighting (lights + neon) — on only in Normal
--   "EmergencyLight" parts: red lights — on only in Emergency; attribute Rotating=true spins the light like a beacon
--                    (its lights must be inside an Attachment child), otherwise a slow pulse
-- Beacon speed/pulse are slow on purpose (no strobe); Reduced Motion stops rotation and pulsing.
-- Status: TYPECHECKED. Not run in Studio.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Binder = require(ReplicatedStorage.Lib.Binder)

type Fixture = { part: BasePart, lights: { Light }, material: Enum.Material, spinner: Attachment?, emergency: boolean }
local fixtures: { [BasePart]: Fixture } = {}

local function powered(f: Fixture): boolean
	local state = Workspace:GetAttribute("PowerState")
	return if f.emergency then state == "Emergency" else (state == nil or state == "Normal")
end

local function applyFixture(f: Fixture)
	local on = powered(f)
	for _, light in f.lights do
		light.Enabled = on
	end
	f.part.Material = if on then f.material else Enum.Material.SmoothPlastic
end

local function bindTag(tag: string, emergency: boolean)
	Binder.bind(tag, function(inst, cleanup)
		if not inst:IsA("BasePart") then
			return
		end
		local lights = {}
		for _, d in inst:GetDescendants() do
			if d:IsA("Light") then
				table.insert(lights, d)
			end
		end
		local spinner = if emergency and inst:GetAttribute("Rotating") == true
			then inst:FindFirstChildOfClass("Attachment") else nil
		local f: Fixture = { part = inst, lights = lights, material = inst.Material, spinner = spinner, emergency = emergency }
		fixtures[inst] = f
		applyFixture(f)
		cleanup:add(function()
			fixtures[inst] = nil
		end)
	end)
end
bindTag("MainLight", false)
bindTag("EmergencyLight", true)

Workspace:GetAttributeChangedSignal("PowerState"):Connect(function()
	for _, f in fixtures do
		applyFixture(f)
	end
end)

RunService.PreRender:Connect(function(dt: number)
	if Workspace:GetAttribute("PowerState") ~= "Emergency" or GuiService.ReducedMotionEnabled then
		return
	end
	local t = os.clock()
	for _, f in fixtures do
		if not f.emergency then
			continue
		end
		if f.spinner then
			f.spinner.Orientation += Vector3.new(0, 150 * dt, 0) -- ~0.4 rotations per second
		else
			local pulse = 0.65 + 0.35 * (0.5 + 0.5 * math.sin(t * math.pi)) -- 0.5 Hz breathing, never fully off
			for _, light in f.lights do
				light.Brightness = 2 * pulse
			end
		end
	end
end)
```
<!-- /code -->

## Fixture setup
- Beacon: small red `Neon` dome part tagged `EmergencyLight`, attribute `Rotating = true`, child `Attachment` with a
  `SpotLight` (Angle 45, Range 30, Brightness 3, red (255, 40, 30), Shadows off) pointing sideways.
- Wall emergency lamp: `Neon` red part + `PointLight` (Range 14, Brightness 2) child, tag `EmergencyLight`.
- Normal fixtures: tag `MainLight`.
- Sound: alarm loop (client-side, distance-attenuated), a power-down "clunk" when switching.

## Accessibility
Slow rotation/pulse only, no strobe; Reduced Motion stops motion. Don't make red the only cue for danger (colour
blindness) — pair with sound and UI text.

Sources: cd:effects/light-sources, cd:reference/engine/classes/SpotLight, cd:reference/engine/classes/PointLight,
cd:scripting/attributes, cd:production/publishing/accessibility.
