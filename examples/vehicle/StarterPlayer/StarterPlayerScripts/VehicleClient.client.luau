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
