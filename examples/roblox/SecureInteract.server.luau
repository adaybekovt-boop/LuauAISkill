--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: Roblox Script / ServerScriptService / RunContext Server
-- Limited demo: rate, schema, membership, alive, distance and line-of-sight checks. Not a complete anti-cheat.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local tokenModule = script.Parent:WaitForChild("TokenBucket", 10)
assert(tokenModule and tokenModule:IsA("ModuleScript"), "Install TokenBucket ModuleScript beside this Script")
local TokenBucket = require(tokenModule)
local remotes = ReplicatedStorage:FindFirstChild("TKDemoRemotes")
if remotes == nil then
    remotes = Instance.new("Folder")
    remotes.Name = "TKDemoRemotes"
    remotes.Parent = ReplicatedStorage
end
assert(remotes:IsA("Folder"), "TKDemoRemotes name collision")
local existing = remotes:FindFirstChild("Interact")
assert(existing == nil, "Demo already started, or remote name collision; do not run duplicate entrypoints")
local remote = Instance.new("RemoteEvent")
remote.Name = "Interact"
remote.Parent = remotes
-- Explicit local interface also works when an editor cannot resolve a dynamic require path.
type Bucket = {take: (number, number?) -> boolean, available: (number) -> number}
local buckets: {[Player]: Bucket} = {}
local nextUse: {[Instance]: number} = {}
local RANGE = 12 -- demo policy, not a platform guarantee
local function finite(n: number): boolean
    return n == n and math.abs(n) < math.huge
end
local requestConnection = remote.OnServerEvent:Connect(function(player: Player, target: unknown)
    local now = os.clock()
    local bucket = buckets[player]
    if bucket == nil then
        bucket = TokenBucket.new(4, 2, now)
        buckets[player] = bucket
    end
    if not bucket.take(now) then return end
    if typeof(target) ~= "Instance" or not target:IsA("BasePart") then return end
    if not target:IsDescendantOf(Workspace) or not CollectionService:HasTag(target, "InteractableDemo") then return end
    if not target.Anchored then return end -- this demo only permits static interaction targets
    local character = player.Character
    if character == nil then return end
    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then return end
    local delta = target.Position - root.Position
    if not (finite(delta.X) and finite(delta.Y) and finite(delta.Z)) then return end
    local distance = delta.Magnitude
    if distance > RANGE or not finite(distance) then return end
    if now < (nextUse[target] or 0) then return end
    if distance > 0.01 then
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {character}
        local hit = Workspace:Raycast(root.Position, delta, params)
        if hit == nil or hit.Instance ~= target then return end
    end
    -- No yield between final validation and state commit.
    nextUse[target] = now + 0.5
    local enabled = target:GetAttribute("DemoActive") ~= true
    target:SetAttribute("DemoActive", enabled)
    remote:FireClient(player, target, enabled)
end)
local leaving = Players.PlayerRemoving:Connect(function(player: Player) buckets[player] = nil end)
local removed = CollectionService:GetInstanceRemovedSignal("InteractableDemo"):Connect(function(instance)
    nextUse[instance] = nil
end)
script.Destroying:Connect(function()
    requestConnection:Disconnect()
    leaving:Disconnect()
    removed:Disconnect()
    table.clear(buckets)
    table.clear(nextUse)
    remote:Destroy()
end)
-- Important: checking replicated character distance does NOT prevent speed/fly exploits.
-- Movement authority/validation is a separate requirement; see handbook/08 and 10.
