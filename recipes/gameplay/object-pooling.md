# Recipe: object pooling for high-frequency effects (and when not to pool)

Evidence: TYPECHECKED · **not run in Studio** — pooling is a performance change: measure before/after in the
MicroProfiler on your target device. Chapter: [performance](../../handbook/roblox/08-performance.md).

## When pooling helps (and when it doesn't)
| Situation | Pool? | Why |
|---|---|---|
| Client tracers/shells/sparks at 10+ per second | yes | avoids constant Instance creation, GC and ancestry work |
| Client UI list rows that scroll (1000 items) | yes (virtualized list) | only ~20 rows exist; rebind data |
| Server bullets as parts | no — don't use parts | simulate data on the server, render on clients ([projectile](projectile-weapon.md)) |
| A few effects per minute | no | complexity for nothing |
| NPC models that respawn | sometimes | reuse avoids re-creating Humanoids; reset state carefully |
Measure first: `Instance.new` + `Destroy` of simple parts is cheap in small numbers; the win appears with bursts.

## Architecture
```text
PartPool.new(template, prewarm, parent, maxSize)
  get(cframe)       free stack → part (or clone a new one) → place it
  release(part)     mark for parking (no immediate work)
  releaseAfter(part, t)
  PostSimulation    ONE Workspace:BulkMoveTo(parked parts → far below, FireCFrameChanged) per frame
Parked parts stay parented and Anchored with CanQuery/CanTouch off → no ancestry churn, no physics or query cost.
```

## Code
<!-- code: examples/pooling/ReplicatedStorage/Pooling/PartPool.luau -->
```luau
-- file: examples/pooling/ReplicatedStorage/Pooling/PartPool.luau
--!strict
-- PartPool: reuse BaseParts instead of Instance.new/Destroy for high-frequency effects (tracers, shells, debris,
-- hit sparks). Parked parts stay parented (no ancestry churn) and are moved far away in ONE BulkMoveTo per frame.
-- Use on the client for cosmetics. On the server, pooled parts still replicate every move — prefer data + client
-- rendering there (see the projectile recipe).
-- Status: TYPECHECKED. Not run in Studio (measure the gain in your case with the MicroProfiler).
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PARK = CFrame.new(0, -10000, 0) -- below the world; parts are Anchored and CanQuery/CanTouch off

export type PartPool = {
	get: (self: PartPool, cframe: CFrame) -> BasePart,
	release: (self: PartPool, part: BasePart) -> (),
	releaseAfter: (self: PartPool, part: BasePart, seconds: number) -> (),
	destroy: (self: PartPool) -> (),
	size: (self: PartPool) -> (number, number), -- (free, in use)
}

local PartPool = {}

function PartPool.new(template: BasePart, prewarm: number, parent: Instance, maxSize: number?): PartPool
	local free: { BasePart } = {}
	local inUse: { [BasePart]: true } = {}
	local toPark: { BasePart } = {}
	local cap = maxSize or 500
	local total = 0

	local function make(): BasePart
		local p = template:Clone()
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = PARK
		p.Parent = parent
		total += 1
		return p
	end
	for _ = 1, prewarm do
		table.insert(free, make())
	end

	-- Park everything released this frame with a single BulkMoveTo (cheaper than N CFrame writes).
	local conn = RunService.PostSimulation:Connect(function()
		if #toPark == 0 then
			return
		end
		local cframes = table.create(#toPark, PARK)
		Workspace:BulkMoveTo(toPark, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		for _, p in toPark do
			table.insert(free, p)
		end
		table.clear(toPark)
	end)

	local pool = {}
	function pool.get(_self: PartPool, cframe: CFrame): BasePart
		local p: BasePart = table.remove(free) or make() -- grows on demand
		if total == cap + 1 then
			warn("[PartPool] exceeded", cap, "parts — release parts or raise maxSize") -- warns once, keeps working
		end
		inUse[p] = true
		p.CFrame = cframe
		return p
	end
	function pool.release(_self: PartPool, p: BasePart)
		if inUse[p] then
			inUse[p] = nil
			table.insert(toPark, p)
		end
	end
	function pool.releaseAfter(self: PartPool, p: BasePart, seconds: number)
		task.delay(seconds, self.release, self, p)
	end
	function pool.destroy(_self: PartPool)
		conn:Disconnect()
		for _, p in free do
			p:Destroy()
		end
		for p in inUse do
			p:Destroy()
		end
		for _, p in toPark do
			p:Destroy()
		end
		table.clear(free)
		table.clear(inUse)
		table.clear(toPark)
	end
	function pool.size(_self: PartPool): (number, number)
		local n = 0
		for _ in inUse do
			n += 1
		end
		return #free, n
	end
	return pool :: any
end

return PartPool
```
<!-- /code -->

<!-- code: examples/pooling/StarterPlayer/StarterPlayerScripts/PooledTracers.client.luau -->
```luau
-- file: examples/pooling/StarterPlayer/StarterPlayerScripts/PooledTracers.client.luau
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
```
<!-- /code -->

## Pitfalls
- Reset every property you change on a pooled object (size, color, transparency, attributes) on `get`.
- Don't pool instances you hand to other systems that may destroy them.
- Pools hold memory: cap them (`maxSize`) and destroy on scene change.
- Particle bursts: prefer one `ParticleEmitter` moved to the hit point + `Emit(n)` over pooling emitters.

## How to measure
MicroProfiler (Ctrl+F6) → record while firing continuously; compare frame time and the `GC` / script scopes with
and without the pool; Developer Console → Memory → `Instances` count should stay flat with the pool.

Sources: cd:performance-optimization/improve, cd:performance-optimization/microprofiler/use-microprofiler,
cd:reference/engine/classes/WorldRoot, cd:reference/engine/classes/ParticleEmitter.
