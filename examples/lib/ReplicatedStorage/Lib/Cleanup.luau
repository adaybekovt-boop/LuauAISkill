--!strict
-- Cleanup: owns connections, instances, threads and callbacks for one lifetime (character, UI screen, round...).
-- clean() runs tasks in reverse order (LIFO), is re-entrancy safe, and keeps going if one task errors.
-- Host: shared (pure Luau + Roblox types). Status: TYPECHECKED (luau-lsp, Roblox defs). Not run in Studio.

export type Task = RBXScriptConnection | Instance | thread | () -> () | { destroy: (any) -> () }

export type Cleanup = {
	add: <T>(self: Cleanup, task: T) -> T,
	connect: (self: Cleanup, signal: RBXScriptSignal, fn: (...any) -> ()) -> RBXScriptConnection,
	clean: (self: Cleanup) -> (),
	destroy: (self: Cleanup) -> (),
	isCleaning: (self: Cleanup) -> boolean,
}

type Internal = Cleanup & { _tasks: { any }, _cleaning: boolean }

-- `warn` is a Roblox global; fall back to print so the module also runs under the plain Luau CLI.
local report: (...any) -> () = (warn :: any) or print

local Cleanup = {}
Cleanup.__index = Cleanup

local function run(t: any)
	local kind = typeof(t)
	if kind == "RBXScriptConnection" then
		t:Disconnect()
	elseif kind == "Instance" then
		t:Destroy()
	elseif kind == "thread" then
		if coroutine.status(t) ~= "dead" then
			task.cancel(t)
		end
	elseif kind == "function" then
		t()
	elseif kind == "table" then
		local obj = t :: { destroy: ((any) -> ())? }
		if obj.destroy then
			obj.destroy(obj)
		end
	end
end

function Cleanup.new(): Cleanup
	local self = setmetatable({ _tasks = {}, _cleaning = false }, Cleanup)
	return (self :: any) :: Cleanup
end

function Cleanup.add<T>(self: Cleanup, t: T): T
	local s = self :: Internal
	if s._cleaning then
		run(t) -- added during cleanup: release immediately instead of leaking
	else
		table.insert(s._tasks, t)
	end
	return t
end

function Cleanup.connect(self: Cleanup, signal: RBXScriptSignal, fn: (...any) -> ()): RBXScriptConnection
	return self:add(signal:Connect(fn))
end

function Cleanup.clean(self: Cleanup)
	local s = self :: Internal
	if s._cleaning then
		return
	end
	s._cleaning = true
	local tasks = s._tasks
	while #tasks > 0 do
		local t = table.remove(tasks)
		xpcall(run, function(err: any)
			report("[Cleanup] task failed:", err, debug.traceback())
		end, t)
	end
	s._cleaning = false
end

Cleanup.destroy = Cleanup.clean

function Cleanup.isCleaning(self: Cleanup): boolean
	return (self :: Internal)._cleaning
end

return Cleanup
