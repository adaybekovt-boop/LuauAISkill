--!strict
-- NetClient: find server-created remotes (with timeouts) and throttle sends locally so normal play never hits the
-- server's limits. Client throttling is UX only — the server enforces the real limits.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)

local NetClient = {}
local TIMEOUT = 15

local function folder(): Instance
	local f = ReplicatedStorage:WaitForChild("Remotes", TIMEOUT)
	assert(f, "ReplicatedStorage.Remotes not found (server scripts not running?)")
	return f
end

function NetClient.remote(name: string): Instance
	local r = folder():WaitForChild(name, TIMEOUT)
	assert(r, "remote not found: " .. name)
	return r
end

-- Returns fire(...) that sends at most `limit` (burst/rate) and silently drops the excess.
-- For continuous data (aim, look) drop is correct: the next update supersedes it.
function NetClient.sender(name: string, limit: TokenBucket.Limit): (...any) -> boolean
	local remote = NetClient.remote(name)
	local bucket = TokenBucket.new({ send = limit })
	return function(...: any): boolean
		if not bucket:allow("self", "send", os.clock()) then
			return false
		end
		if remote:IsA("RemoteEvent") then
			remote:FireServer(...)
		elseif remote:IsA("UnreliableRemoteEvent") then
			remote:FireServer(...)
		end
		return true
	end
end

-- InvokeServer with a client-side timeout: resolves to nil if the server doesn't answer in `timeout` seconds.
function NetClient.request(name: string, timeout: number, ...: any): any
	local remote = NetClient.remote(name) :: RemoteFunction
	local result: any = nil
	local done = false
	local args = table.pack(...)
	local thread = coroutine.running()
	task.spawn(function()
		local ok, value = pcall(remote.InvokeServer, remote, table.unpack(args, 1, args.n))
		if not done then
			done = true
			result = if ok then value else nil
			task.spawn(thread)
		end
	end)
	task.delay(timeout, function()
		if not done then
			done = true
			task.spawn(thread)
		end
	end)
	coroutine.yield()
	return result
end

return NetClient
