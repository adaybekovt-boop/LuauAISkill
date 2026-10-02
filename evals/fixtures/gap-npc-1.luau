RunService.Heartbeat:Connect(function()
	local path = PathfindingService:CreatePath()
	path:ComputeAsync(npc.PrimaryPart.Position, target.Position)
end)
