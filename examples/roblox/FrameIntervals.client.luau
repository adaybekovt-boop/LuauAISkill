--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: Roblox Script in ReplicatedStorage / RunContext Client
-- Records render interval samples, not GPU/CPU measurements.
local RunService = game:GetService("RunService")
local statsModule = script.Parent:WaitForChild("FrameStats", 10)
assert(statsModule and statsModule:IsA("ModuleScript"), "Install FrameStats beside this client Script")
local FrameStats = require(statsModule)
local stats = FrameStats.new(600)
local elapsed = 0
local connection = RunService.PreRender:Connect(function(dt: number)
    stats.push(dt)
    elapsed += dt
    if elapsed >= 10 then
        elapsed = 0
        local snapshot = stats.snapshot()
        if snapshot then
            print("OBSERVED RENDER INTERVAL ms (NOT GPU timing)", snapshot.count, snapshot.meanMs, snapshot.p95Ms, snapshot.p99Ms)
        end
    end
end)
script.Destroying:Connect(function() connection:Disconnect() end)
