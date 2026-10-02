--!strict
-- Primitive-only, disposable fixtures. Never insert assets or execute production-place scripts.
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Fixtures = {}
function Fixtures.part(name: string, position: Vector3, size: Vector3, parent: Instance?): Part
	local part = Instance.new("Part")
	part.Name, part.Position, part.Size = name, position, size
	part.Anchored = true
	part.Parent = parent or Workspace
	return part
end

function Fixtures.prepare(caseId: string)
	Fixtures.part("ReleaseSmokeFloor", Vector3.new(0, -1, 0), Vector3.new(600, 2, 600))
	local spawn = Instance.new("SpawnLocation")
	spawn.Name, spawn.Anchored, spawn.Duration = "ReleaseSmokeSpawn", true, 0
	spawn.Position = Vector3.new(0, 1, 30)
	spawn.Parent = Workspace
	if caseId == "lighting-presets" then
		Fixtures.part("SmokeBackWall", Vector3.new(0, 8, -30), Vector3.new(60, 16, 2))
		Fixtures.part("SmokeLeftWall", Vector3.new(-30, 8, 0), Vector3.new(2, 16, 60))
		for i = -1, 1 do
			local lamp = Fixtures.part("SmokeLamp" .. tostring(i), Vector3.new(i * 15, 10, -10), Vector3.new(2, 1, 2))
			lamp.Material = Enum.Material.Neon
			local light = Instance.new("PointLight")
			light.Brightness, light.Range, light.Shadows = 2, 22, true
			light.Color, light.Parent = Color3.fromRGB(255, 224, 190), lamp
			Fixtures.part("SmokeBlock" .. tostring(i), Vector3.new(i * 14, 3, -15), Vector3.new(5, 6, 5))
		end
	end
	if caseId == "round-manager" then
		local maps = Instance.new("Folder")
		maps.Name, maps.Parent = "Maps", ServerStorage
		local map = Instance.new("Model")
		map.Name, map.Parent = "SmokeMap", maps
		local point = Instance.new("SpawnLocation")
		point.Name, point.Anchored, point.Duration = "RoundSpawn", true, 0
		point.Position, point.Parent = Vector3.new(40, 1, 0), map
	end
	local scripts = ServerStorage:FindFirstChild("SmokeScripts")
	if scripts then
		for _, source in scripts:GetChildren() do
			assert(source:IsA("Script"), "SmokeScripts contains a non-Script")
			local copy = source:Clone() :: Script
			copy.Enabled = true
			copy.Parent = ServerScriptService
		end
	end
end

return Fixtures
