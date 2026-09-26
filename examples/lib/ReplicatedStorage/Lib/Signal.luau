--!strict
-- Signal: minimal typed pure-Luau event (same side only). Handlers run synchronously in connect order;
-- a handler error is reported with warn and doesn't stop other handlers. Use RemoteEvents to cross sides.
-- Status: TYPECHECKED + CLI-EXECUTED.

export type Connection = { connected: boolean, disconnect: (self: Connection) -> () }
export type Signal<T...> = {
	connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	fire: (self: Signal<T...>, T...) -> (),
	destroy: (self: Signal<T...>) -> (),
}

-- `warn` is a Roblox global; fall back to print so the module also runs under the plain Luau CLI.
local report: (...any) -> () = (warn :: any) or print

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { { fn: (T...) -> (), conn: Connection } } = {}
	local signal = {}

	function signal.connect(_self: Signal<T...>, fn: (T...) -> ()): Connection
		local conn = { connected = true } :: any
		function conn.disconnect(c: Connection)
			if not c.connected then
				return
			end
			c.connected = false
			for i, h in handlers do
				if h.conn == c then
					table.remove(handlers, i)
					break
				end
			end
		end
		table.insert(handlers, { fn = fn, conn = conn })
		return conn
	end

	function signal.once(self: Signal<T...>, fn: (T...) -> ()): Connection
		local conn: Connection
		conn = self:connect(function(...: T...)
			conn:disconnect()
			fn(...)
		end)
		return conn
	end

	function signal.fire(_self: Signal<T...>, ...: T...)
		local snapshot = table.clone(handlers) -- handlers may (dis)connect during fire
		for _, h in snapshot do
			if h.conn.connected then
				xpcall(h.fn, function(err: any)
					report("[Signal] handler error:", err)
				end, ...)
			end
		end
	end

	function signal.destroy(_self: Signal<T...>)
		for _, h in handlers do
			h.conn.connected = false
		end
		table.clear(handlers)
	end

	return signal :: any
end

return Signal
