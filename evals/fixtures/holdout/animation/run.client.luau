local humanoid = script.Parent:WaitForChild("Humanoid")
local animation = Instance.new("Animation")
animation.AnimationId = "rbxassetid://123456"
game:GetService("RunService").Heartbeat:Connect(function()
    if humanoid.MoveDirection.Magnitude > 0 then
        humanoid:LoadAnimation(animation):Play()
    end
end)
