-- BAD: intentionally broken eval fixture (do not copy). Boss NPC stutters; server frame time 40 ms.
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local boss = workspace.Boss
local target = nil

RunService.Heartbeat:Connect(function()
	target = workspace:FindFirstChild("Player1")
	if target then
		local path = PathfindingService:CreatePath()
		path:ComputeAsync(boss.HumanoidRootPart.Position, target.HumanoidRootPart.Position)
		local wps = path:GetWaypoints()
		if wps[2] then
			boss.Humanoid:MoveTo(wps[2].Position)
		end
	end
end)
