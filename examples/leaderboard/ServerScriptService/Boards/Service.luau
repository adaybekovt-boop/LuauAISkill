--!strict
-- Ordered store is a BEST-score index; authoritative rewards/profile writes happen elsewhere.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Rows = require(script.Parent.Rows)
local store = DataStoreService:GetOrderedDataStore("BestScore_v1")
export type Snapshot = { rows: { Rows.Row }, stale: boolean, partial: boolean, updatedAt: number }
type Cache = { snapshot: Snapshot, expires: number, busy: boolean }
local function empty(): Cache
	return { snapshot = { rows = {}, stale = true, partial = false, updatedAt = 0 }, expires = 0, busy = false }
end
local global = empty()
local friends: { [Player]: Cache } = {}
local pending: { [number]: number } = {}
local Service = {}
function Service.recordBest(userId: number, canonicalScore: number)
	assert(userId > 0 and userId % 1 == 0 and Rows.valid(canonicalScore), "Invalid server score")
	pending[userId] = math.max(pending[userId] or 0, canonicalScore)
end
function Service.get(player: Player, mode: string): Snapshot
	local cache = global
	if mode == "friends" then
		cache = friends[player] or empty()
		friends[player] = cache
	end
	if cache.busy or os.clock() < cache.expires then return cache.snapshot end
	cache.busy = true
	cache.expires = os.clock() + 60 -- rate/backoff also applies to failures
	local ok, rows, partial = pcall(function(): ({ Rows.Row }, boolean)
		if mode == "friends" then
			local ids = player:GetFriendsWhoPlayedAsync()
			local keys, limited = Rows.keys(player.UserId, ids)
			if DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedRead) < #keys + 5 then
				error("Read budget reserved for gameplay")
			end
			return Rows.sorted(store:BatchGetAsync(keys), 20), limited
		end
		if DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedList) < 2 then
			error("List budget exhausted")
		end
		local page = store:GetSortedAsync(false, 20):GetCurrentPage()
		local entries: { [string]: any } = {}
		for _, row in page do entries[row.key] = { value = row.value } end
		return Rows.sorted(entries, 20), false
	end)
	cache.busy = false
	if ok then
		cache.snapshot = { rows = rows, stale = false, partial = partial, updatedAt = os.time() }
	else
		cache.snapshot.stale = true -- preserve last good data; failure is not an empty board
	end
	return cache.snapshot
end
local running = true
local connection = Players.PlayerRemoving:Connect(function(player) friends[player] = nil end)
local function flush()
	local budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedWrite)
	for userId, score in pending do
		if budget < 3 then break end
		budget -= 1
		local ok, saved = pcall(function()
			return store:UpdateAsync(tostring(userId), function(old: any): any
				if old ~= nil and not Rows.valid(old) then return nil end
				return math.max(if type(old) == "number" then old else 0, score)
			end)
		end)
		if ok and type(saved) == "number" and saved >= score and pending[userId] == score then pending[userId] = nil end
	end
end
task.spawn(function()
	while running do task.wait(60); if running then flush() end end
end)
game:BindToClose(function() running = false; connection:Disconnect(); flush() end)
return Service
