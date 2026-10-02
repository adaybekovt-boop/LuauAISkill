--!strict
-- Studio-only setup: choose Server authority mode in Workspace Properties before running.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Simulation = require(ReplicatedStorage.Dash.Simulation)
local function inputs(player: Player)
	-- Input contexts have player lifetime; restarting this server script reuses the existing context.
	local existing = player:FindFirstChild("DashInputs")
	if existing then
		assert(existing:IsA("InputContext") and existing:FindFirstChild("Dash"), "Conflicting DashInputs")
		return
	end
	local context = Instance.new("InputContext")
	context.Name = "DashInputs"; context.Enabled = true
	local action = Instance.new("InputAction")
	action.Name = "Dash"; action.Type = Enum.InputActionType.Bool
	for _, key in { Enum.KeyCode.Q, Enum.KeyCode.ButtonB } do
		local binding = Instance.new("InputBinding")
		binding.KeyCode = key; binding.Parent = action
	end
	action.Parent = context; context.Parent = player
end
local added = Players.PlayerAdded:Connect(inputs)
for _, player in Players:GetPlayers() do inputs(player) end
Simulation.start()
script.Destroying:Connect(function() added:Disconnect(); Simulation.stop() end)
