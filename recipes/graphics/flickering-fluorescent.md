# Recipe: flickering fluorescent lights

## When NOT to use
Do not copy this visual preset unchanged into an unrelated scene or treat it as a measured performance budget.

Evidence: TYPECHECKED · **not run in Studio**.
Chapter: [local lights → flicker](../../handbook/graphics/03-local-lights.md#flicker-and-animated-lights).

## Architecture
```text
Server/procgen/Studio: tag the panel part "FlickerLight" (lights are its descendants). Nothing replicates per frame.
Client: Binder collects panels → ONE loop at 30 Hz animates only panels within 80 studs of the camera
   per-panel program (seeded from its position → same on every client):
     stable 3–12 s → burst 0.15–1.2 s of irregular toggles every 30–120 ms → stable …
   level → Light.Brightness × level, Light.Enabled when > 0.03, panel Material Neon ↔ SmoothPlastic
   Reduced Motion: dips to 60 % instead of switching off
```
Why: cosmetic → client-only (no network); deterministic seed keeps players' views similar; distance culling keeps
cost flat no matter how many panels exist; material swap makes the bloom flicker with the light.

## Code
<!-- code: examples/lighting/StarterPlayer/StarterPlayerScripts/FlickerLights.client.luau -->
```luau
-- file: examples/lighting/StarterPlayer/StarterPlayerScripts/FlickerLights.client.luau
--!strict
-- Flickering fluorescent panels (client-side, cosmetic). Parts tagged "FlickerLight" (the panel; lights are its
-- descendants). One loop for all panels; only panels near the camera animate. Each panel runs a small program:
-- long stable periods, then short irregular bursts (like a failing starter/ballast), deterministic per panel.
-- Photosensitivity: flicker is local (never full-screen), bursts are short and rare, and with Reduced Motion the
-- panel only dims gently instead of switching on/off.
-- Status: TYPECHECKED. Not run in Studio.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Binder = require(ReplicatedStorage.Lib.Binder)

local ANIMATE_DISTANCE = 80
local UPDATE_HZ = 30

type Panel = {
	part: BasePart,
	lights: { { light: Light, base: number } },
	material: Enum.Material,
	rng: Random,
	nextBurst: number,
	burstEnd: number,
	nextToggle: number,
	on: boolean,
	level: number,
}
local panels: { [BasePart]: Panel } = {}

local function setLevel(p: Panel, level: number)
	if math.abs(level - p.level) < 0.01 then
		return
	end
	p.level = level
	for _, entry in p.lights do
		entry.light.Brightness = entry.base * level
		entry.light.Enabled = level > 0.03
	end
	p.part.Material = if level > 0.5 then p.material else Enum.Material.SmoothPlastic
end

Binder.bind("FlickerLight", function(inst, cleanup)
	if not inst:IsA("BasePart") then
		return
	end
	local lights = {}
	for _, d in inst:GetDescendants() do
		if d:IsA("Light") then
			table.insert(lights, { light = d, base = d.Brightness })
		end
	end
	-- Seed from position so every client sees the same pattern for the same panel.
	local pos = inst.Position
	local seed = math.floor(pos.X * 73.1 + pos.Y * 19.7 + pos.Z * 41.3) % 2147483647
	local rng = Random.new(seed)
	local p: Panel = {
		part = inst,
		lights = lights,
		material = inst.Material,
		rng = rng,
		nextBurst = os.clock() + rng:NextNumber(1, 8),
		burstEnd = 0,
		nextToggle = 0,
		on = true,
		level = 1,
	}
	panels[inst] = p
	cleanup:add(function()
		panels[inst] = nil
		setLevel(p, 1) -- leave the panel in its authored state if the tag is removed
	end)
end)

local accumulator = 0
RunService.PreRender:Connect(function(dt: number)
	accumulator += dt
	if accumulator < 1 / UPDATE_HZ then
		return
	end
	accumulator = 0
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local gentle = GuiService.ReducedMotionEnabled
	local now = os.clock()
	for part, p in panels do
		if (part.Position - eye).Magnitude > ANIMATE_DISTANCE then
			continue
		end
		if now >= p.nextBurst and p.burstEnd < now then
			p.burstEnd = now + p.rng:NextNumber(0.15, 1.2) -- a burst
			p.nextBurst = p.burstEnd + p.rng:NextNumber(3, 12) -- then stable for a while
		end
		if now < p.burstEnd then
			if now >= p.nextToggle then
				p.on = not p.on
				p.nextToggle = now + p.rng:NextNumber(0.03, 0.12) -- irregular, not a fixed strobe frequency
			end
			local target = if p.on then 1 else (if gentle then 0.6 else 0.05)
			setLevel(p, target)
		else
			setLevel(p, 1)
		end
	end
end)
```
<!-- /code -->

## Sound
Attach a quiet looping buzz to flickering panels (client-side, spatial, short attenuation) and play a click on each
off→on transition for the full effect.

## Photosensitivity
Keep flicker local to fixtures (never flash the whole screen), keep bursts short and rare, respect Reduced Motion,
and consider a "reduce flashing" setting that disables bursts entirely. Full-screen flashes above ~3 per second are a
known seizure risk.

## How to test
20 tagged panels in view: patterns differ per panel, identical across two clients; walk away 80+ studs → animation
stops (MicroProfiler shows no work); Reduced Motion on → gentle dimming only.

Sources: cd:effects/light-sources, cd:reference/engine/classes/Light, cd:reference/engine/classes/GuiService,
cd:production/publishing/accessibility.
