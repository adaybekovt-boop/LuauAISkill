--!strict
-- Ragdoll: replace Motor6Ds with BallSocketConstraints (reversible). Works for R15 and R6.
-- Death ragdoll: server-only (dead Humanoids don't fight physics). Knock-down of a LIVING player: the owning
-- client must also put its Humanoid into the Physics state (RagdollClient.client.luau) — the server can't,
-- because player characters are simulated by their owner.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ragdoll = {}

local stateRemote: RemoteEvent? = nil
local function remote(): RemoteEvent
	if stateRemote then
		return stateRemote
	end
	local r = Instance.new("RemoteEvent")
	r.Name = "RagdollState"
	r.Parent = ReplicatedStorage
	stateRemote = r
	return r
end

-- Call once when the character spawns (server): keep joints on death so we can ragdoll instead of falling apart.
function Ragdoll.prepare(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.BreakJointsOnDeath = false
	end
	remote() -- make sure the remote exists before clients look for it
end

function Ragdoll.enable(character: Model)
	if character:GetAttribute("Ragdolled") == true then
		return
	end
	character:SetAttribute("Ragdolled", true)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Docs: with RequiresNeck the character dies if the Neck Motor6D is "removed or disconnected even
		-- momentarily". Whether Enabled=false counts isn't documented, so turn it off for alive knock-downs.
		humanoid.RequiresNeck = false
	end
	for _, motor in character:GetDescendants() do
		if not motor:IsA("Motor6D") or not motor.Part0 or not motor.Part1 then
			continue
		end
		local part0, part1 = motor.Part0 :: BasePart, motor.Part1 :: BasePart
		local a0 = Instance.new("Attachment")
		a0.Name = "RagdollA0"
		a0.CFrame = motor.C0
		a0.Parent = part0
		local a1 = Instance.new("Attachment")
		a1.Name = "RagdollA1"
		a1.CFrame = motor.C1
		a1.Parent = part1
		local socket = Instance.new("BallSocketConstraint")
		socket.Name = "RagdollSocket"
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.LimitsEnabled = true
		socket.UpperAngle = if part1.Name:find("Head") then 30 else 60
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -45
		socket.TwistUpperAngle = 45
		socket.Parent = part0
		local noCollide = Instance.new("NoCollisionConstraint") -- adjacent limbs would jitter against each other
		noCollide.Name = "RagdollNoCollide"
		noCollide.Part0 = part0
		noCollide.Part1 = part1
		noCollide.Parent = part0
		motor.Enabled = false
		if part1.Name ~= "HumanoidRootPart" then
			part1.CanCollide = true
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CanCollide = false -- the invisible root box would prop the body up
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		remote():FireClient(player, true)
	elseif humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- server-owned NPC
	end
end

function Ragdoll.disable(character: Model)
	if character:GetAttribute("Ragdolled") ~= true then
		return
	end
	character:SetAttribute("Ragdolled", nil)
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			d.Enabled = true
		elseif d.Name:sub(1, 7) == "Ragdoll" and (d:IsA("Constraint") or d:IsA("Attachment")
			or d:IsA("NoCollisionConstraint")) then
			d:Destroy()
		end
	end
	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.RequiresNeck = true
	end
	if player then
		remote():FireClient(player, false)
	elseif humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	-- Limb CanCollide is managed by the Humanoid again once it leaves the Physics state.
end

-- Temporary knock-down (alive). Returns immediately.
function Ragdoll.knockDown(character: Model, seconds: number)
	Ragdoll.enable(character)
	task.delay(seconds, function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if character.Parent and humanoid and humanoid.Health > 0 then
			Ragdoll.disable(character)
		end
	end)
end

return Ragdoll
