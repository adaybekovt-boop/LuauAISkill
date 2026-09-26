--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: Roblox Script in ReplicatedStorage / RunContext Client
-- Input Action demo for ordinary client architecture, not BindToSimulation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
assert(player ~= nil, "Client RunContext required")
local folder = ReplicatedStorage:WaitForChild("TKDemoRemotes", 10)
assert(folder ~= nil, "Start the server demo first")
local remote = folder:WaitForChild("Interact", 10)
assert(remote and remote:IsA("RemoteEvent"), "Interact RemoteEvent missing")
local context = Instance.new("InputContext")
context.Name = "TKDemoInput"
context.Enabled = true
context.Parent = player
local action = Instance.new("InputAction")
action.Name = "Interact"
action.Type = Enum.InputActionType.Bool
action.Parent = context
local keyboard = Instance.new("InputBinding")
keyboard.KeyCode = Enum.KeyCode.E
keyboard.Parent = action
local gamepad = Instance.new("InputBinding")
gamepad.KeyCode = Enum.KeyCode.ButtonX
gamepad.Parent = action
local pressed = action.Pressed:Connect(function()
    local camera = Workspace.CurrentCamera
    if camera == nil then return end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = if player.Character then {player.Character} else {}
    local hit = Workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 20, params)
    if hit then remote:FireServer(hit.Instance) end -- server independently validates
end)
local acknowledged = remote.OnClientEvent:Connect(function(target: unknown, active: unknown)
    -- A referenced instance may have streamed out or been destroyed before delivery.
    local name = if typeof(target) == "Instance" then target.Name else "unavailable instance"
    print("Server confirmed demo interaction", name, active)
end)
script.Destroying:Connect(function()
    pressed:Disconnect()
    acknowledged:Disconnect()
    context:Destroy()
end)
-- Add a touch GuiButton binding (InputBinding.UIButton) in your UI adapter.
-- This example intentionally does not claim a complete mobile HUD.
