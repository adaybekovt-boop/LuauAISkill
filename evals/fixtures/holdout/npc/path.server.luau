local PathfindingService = game:GetService("PathfindingService")
local function walk(npc, goal)
    local path = PathfindingService:CreatePath()
    path:ComputeAsync(npc.PrimaryPart.Position, goal)
    for _, point in path:GetWaypoints() do
        npc.Humanoid:MoveTo(point.Position)
    end
end
return walk
