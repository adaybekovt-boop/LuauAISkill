--!strict
local RunService = game:GetService("RunService")
local StudioTestService = game:GetService("StudioTestService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
if not RunService:IsStudio() then return end
-- GetTestArgs has a documented client issue; the server's opt-in remote is the gate.
local remote = ReplicatedStorage:WaitForChild("RegressionPeer", 20) :: RemoteEvent?
local fixture = ReplicatedStorage:WaitForChild("RegressionState", 20)
if not remote or not fixture then return end
local connection = remote.OnClientEvent:Connect(function(verb: string, phase: string, expected: number)
    if verb == "observe" then
        -- Remote/property ordering is not guaranteed. Wait for the explicit version with a deadline.
        local deadline = os.clock() + 10
        while fixture:GetAttribute("Revision") ~= expected and os.clock() < deadline do task.wait() end
        if fixture:GetAttribute("Revision") == expected then remote:FireServer("ack", phase) end
    elseif verb == "forge" then
        remote:FireServer("forge", 999999)
        remote:FireServer("forge", "invalid type")
        remote:FireServer("ack", phase)
    elseif verb == "leave" and StudioTestService:CanLeaveTest() then
        StudioTestService:LeaveTest()
    end
end)
remote:FireServer("ready", true)
script.Destroying:Connect(function() connection:Disconnect() end)
