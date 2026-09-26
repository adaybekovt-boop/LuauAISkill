-- BAD: intentionally broken eval fixture (do not copy). One copy of this Script is inside each of 80 zombies.
local PathfindingService = game:GetService("PathfindingService")
local npc = script.Parent
local humanoid = npc:WaitForChild("Humanoid")

while true do
	wait()
	local target = nil
	local closest = math.huge
	for _, player in pairs(game.Players:GetPlayers()) do
		local char = player.Character
		if char and (char.HumanoidRootPart.Position - npc.HumanoidRootPart.Position).Magnitude < closest then
			closest = (char.HumanoidRootPart.Position - npc.HumanoidRootPart.Position).Magnitude
			target = char
		end
	end
	if target then
		local path = PathfindingService:CreatePath()
		path:ComputeAsync(npc.HumanoidRootPart.Position, target.HumanoidRootPart.Position)
		for _, wp in pairs(path:GetWaypoints()) do
			humanoid:MoveTo(wp.Position)
			humanoid.MoveToFinished:Wait()
		end
	end
end
