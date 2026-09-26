-- BAD: intentionally broken eval fixture (do not copy). Server memory grows for hours until the server crashes.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lastPositions = {}

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		RunService.Heartbeat:Connect(function()
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				lastPositions[player.Name .. tostring(tick())] = root.Position
			end
		end)
	end)
end)
