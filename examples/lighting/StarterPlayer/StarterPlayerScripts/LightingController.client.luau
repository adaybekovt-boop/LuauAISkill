--!strict
-- Client lighting controller: blends between LightingPresets as the camera moves through tagged zones.
--   Zones: parts tagged "LightingZone" (Anchored, CanCollide/CanQuery false, Transparency 1) with attributes
--          Preset (string) and optional Priority (number, higher wins where zones overlap)
--   Default: Workspace attribute "LightingPreset" (server-set) or HorrorInterior
--   Workspace attribute PowerState == "Emergency" overrides everything with EmergencyRed
-- Ownership rule: the server must NOT also write these Lighting/effect properties, or its replicated changes will
-- overwrite the client's blend. Post effects are created client-side (names start with "LC_").
-- Status: TYPECHECKED. Not run in Studio.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Presets = require(ReplicatedStorage.LightingPresets)

local CHECK_INTERVAL = 0.25
local CONFIRM_CHECKS = 2 -- hysteresis: a new zone must win twice in a row before we blend
local BLEND = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local function ensure(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or ensure("Atmosphere", "LC_Atmosphere")
local grade = ensure("ColorCorrectionEffect", "LC_Grade")
local bloom = ensure("BloomEffect", "LC_Bloom")
local sunRays = ensure("SunRaysEffect", "LC_SunRays") :: SunRaysEffect

local tweens: { Tween } = {}

local function tweenProps(inst: Instance, props: { [string]: any })
	local goals = {}
	for prop, value in props do
		if type(value) == "boolean" then
			(inst :: any)[prop] = value -- booleans can't tween
		else
			goals[prop] = value
		end
	end
	local t = TweenService:Create(inst, BLEND, goals)
	table.insert(tweens, t)
	t:Play()
end

local currentName: string? = nil
local function apply(name: string)
	local preset = Presets[name]
	if not preset or name == currentName then
		return
	end
	currentName = name
	for _, t in tweens do
		t:Cancel() -- a new blend starts from wherever the old one got to
	end
	table.clear(tweens)
	tweenProps(Lighting, preset.lighting)
	tweenProps(atmosphere, preset.atmosphere)
	tweenProps(grade, preset.colorCorrection)
	tweenProps(bloom, preset.bloom)
	if preset.sunRays then
		sunRays.Enabled = true
		tweenProps(sunRays, preset.sunRays)
	else
		sunRays.Enabled = false
	end
end

local function inside(zone: BasePart, point: Vector3): boolean
	local rel = zone.CFrame:PointToObjectSpace(point)
	local half = zone.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local function desired(point: Vector3): string
	if Workspace:GetAttribute("PowerState") == "Emergency" then
		return "EmergencyRed"
	end
	local best: string? = nil
	local bestPriority = -math.huge
	for _, zone in CollectionService:GetTagged("LightingZone") do
		if zone:IsA("BasePart") and inside(zone, point) then
			local preset = zone:GetAttribute("Preset")
			local priority = zone:GetAttribute("Priority")
			local p = if type(priority) == "number" then priority else 0
			if type(preset) == "string" and Presets[preset] and p > bestPriority then
				best, bestPriority = preset, p
			end
		end
	end
	local default = Workspace:GetAttribute("LightingPreset")
	return best or (if type(default) == "string" and Presets[default] then default else "HorrorInterior")
end

local candidate: string? = nil
local streak = 0
while true do
	local camera = Workspace.CurrentCamera
	if camera then
		local want = desired(camera.CFrame.Position)
		if want == currentName then
			streak = 0
		elseif want == candidate then
			streak += 1
			if streak >= CONFIRM_CHECKS or currentName == nil then
				apply(want)
				streak = 0
			end
		else
			candidate, streak = want, 1
			if currentName == nil then
				apply(want) -- first frame: no blend delay
			end
		end
	end
	task.wait(CHECK_INTERVAL)
end
