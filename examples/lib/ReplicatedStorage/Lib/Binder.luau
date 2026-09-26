--!strict
-- Binder: run setup/cleanup per tagged Instance (CollectionService). Idempotent and streaming-safe:
-- instances can be removed (destroyed or streamed out) and re-added; each add gets a fresh Cleanup.
-- Host: server or client. Status: TYPECHECKED. Not run in Studio.

local CollectionService = game:GetService("CollectionService")
local Cleanup = require(script.Parent.Cleanup)

export type Binder = { destroy: (self: Binder) -> (), count: (self: Binder) -> number }

local Binder = {}

-- setup(instance, cleanup) attaches behaviour; register everything it creates in `cleanup`.
function Binder.bind(tag: string, setup: (Instance, Cleanup.Cleanup) -> ()): Binder
	local active: { [Instance]: Cleanup.Cleanup } = {}
	local root = Cleanup.new()

	local function add(inst: Instance)
		if active[inst] then
			return
		end
		local c = Cleanup.new()
		active[inst] = c
		local ok = xpcall(setup, function(err: any)
			warn(`[Binder:{tag}] setup failed for {inst:GetFullName()}: {err}`)
		end, inst, c)
		if not ok then
			c:clean()
			active[inst] = nil
		end
	end

	local function remove(inst: Instance)
		local c = active[inst]
		if c then
			active[inst] = nil
			c:clean()
		end
	end

	root:add(CollectionService:GetInstanceAddedSignal(tag):Connect(add))
	root:add(CollectionService:GetInstanceRemovedSignal(tag):Connect(remove))
	for _, inst in CollectionService:GetTagged(tag) do
		task.spawn(add, inst)
	end

	local binder = {}
	function binder.destroy(_self: Binder)
		root:clean()
		for inst in active do
			remove(inst)
		end
	end
	function binder.count(_self: Binder): number
		local n = 0
		for _ in active do
			n += 1
		end
		return n
	end
	return binder
end

return Binder
