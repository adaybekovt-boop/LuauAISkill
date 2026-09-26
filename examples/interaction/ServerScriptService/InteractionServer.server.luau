--!strict
-- Server-authoritative interactions via ProximityPrompts created for every tagged object.
-- The prompt is only an input device: the server re-checks rate, state, distance and (optionally) line of sight.
-- Requires: ReplicatedStorage.Lib (examples/lib), ReplicatedStorage.Interaction.Config, ServerScriptService.Interaction.Handlers.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Binder = require(ReplicatedStorage.Lib.Binder)
local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
local Validate = require(ReplicatedStorage.Lib.Validate)
local Config = require(ReplicatedStorage.Interaction.Config)
local Handlers = require(ServerScriptService.Interaction.Handlers)

local limiter = TokenBucket.new({ Interact = Config.RATE })
local nextAllowed: { [Instance]: number } = {}

local function attrNumber(inst: Instance, name: string, default: number, min: number, max: number): number
	return Validate.number(inst:GetAttribute(name), min, max) or default
end

local function attrString(inst: Instance, name: string, default: string): string
	return Validate.string(inst:GetAttribute(name), 64) or default
end

local function anchorPart(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	elseif target:IsA("Model") then
		return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function hasLineOfSight(character: Model, from: Vector3, target: Instance, to: Vector3): boolean
	local params = RaycastParams.new()
	params.ExcludeInstances = { character }
	local hit = Workspace:Raycast(from, to - from, params)
	return hit == nil or hit.Instance == target or hit.Instance:IsDescendantOf(target)
end

local function onTriggered(prompt: ProximityPrompt, target: Instance, player: Player)
	local now = os.clock()
	-- 1. cheap checks first
	if not limiter:allow(player, "Interact", now) then
		return
	end
	if target:GetAttribute("Enabled") == false or now < (nextAllowed[target] or 0) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	-- 2. spatial checks with server-side positions (never client-reported ones)
	local part = anchorPart(target)
	if not part then
		return
	end
	local maxDistance = prompt.MaxActivationDistance + Config.DISTANCE_SLACK
	if (part.Position - root.Position).Magnitude > maxDistance then
		return
	end
	if target:GetAttribute("RequireLineOfSight") == true then
		local head = character:FindFirstChild("Head")
		local eye = if head and head:IsA("BasePart") then head.Position else root.Position
		if not hasLineOfSight(character, eye, target, part.Position) then
			return
		end
	end
	-- 3. dispatch
	local handler = Handlers.get(attrString(target, "InteractionType", ""))
	if not handler then
		return
	end
	nextAllowed[target] = now + attrNumber(target, "Cooldown", Config.DEFAULT_COOLDOWN, 0, 60)
	handler({ player = player, character = character, target = target, prompt = prompt })
end

Binder.bind(Config.TAG, function(target, cleanup)
	local part = anchorPart(target)
	if not part then
		warn("Interactable without a BasePart:", target:GetFullName())
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = attrString(target, "ActionText", "Interact")
	prompt.ObjectText = attrString(target, "ObjectText", target.Name)
	prompt.MaxActivationDistance = attrNumber(target, "Distance", Config.DEFAULT_DISTANCE, 1, 50)
	prompt.HoldDuration = attrNumber(target, "HoldDuration", 0, 0, 10)
	prompt.Enabled = target:GetAttribute("Enabled") ~= false
	prompt.Parent = part -- set properties first, parent last
	cleanup:add(prompt)
	cleanup:connect(prompt.Triggered, function(player: Player)
		onTriggered(prompt, target, player)
	end)
	cleanup:connect(target:GetAttributeChangedSignal("Enabled"), function()
		prompt.Enabled = target:GetAttribute("Enabled") ~= false
	end)
	cleanup:add(function()
		nextAllowed[target] = nil
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	limiter:forget(player)
end)
