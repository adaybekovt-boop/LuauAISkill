--!strict
-- Classic physics, not Workspace server-authority mode. Safe default: server owns every assembly.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Drive = require(ReplicatedStorage.Vehicle.Drive)
local CLIENT_OWNERSHIP = false -- opt-in only for non-competitive feel; client-owned physics is untrusted
local remote = Instance.new("RemoteEvent")
remote.Name = "VehicleIntent"; remote.Parent = ReplicatedStorage
local car = Instance.new("Model")
car.Name = "ConstraintCart"
local function part(name: string, size: Vector3, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Anchored = false; p.Parent = car
	return p
end
local origin = CFrame.new(0, 6, 0)
local body = part("Chassis", Vector3.new(4, 1, 6), origin)
body.Color = Color3.fromRGB(45, 100, 140)
local seat = Instance.new("VehicleSeat")
seat.Name = "Driver"; seat.Size = Vector3.new(2, 1, 2); seat.CFrame = origin * CFrame.new(0, 1, 0)
seat.Parent = car
local weld = Instance.new("WeldConstraint")
weld.Part0 = body; weld.Part1 = seat; weld.Parent = body
local motors: { { hinge: HingeConstraint, side: number } } = {}
for _, x in { -3, 3 } do
	for _, z in { -2, 2 } do
		local wheel = part("Wheel", Vector3.new(1, 2, 2), origin * CFrame.new(x, -0.5, z))
		wheel.Shape = Enum.PartType.Cylinder
		wheel.CustomPhysicalProperties = PhysicalProperties.new(1, 0.6, 0, 100, 100)
		local chassisAttachment = Instance.new("Attachment")
		chassisAttachment.Position = Vector3.new(x, -0.5, z); chassisAttachment.Parent = body
		local wheelAttachment = Instance.new("Attachment")
		wheelAttachment.Parent = wheel
		local hinge = Instance.new("HingeConstraint")
		hinge.Attachment0 = chassisAttachment; hinge.Attachment1 = wheelAttachment
		hinge.ActuatorType = Enum.ActuatorType.Motor; hinge.MotorMaxTorque = 1800
		hinge.MotorMaxAcceleration = 30; hinge.Parent = body
		table.insert(motors, { hinge = hinge, side = x })
	end
end
car.PrimaryPart = body; car.Parent = workspace
local driver: Player? = nil
local throttle, steer, received = 0, 0, 0
local lastRequest: { [Player]: number } = {}
local function ownership(player: Player?)
	-- Constraints can connect separate assemblies. Assign every unanchored part, not just the chassis.
	for _, item in car:GetDescendants() do
		if item:IsA("BasePart") then
			local canSet = item:CanSetNetworkOwnership()
			if canSet then item:SetNetworkOwner(player) end
		end
	end
end
local function occupantChanged()
	local previous = driver
	local character = if seat.Occupant then seat.Occupant.Parent else nil
	driver = if character and character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil
	throttle, steer, received = 0, 0, 0
	ownership(if CLIENT_OWNERSHIP then driver else nil)
	if previous and previous ~= driver then
		-- The SeatWeld can temporarily join the avatar to the car's ownership assembly.
		task.defer(function()
			local oldCharacter = previous.Character
			local humanoid = oldCharacter and oldCharacter:FindFirstChildOfClass("Humanoid")
			local root = humanoid and humanoid.RootPart
			if root and humanoid and humanoid.SeatPart ~= seat and root:CanSetNetworkOwnership() then
				root:SetNetworkOwnershipAuto() -- restore classic character ownership after detachment
			end
		end)
	end
end
local connections: { RBXScriptConnection } = {}
table.insert(connections, seat:GetPropertyChangedSignal("Occupant"):Connect(occupantChanged))
occupantChanged()
table.insert(connections, remote.OnServerEvent:Connect(function(player: Player, t: any, s: any)
	local now = os.clock()
	if now - (lastRequest[player] or -1) < 0.07 then return end
	lastRequest[player] = now
	if player ~= driver or not Drive.valid(t, s) then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart ~= seat or not root
		or (root.Position - seat.Position).Magnitude > 12 then return end
	throttle, steer, received = t, s, now
end))
table.insert(connections, RunService.PreSimulation:Connect(function()
	local left, right = Drive.wheels(throttle, steer, driver ~= nil, os.clock() - received)
	for _, entry in motors do entry.hinge.AngularVelocity = if entry.side < 0 then left else right end
	-- Diagnostics, not proof against a physics exploiter. Game rewards must use server-owned state.
	if body.AssemblyLinearVelocity.Magnitude > 100 or body.Position.Y < -200 then
		ownership(nil)
		if seat.Occupant then seat.Occupant.Sit = false end
		car:PivotTo(origin)
		for _, item in car:GetDescendants() do
			if item:IsA("BasePart") then
				item.AssemblyLinearVelocity = Vector3.zero
				item.AssemblyAngularVelocity = Vector3.zero
			end
		end
		throttle, steer, received = 0, 0, 0
	end
end))
table.insert(connections, Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
	if driver == player then driver = nil; ownership(nil); throttle, steer = 0, 0 end
end))
script.Destroying:Connect(function()
	for _, c in connections do c:Disconnect() end
	remote:Destroy(); car:Destroy()
end)
