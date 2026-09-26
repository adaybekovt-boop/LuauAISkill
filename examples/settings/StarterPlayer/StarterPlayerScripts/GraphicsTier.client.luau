--!strict
-- Graphics tiers for YOUR content (the engine's own quality level is separate and not readable by game scripts).
-- Tier comes from ClientSettings.GraphicsTier; "Auto" = start from a device heuristic, then adapt to measured frame
-- time with hysteresis (down fast, up slowly, never oscillate). Applies by tags, so streamed-in content is covered:
--   FX_Decor  (ParticleEmitter/Beam/Trail): off on Low, rate × multiplier otherwise
--   Light_Fill (Light): off on Low; Light_Shadow (Light): Shadows only on High/Ultra
--   Lighting post effects: Bloom off on Low, DepthOfField/SunRays only on High/Ultra
-- Gameplay-relevant visuals (fog density, enemy visibility, darkness) must NOT depend on the tier.
-- Status: TYPECHECKED. Not run in Studio.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientSettings = require(ReplicatedStorage.Settings.ClientSettings)

type Tier = "Low" | "Medium" | "High" | "Ultra"
local ORDER: { Tier } = { "Low", "Medium", "High", "Ultra" }
local RATE: { [Tier]: number } = { Low = 0, Medium = 0.5, High = 1, Ultra = 1.25 }
local TARGET_FRAME = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then 1 / 30 else 1 / 60

local current: Tier = "High"
local baseRates: { [Instance]: number } = {} -- original Rate per emitter (weak by instance lifetime via untag)

local function rank(t: Tier): number
	return table.find(ORDER, t) or 3
end

local function applyTo(inst: Instance, tag: string)
	if tag == "FX_Decor" then
		if inst:IsA("ParticleEmitter") then
			baseRates[inst] = baseRates[inst] or inst.Rate
			inst.Rate = (baseRates[inst] :: number) * RATE[current]
			inst.Enabled = RATE[current] > 0
		elseif inst:IsA("Beam") then
			inst.Enabled = current ~= "Low"
		elseif inst:IsA("Trail") then
			inst.Enabled = current ~= "Low"
		end
	elseif tag == "Light_Fill" and inst:IsA("Light") then
		inst.Enabled = current ~= "Low"
	elseif tag == "Light_Shadow" and inst:IsA("Light") then
		inst.Shadows = rank(current) >= 3
	end
end

local TAGS = { "FX_Decor", "Light_Fill", "Light_Shadow" }

local function applyAll()
	for _, tag in TAGS do
		for _, inst in CollectionService:GetTagged(tag) do
			applyTo(inst, tag)
		end
	end
	for _, effect in Lighting:GetChildren() do
		if effect:IsA("BloomEffect") then
			effect.Enabled = current ~= "Low"
		elseif effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") then
			effect.Enabled = rank(current) >= 3
		end
	end
end

for _, tag in TAGS do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst: Instance)
		applyTo(inst, tag)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
		baseRates[inst] = nil
	end)
end

local function setTier(t: Tier)
	if t ~= current then
		current = t
		applyAll()
	end
end

-- Adaptive controller for "Auto": p90-ish estimate via EMA of frame time, stepped with hysteresis.
local ema = TARGET_FRAME
local overSince: number? = nil
local stableSince = os.clock()
local STEP_DOWN_AFTER = 5 -- seconds consistently over budget
local STEP_UP_AFTER = 60 -- seconds consistently under 70 % of budget

RunService.PreRender:Connect(function(dt: number)
	if ClientSettings.get("GraphicsTier") ~= "Auto" then
		return
	end
	ema += (math.min(dt, 0.25) - ema) * 0.05
	local now = os.clock()
	if ema > TARGET_FRAME * 1.1 then
		overSince = overSince or now
		stableSince = now
		if now - (overSince :: number) > STEP_DOWN_AFTER and rank(current) > 1 then
			setTier(ORDER[rank(current) - 1])
			overSince = nil
		end
	else
		overSince = nil
		if ema > TARGET_FRAME * 0.7 then
			stableSince = now
		elseif now - stableSince > STEP_UP_AFTER and rank(current) < 4 then
			setTier(ORDER[rank(current) + 1])
			stableSince = now
		end
	end
end)

local function fromSetting()
	local chosen = ClientSettings.get("GraphicsTier")
	if chosen == "Auto" then
		-- Device heuristic as the starting point only.
		setTier(if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Medium" else "High")
	elseif type(chosen) == "string" and table.find(ORDER, chosen :: any) then
		setTier(chosen :: Tier)
	end
end
ClientSettings.changed:connect(function(id: string)
	if id == "GraphicsTier" then
		fromSetting()
	end
end)
fromSetting()
applyAll()
