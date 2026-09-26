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
