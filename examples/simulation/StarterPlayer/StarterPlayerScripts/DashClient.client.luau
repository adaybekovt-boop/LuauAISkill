--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Simulation = require(ReplicatedStorage.Dash.Simulation)
local player = Players.LocalPlayer :: Player
Simulation.start()
-- Replay-safe effect: one persistent Highlight, rendered from current simulation state.
-- Rollback to inactive removes it; replay never creates another effect or fires an irreversible sound.
local highlight = Instance.new("Highlight")
highlight.Name = "DashVisual"; highlight.FillColor = Color3.fromRGB(90, 180, 255)
highlight.FillTransparency = 0.7; highlight.OutlineTransparency = 1; highlight.Enabled = false
highlight.Parent = workspace
local connection = RunService.PreRender:Connect(function()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local remaining = root and root:GetAttribute("DashRemaining")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    highlight.Adornee = character
    highlight.Enabled = humanoid ~= nil and humanoid.Health > 0 and type(remaining) == "number" and remaining > 0
        and player:GetAttribute("ReducedMotion") ~= true
end)
local gui: ScreenGui? = nil
local touchBinding: InputBinding? = nil
if UserInputService.TouchEnabled then
    local context = player:WaitForChild("DashInputs", 15)
    local action = context and context:WaitForChild("Dash", 15)
    if action and action:IsA("InputAction") then
        local screen = Instance.new("ScreenGui")
        screen.Name = "DashTouch"; screen.ResetOnSpawn = false
        local button = Instance.new("TextButton")
        button.Text = "Dash"; button.Size = UDim2.fromOffset(80, 64)
        button.Position = UDim2.new(1, -190, 1, -160); button.Parent = screen
        screen.Parent = player:WaitForChild("PlayerGui")
        local binding = Instance.new("InputBinding")
        binding.UIButton = button; binding.Parent = action
        touchBinding = binding
        gui = screen
    end
end
script.Destroying:Connect(function()
    connection:Disconnect(); highlight:Destroy(); if gui then gui:Destroy() end
    if touchBinding then touchBinding:Destroy() end
    Simulation.stop()
end)
