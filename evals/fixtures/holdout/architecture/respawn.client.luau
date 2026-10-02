local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
player.CharacterAdded:Connect(function(character)
    local humanoid = character:WaitForChild("Humanoid")
    RunService.Heartbeat:Connect(function()
        print(humanoid.Health)
    end)
end)
