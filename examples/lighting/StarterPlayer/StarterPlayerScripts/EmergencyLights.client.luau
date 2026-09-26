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
