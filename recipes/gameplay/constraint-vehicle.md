# Constraint vehicle with authenticated control and ownership

An asset-free, four-wheel skid-steer cart: hinged wheel motors, welded seat, bounded client intent, stale-input
braking, explicit whole-vehicle ownership policy, and cleanup. It is a physical example, not a tuned racing chassis.

Evidence: **TYPECHECKED** (strict, old + new solver, pinned Roblox definitions); pure logic **CLI-EXECUTED**.
**Studio / live: NOT RUN.**

## Architecture
- The server constructs chassis, seat, four wheels, attachments and motor HingeConstraints. There are no
  BodyMovers, imported models, invented mesh IDs, or dynamically assigned Script source.
- Native VehicleSeat controls supply local desktop/gamepad/touch input. Client sends only throttle/steer at 10 Hz;
  the server accepts them only from the current seated driver after health, seat, distance, number, range and rate checks.
- Skid-steering maps left/right motor velocities from throttle + differential steer. Empty seat or input older
  than 0.35 seconds sets both targets to zero. Motor torque and acceleration are finite design parameters.
- Default ownership is server-side for every unanchored part because constraint-connected parts can be separate
  assemblies. Seat change/leave reclaims ownership; after detachment the former driver returns to classic automatic
  character ownership. Optional client ownership trades trust for responsiveness.
- Out-of-bounds / extreme velocity resets are recovery diagnostics, not a physics anti-cheat proof. Scoring, races,
  purchases and other consequential outcomes must not trust a client-owned vehicle's position.

## When NOT to use

no suspension, gear train, Ackermann steering, collision-damage model, or competitive authority
claim. Use an established project vehicle controller when present. For competitive client prediction, investigate
engine server authority rather than enabling client ownership and assuming the velocity check secures it.

## Setup and integration
Copy `examples/vehicle` by service folder into a blank baseplate. The cart spawns at (0, 6, 0), so keep that area
clear and adjust the server `origin` to your authored spawn. Leave `CLIENT_OWNERSHIP=false` initially. Sit in Driver
and use the default vehicle controls. Four motor hinges share the same X-axis; no steering joints are implied.
Tune mass, wheel friction and motor limits against actual Studio captures and target-device network conditions.
If using this inside another place, give the owner script one lifetime and avoid duplicating the remote name.

## Implementation

### `examples/vehicle/ReplicatedStorage/Vehicle/Drive.luau`

<!-- code: examples/vehicle/ReplicatedStorage/Vehicle/Drive.luau -->
```luau
-- file: examples/vehicle/ReplicatedStorage/Vehicle/Drive.luau
--!strict
local Drive = {}
function Drive.valid(throttle: any, steer: any): boolean
	return type(throttle) == "number" and throttle == throttle and math.abs(throttle) <= 1
		and type(steer) == "number" and steer == steer and math.abs(steer) <= 1
end
function Drive.wheels(throttle: number, steer: number, occupied: boolean, age: number): (number, number)
	if not occupied or age > 0.35 or not Drive.valid(throttle, steer) then return 0, 0 end
	return math.clamp(throttle + steer * 0.7, -1, 1) * 16,
		math.clamp(throttle - steer * 0.7, -1, 1) * 16
end
return Drive
```
<!-- /code -->

### `examples/vehicle/ServerScriptService/VehicleServer.server.luau`

<!-- code: examples/vehicle/ServerScriptService/VehicleServer.server.luau -->
```luau
-- file: examples/vehicle/ServerScriptService/VehicleServer.server.luau
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
```
<!-- /code -->

### `examples/vehicle/StarterPlayer/StarterPlayerScripts/VehicleClient.client.luau`

<!-- code: examples/vehicle/StarterPlayer/StarterPlayerScripts/VehicleClient.client.luau -->
```luau
-- file: examples/vehicle/StarterPlayer/StarterPlayerScripts/VehicleClient.client.luau
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer :: Player
local remote = ReplicatedStorage:WaitForChild("VehicleIntent", 20) :: RemoteEvent?
if not remote then return end
local elapsed = 0
local connection = RunService.PreSimulation:Connect(function(dt: number)
	elapsed += dt
	if elapsed < 0.1 then return end
	elapsed = 0
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") and seat.Parent and seat.Parent.Name == "ConstraintCart" then
		-- VehicleSeat supplies desktop/gamepad/touch intent; server still authenticates the occupant.
		remote:FireServer(seat.ThrottleFloat, seat.SteerFloat)
	end
end)
script.Destroying:Connect(function() connection:Disconnect() end)
```
<!-- /code -->

## How to test

| Scenario | Required observation |
|---|---|
| CLI input validation | NaN, infinity and out-of-range intent rejected; empty/stale intent stops motors |
| Server & Clients, two players | Only the seat occupant can control the cart; other client's spam has no effect |
| Driver leaves / jumps / resets | Server reclaims every assembly; motors stop within the stale-input window |
| High latency and lost client updates | No permanently latched acceleration; responsiveness measured in both ownership modes |
| Flip / fall / excessive velocity | Recovery occurs without rewarding an impossible lap or punishing solely on a heuristic |
| Server ownership inspection | `GetNetworkOwner` on each assembly matches configured policy after each transition |
| Repeated destroy/create | No abandoned models, remotes, or per-frame connections |

Physics response and mobile seat controls remain NOT RUN until these checks are completed in Studio.

## Failure paths and limits
The reset clears velocities on every part/assembly; production recovery should also choose an unoccupied safe
spawn and validate the vehicle is not intersecting another character. The cart may tip or skid until
tuned; no ride-quality or performance claim is made. Don't infer server ownership from just the seat, and don't
use the demo's optional client-owned mode as proof of server-authoritative physics.

## Verification
From the skill directory, run `python tools/check_all.py`. Pure tests for this recipe:
`luau examples/tests/vehicle.spec.luau`. The checker runs both Luau solvers. Engine coverage remains NOT RUN until you retain
assertion output from the specified Studio scenario with Studio build, place revision, peers, and device.

Sources: cd:reference/engine/classes/HingeConstraint, cd:reference/engine/classes/VehicleSeat, cd:scripting/security/network-ownership, api:BasePart.SetNetworkOwner, api:BasePart.CanSetNetworkOwnership.
