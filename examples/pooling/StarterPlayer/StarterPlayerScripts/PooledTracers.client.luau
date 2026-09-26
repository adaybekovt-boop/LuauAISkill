--!strict
-- Usage example: bullet tracers from a pool (drop-in for the tracer() function in the hitscan recipe's client).
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PartPool = require(ReplicatedStorage.Pooling.PartPool)

local fx = Instance.new("Folder")
fx.Name = "PooledFx"
fx.Parent = Workspace

local template = Instance.new("Part")
template.Material = Enum.Material.Neon
template.Color = Color3.fromRGB(255, 225, 160)
template.CastShadow = false
template.Size = Vector3.new(0.06, 0.06, 1)

local tracers = PartPool.new(template, 32, fx, 256)

local function tracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local p = tracers:get(CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2))
	p.Size = Vector3.new(0.06, 0.06, length)
	tracers:releaseAfter(p, 0.05)
end

-- Demo: a burst of tracers in front of the camera once the game has loaded.
task.wait(5)
local camera = Workspace.CurrentCamera
if camera then
	for _ = 1, 50 do
		local origin = camera.CFrame.Position
		tracer(origin, origin + camera.CFrame.LookVector * 100 + Vector3.new(math.random() * 4 - 2, math.random() * 4 - 2, 0))
		task.wait(0.03)
	end
end
print("tracer pool (free, in use):", tracers:size())
