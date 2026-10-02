--!strict
-- Required on server AND client. Only synchronized properties/methods inside BindToSimulation.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Model = require(script.Parent.DashState)
type Entry = { root: BasePart, action: InputAction }
local entries: { [Player]: Entry } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local generation: { [Player]: number } = {}
local deathConnections: { [Player]: RBXScriptConnection } = {}
local connections: { RBXScriptConnection } = {}
local started = false
local Simulation = {}
local function detach(player: Player)
    generation[player] = (generation[player] or 0) + 1
    entries[player] = nil
    local death = deathConnections[player]
    if death then death:Disconnect(); deathConnections[player] = nil end
end
local function attach(player: Player, character: Model)
    detach(player)
    local token = generation[player]
    local root = character:WaitForChild("HumanoidRootPart", 10)
    local humanoid = character:WaitForChild("Humanoid", 10)
    local context = player:WaitForChild("DashInputs", 10)
    local action = context and context:WaitForChild("Dash", 10)
    if generation[player] ~= token or player.Character ~= character then return end
    if root and root:IsA("BasePart") and action and action:IsA("InputAction") then
        if not humanoid or not humanoid:IsA("Humanoid") or humanoid.Health <= 0 then return end
        entries[player] = { root = root, action = action }
        deathConnections[player] = humanoid.Died:Connect(function() detach(player) end)
    end
end
local function onPlayer(player: Player)
    playerConnections[player] = {
        player.CharacterAdded:Connect(function(character) task.spawn(attach, player, character) end),
        player.CharacterRemoving:Connect(function() detach(player) end),
    }
    if player.Character then task.spawn(attach, player, player.Character) end
end
local function numberAttribute(root: BasePart, name: string): number
    local v = root:GetAttribute(name)
    return if type(v) == "number" then v else 0
end
function Simulation.start()
    if started then return end
    started = true
    table.insert(connections, Players.PlayerAdded:Connect(onPlayer))
    table.insert(connections, Players.PlayerRemoving:Connect(function(player)
        detach(player)
        local list = playerConnections[player]
        if list then for _, c in list do c:Disconnect() end end
        playerConnections[player], generation[player] = nil, nil
    end))
    for _, player in Players:GetPlayers() do onPlayer(player) end
    table.insert(connections, RunService:BindToSimulation(function(dt: number)
        for _, entry in entries do
            local root = entry.root
            local nextState, start = Model.step({ cooldown = numberAttribute(root, "DashCooldown"),
                remaining = numberAttribute(root, "DashRemaining"), held = root:GetAttribute("DashHeld") == true },
                entry.action:GetState() == true, dt)
            root:SetAttribute("DashCooldown", nextState.cooldown)
            root:SetAttribute("DashRemaining", nextState.remaining)
            root:SetAttribute("DashHeld", nextState.held)
            if start then
                local look = root.CFrame.LookVector
                local flat = Vector3.new(look.X, 0, look.Z)
                if flat.Magnitude > 0.001 then
                    local velocity = root.AssemblyLinearVelocity
                    root.AssemblyLinearVelocity = flat.Unit * 52 + Vector3.new(0, velocity.Y, 0)
                end
            end
        end
    end, Enum.StepFrequency.Hz60, 2500))
end
function Simulation.stop()
    for _, c in connections do c:Disconnect() end
    for player, list in playerConnections do
        detach(player)
        for _, c in list do c:Disconnect() end
    end
    table.clear(connections); table.clear(playerConnections); table.clear(entries); table.clear(generation)
    started = false
end
return Simulation
