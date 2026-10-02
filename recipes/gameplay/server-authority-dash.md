# Server-authority dash with replay-safe effects

An input-driven movement ability shared by client and server with fixed simulation, rollback-owned cooldown and
button latch, deterministic impulse, and a reversible state-driven visual. Server authority is opt-in per place.

Evidence: **TYPECHECKED** (strict, old + new solver, pinned Roblox definitions); pure logic **CLI-EXECUTED**.
**Studio / live: NOT RUN.**

## Architecture
- The server creates the same InputContext/InputAction under each Player. A ModuleScript is required by both
  sides; it binds at Hz60 and uses only Simulation Access APIs inside the callback.
- Cached Player/character/root/action references are gathered through events outside simulation. Character death,
  removal, late setup and respawn cancel stale registrations. No Players calls or Humanoid.Health read occurs inside.
- Cooldown, remaining effect duration and held-input latch live in root attributes, written only in the simulation
  callback. They roll back together. A new press after cooldown applies one forward horizontal impulse; vertical
  velocity is preserved. Holding the button does not auto-repeat.
- Effects are separate: a single client Highlight reads current simulated state during PreRender. Replaying a frame
  creates no new effect, sound, particle, receipt, remote or damage. Rollback to inactive disables the existing effect.
- The base character controller still owns ordinary locomotion. This is a dash impulse overlay, not a replacement
  walking controller. Verify callback priority and momentum interaction with the specific controller you use.

## When NOT to use

do not paste into classic networking without enabling fixed simulation/server authority.
Don't convert a shipped game without a branch-place compatibility pass. Do not use this visual state as an
irreversible hit/damage trigger; one-shot effects need a confirmed-event policy or reversible presentation.

## Setup and integration
1. In a branch/test place, use Studio Workspace Properties to choose Server authority mode; this configures the
   required replication, fixed simulation, deferred signals, streaming and input-action settings. Game scripts
   cannot read/write the protected authority setting to repair setup automatically.
2. Copy `examples/simulation` by service folder. Require `Simulation.start` exactly once per peer (the supplied
   scripts do that); don't add another independent copy of the simulation ModuleScript.
3. Dash uses Q / gamepad B, plus an InputBinding-backed touch button. Change bindings to avoid project conflicts.
   Priority 2500 is explicit, not a promise that every custom character controller runs before it.
4. Keep custom dash attributes below engine prediction limits and their names stable across peers. Set the local
   ReducedMotion preference to suppress the visual. Leave health/respawn changes outside the simulation.
5. Perform simulated-latency and misprediction tests before enabling this in a production place.

## Implementation

### `examples/simulation/ReplicatedStorage/Dash/DashState.luau`

<!-- code: examples/simulation/ReplicatedStorage/Dash/DashState.luau -->
```luau
-- file: examples/simulation/ReplicatedStorage/Dash/DashState.luau
--!strict
export type DashData = { cooldown: number, remaining: number, held: boolean }
local Model = {}
function Model.step(previous: DashData, pressed: boolean, dt: number): (DashData, boolean)
    local delta = math.clamp(dt, 0, 1 / 30)
    local cooldown = math.max(0, previous.cooldown - delta)
    local remaining = math.max(0, previous.remaining - delta)
    local start = pressed and not previous.held and cooldown == 0
    if start then cooldown, remaining = 1.5, 0.18 end
    return { cooldown = cooldown, remaining = remaining, held = pressed }, start
end
return Model
```
<!-- /code -->

### `examples/simulation/ReplicatedStorage/Dash/Simulation.luau`

<!-- code: examples/simulation/ReplicatedStorage/Dash/Simulation.luau -->
```luau
-- file: examples/simulation/ReplicatedStorage/Dash/Simulation.luau
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
```
<!-- /code -->

### `examples/simulation/ServerScriptService/DashServer.server.luau`

<!-- code: examples/simulation/ServerScriptService/DashServer.server.luau -->
```luau
-- file: examples/simulation/ServerScriptService/DashServer.server.luau
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
```
<!-- /code -->

### `examples/simulation/StarterPlayer/StarterPlayerScripts/DashClient.client.luau`

<!-- code: examples/simulation/StarterPlayer/StarterPlayerScripts/DashClient.client.luau -->
```luau
-- file: examples/simulation/StarterPlayer/StarterPlayerScripts/DashClient.client.luau
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
```
<!-- /code -->

## How to test

| Scenario | Required observation |
|---|---|
| CLI rollback/replay | Same initial state + input + dt yields same state/start flag; corrected inactive state removes effect |
| Server & Clients, Q/B/touch | Owning client predicts movement; authoritative state converges for all peers |
| Hold, release, cooldown, repeated press | One impulse per permitted press; holding never repeats |
| Inject latency / conflicting movement | Corrections do not create duplicate Highlights/sounds or grant duplicate damage |
| Die or respawn during setup/ability | Old root is detached; new action/root registration works; no corpse control |
| Script stop/restart | Fixed callback and lifecycle connections disconnect |
| Controller and priority integration | Default walking controller does not instantly cancel dash; exact effect validated, not inferred |

The CLI checks the reducer only. It cannot establish engine rollback, prediction scope, physics, or replication.

## Failure paths and limits
The impulse direction is the synchronized root orientation, not an unsynchronized camera direction. Default
walking/friction may immediately damp the impulse, so tune through the project's controller rather than writing
velocity continuously from two owners. Death detaches simulation before the visual duration naturally counts down;
the client renderer also gates on living character state when integrated. No invulnerability, hitbox, damage,
stamina purchase, animation ID, or irreversible animation-track cache is implied. Client prediction can temporarily
show an ability later corrected by the server; that is expected and must remain cosmetic.

## Verification
From the skill directory, run `python tools/check_all.py`. Pure tests for this recipe:
`luau examples/tests/simulation.spec.luau`. The checker runs both Luau solvers. Engine coverage remains NOT RUN until you retain
assertion output from the specified Studio scenario with Studio build, place revision, peers, and device.

Sources: cd:projects/server-authority/index, cd:projects/server-authority/techniques, cd:input/input-action-system, api:RunService.BindToSimulation, api:InputAction.GetState, api:BasePart.AssemblyLinearVelocity, api:Instance.GetAttribute, api:Instance.SetAttribute.
