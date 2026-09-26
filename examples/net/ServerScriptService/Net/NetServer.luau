--!strict
-- NetServer: declare each remote once with a rate limit and a parser; handlers only ever see parsed, typed data.
-- Not a framework — ~120 lines you can read in one go. Order per message: rate limit → parse → handler.
-- Rejections are silent to the client (no oracle for exploiters) but counted for monitoring.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)

export type Limit = TokenBucket.Limit
export type Spec<T> = {
	limit: Limit, -- per player: burst `capacity`, sustained `rate` per second
	parse: (...unknown) -> T?, -- validate + convert raw args; nil = reject
}
type Counters = { accepted: number, limited: number, invalid: number }

local NetServer = {}

-- Called when a player keeps sending garbage (default: log). Don't auto-kick on rate limits alone:
-- lag spikes deliver bursts of legitimate messages.
NetServer.onAbuse = function(player: Player, remote: string, invalidPerMinute: number)
	warn(`[Net] {player.Name} ({player.UserId}) sent {invalidPerMinute} invalid {remote} messages in a minute`)
end
NetServer.ABUSE_THRESHOLD = 30

local folder: Folder? = nil
local counters: { [string]: Counters } = {}
local invalidByPlayer: { [Player]: number } = {}
local forgetters: { (Player) -> () } = {}

local function getFolder(): Folder
	if folder then
		return folder
	end
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	local f = if existing and existing:IsA("Folder") then existing else Instance.new("Folder")
	f.Name = "Remotes"
	f.Parent = ReplicatedStorage
	folder = f
	return f
end

-- RemoteEvent and UnreliableRemoteEvent share an API but no scriptable base type; create either as Instance.
local function newEvent(name: string, unreliable: boolean?): Instance
	local remote = Instance.new(if unreliable then "UnreliableRemoteEvent" else "RemoteEvent")
	remote.Name = name
	remote.Parent = getFolder()
	return remote
end

local function track(name: string, limit: Limit): (Player) -> "ok" | "limited"
	assert(counters[name] == nil, "remote declared twice: " .. name)
	counters[name] = { accepted = 0, limited = 0, invalid = 0 }
	local limiter = TokenBucket.new({ [name] = limit })
	table.insert(forgetters, function(player: Player)
		limiter:forget(player)
	end)
	return function(player: Player)
		if limiter:allow(player, name, os.clock()) then
			return "ok"
		end
		counters[name].limited += 1
		return "limited"
	end
end

local function invalid(player: Player, name: string)
	counters[name].invalid += 1
	local n = (invalidByPlayer[player] or 0) + 1
	invalidByPlayer[player] = n
	if n == NetServer.ABUSE_THRESHOLD then
		NetServer.onAbuse(player, name, n)
	end
end

-- Client → server event. `unreliable = true` for continuous cosmetic data (≤ 1000 bytes, may drop/reorder).
function NetServer.event<T>(name: string, spec: Spec<T>, handler: (Player, T) -> (), unreliable: boolean?): Instance
	local remote = newEvent(name, unreliable)
	local gate = track(name, spec.limit)
	local signal = (remote :: any).OnServerEvent :: RBXScriptSignal
	signal:Connect(function(player: Player, ...: unknown)
		if gate(player) ~= "ok" then
			return
		end
		local parsed = spec.parse(...)
		if parsed == nil then
			invalid(player, name)
			return
		end
		counters[name].accepted += 1
		handler(player, parsed)
	end)
	return remote
end

-- Client → server request/response. The handler must not yield for long (the client waits); returning nil tells
-- the client "rejected/failed" — clients must handle nil and time out their UI.
function NetServer.request<T>(name: string, spec: Spec<T>, handler: (Player, T) -> any): RemoteFunction
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = getFolder()
	local gate = track(name, spec.limit)
	remote.OnServerInvoke = function(player: Player, ...: unknown): any
		if gate(player) ~= "ok" then
			return nil
		end
		local parsed = spec.parse(...)
		if parsed == nil then
			invalid(player, name)
			return nil
		end
		counters[name].accepted += 1
		return handler(player, parsed)
	end
	return remote
end

-- Server → client remote (no limiter needed; the server is trusted). Declared here so all remotes live in one folder.
function NetServer.broadcast(name: string, unreliable: boolean?): Instance
	return newEvent(name, unreliable)
end

function NetServer.stats(): { [string]: Counters }
	return table.clone(counters)
end

Players.PlayerRemoving:Connect(function(player: Player)
	invalidByPlayer[player] = nil
	for _, forget in forgetters do
		forget(player)
	end
end)

-- Abuse counters are per minute.
task.spawn(function()
	while true do
		task.wait(60)
		table.clear(invalidByPlayer)
	end
end)

return NetServer
