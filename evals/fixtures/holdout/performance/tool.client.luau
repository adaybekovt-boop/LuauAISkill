local RunService = game:GetService("RunService")
local tool = script.Parent
tool.Equipped:Connect(function()
    RunService.RenderStepped:Connect(function()
        print(tool.Name)
    end)
end)
