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
