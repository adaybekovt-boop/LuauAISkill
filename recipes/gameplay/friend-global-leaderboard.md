# Cached friend and global leaderboards

An eventually consistent best-score index with a single global cache, per-player friend caches, explicit stale /
partial states, coalesced writes, and a working two-tab client display.

Evidence: **TYPECHECKED** (strict, old + new solver, pinned Roblox definitions); pure logic **CLI-EXECUTED**.
**Studio / live: NOT RUN.**

## Architecture
- Trusted server score producers call `Service.recordBest` only after the canonical profile save succeeds.
  `UpdateAsync(max(old, score))` makes duplicate, reordered, and concurrent index writes safe for a monotonic best score.
- This OrderedDataStore is an index, never authority for rewards or profile recovery. Friends use the documented
  `GetFriendsWhoPlayedAsync` IDs and `BatchGetAsync` on the ordered store only.
- One global cache is shared for all players; friend cache entries live only for connected players. Sixty-second
  cache/backoff, one in-flight fetch per cache, per-player three-second request limit, and explicit budget headroom
  prevent a refresh button from becoming an unbounded DataStore worker.
- Batch keys are sorted/deduped: self plus at most 99 friends. Each key costs one ordered read. Missing values are
  omitted. Ties sort by ascending UserId for reproducibility; global boundary ties are limited by the fetched page.
- Failed reads preserve last good data with `stale=true`; a restricted friend subset sets `partial=true` in the UI.
  The UI uses UserIds to avoid per-row name-fetch storms and refreshes every 65 seconds.

## When NOT to use

not a spendable-currency ranking, decrementable seasonal rank, or full ranking of more than
99 friends. A mutable score needs an explicit canonical revision scheme, not a max reducer. Do not use the global
board for exact transactional eligibility or claiming a user's exact rank outside the fetched top page.

## Setup and integration
Copy `examples/leaderboard` by service folder. In a dedicated test universe, enable Studio API access if needed;
these calls access real DataStores. Wire your existing score service to `Service.recordBest(userId, canonicalScore)`
after a durable save, and on every successful profile load so failed index updates can be repaired next session.
The accepted score domain is integer 0–2,147,483,647. Populate a few test scores from trusted server code; clients
cannot submit a score, datastore key, page size, or arbitrary friend ID. The display intentionally shows user IDs.

## Implementation

### `examples/leaderboard/ServerScriptService/Boards/Rows.luau`

<!-- code: examples/leaderboard/ServerScriptService/Boards/Rows.luau -->
```luau
-- file: examples/leaderboard/ServerScriptService/Boards/Rows.luau
--!strict
export type Row = { userId: number, score: number }
local Rows = {}
function Rows.valid(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= 2147483647 and value % 1 == 0
end
function Rows.sorted(entries: { [string]: any }, limit: number): { Row }
	local rows: { Row } = {}
	for key, entry in entries do
		local id = tonumber(key)
		if id and id > 0 and id % 1 == 0 and type(entry) == "table" and Rows.valid(entry.value) then
			table.insert(rows, { userId = id, score = entry.value })
		end
	end
	table.sort(rows, function(a: Row, b: Row) return a.score > b.score or (a.score == b.score and a.userId < b.userId) end)
	while #rows > limit do table.remove(rows) end
	return rows
end
function Rows.keys(userId: number, friends: { number }): ({ string }, boolean)
	local ids: { number } = {}
	local seen: { [number]: boolean } = { [userId] = true }
	for _, id in friends do
		if id > 0 and id % 1 == 0 and id == id and not seen[id] then
			seen[id] = true; table.insert(ids, id)
		end
	end
	table.sort(ids)
	local keys = { tostring(userId) }
	for i = 1, math.min(99, #ids) do table.insert(keys, tostring(ids[i])) end
	return keys, #ids > 99
end
return Rows
```
<!-- /code -->

### `examples/leaderboard/ServerScriptService/Boards/Service.luau`

<!-- code: examples/leaderboard/ServerScriptService/Boards/Service.luau -->
```luau
-- file: examples/leaderboard/ServerScriptService/Boards/Service.luau
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
```
<!-- /code -->

### `examples/leaderboard/ServerScriptService/LeaderboardServer.server.luau`

<!-- code: examples/leaderboard/ServerScriptService/LeaderboardServer.server.luau -->
```luau
-- file: examples/leaderboard/ServerScriptService/LeaderboardServer.server.luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Service = require(script.Parent.Boards.Service)
local remote = Instance.new("RemoteEvent")
remote.Name = "LeaderboardQuery"
remote.Parent = ReplicatedStorage
local nextRequest: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
remote.OnServerEvent:Connect(function(player: Player, mode: any)
	if (mode ~= "global" and mode ~= "friends") or busy[player] or os.clock() < (nextRequest[player] or 0) then return end
	nextRequest[player] = os.clock() + 3
	busy[player] = true
	local snapshot = Service.get(player, mode)
	busy[player] = nil
	if player.Parent == Players then remote:FireClient(player, mode, snapshot) end
end)
Players.PlayerRemoving:Connect(function(player) nextRequest[player], busy[player] = nil, nil end)
-- Trusted score producers call Service.recordBest(userId, score) AFTER their canonical save succeeds.
```
<!-- /code -->

### `examples/leaderboard/StarterPlayer/StarterPlayerScripts/LeaderboardClient.client.luau`

<!-- code: examples/leaderboard/StarterPlayer/StarterPlayerScripts/LeaderboardClient.client.luau -->
```luau
-- file: examples/leaderboard/StarterPlayer/StarterPlayerScripts/LeaderboardClient.client.luau
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("LeaderboardQuery", 20) :: RemoteEvent?
if not remote then return end
local player = Players.LocalPlayer :: Player
local gui = Instance.new("ScreenGui")
gui.Name = "Leaderboard"; gui.ResetOnSpawn = false
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(280, 440); frame.Position = UDim2.fromOffset(16, 80); frame.Parent = gui
local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 1, -40); label.Position = UDim2.fromOffset(0, 40)
label.TextSize = 16; label.TextYAlignment = Enum.TextYAlignment.Top
label.RichText = false; label.AutoLocalize = false; label.Text = "Loading scores…"; label.Parent = frame
local current = "global"
local running = true
for index, mode in { "global", "friends" } do
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0.5, 0, 0, 36); button.Position = UDim2.new((index - 1) * 0.5, 0, 0, 0)
	button.Text = mode; button.Parent = frame
	button.Activated:Connect(function() current = mode; remote:FireServer(mode) end)
end
gui.Parent = player:WaitForChild("PlayerGui")
local response = remote.OnClientEvent:Connect(function(mode: string, snapshot: any)
	if mode ~= current then return end
	local lines = { if snapshot.stale then "Scores unavailable / cached" else "Best scores" }
	if snapshot.partial then table.insert(lines, "Limited to first 99 friend IDs + you") end
	for rank, row in snapshot.rows do table.insert(lines, `{rank}. User {row.userId}: {row.score}`) end
	if #snapshot.rows == 0 then table.insert(lines, "No recorded scores") end
	label.Text = table.concat(lines, "\n")
end)
remote:FireServer(current)
task.spawn(function()
	while running do
		task.wait(65)
		if running then remote:FireServer(current) end
	end
end)
script.Destroying:Connect(function() running = false; response:Disconnect(); gui:Destroy() end)
-- User IDs avoid per-row username API bursts. Add a bounded name cache if your UI needs names.
```
<!-- /code -->

## How to test

| Scenario | Required observation |
|---|---|
| CLI ties/malformed values | Stable tie ordering; NaN/infinity/noninteger/negative entries omitted |
| Server & Clients global refresh flood | At most one shared fetch per TTL; no score-writing remote |
| Friends empty / duplicate / >99 | Self retained once; no zero-key batch; partial flag visible when capped |
| Budget exhaustion or API failure | Last good rows retained as stale; no repeated immediate retry |
| Concurrent increasing best-score writes | Highest score survives; old request cannot reduce the index |
| Player leaves during friend fetch | No response to departed player; no persistent per-player cache retention |
| Offline index failure then rejoin | Canonical best score is republished by your integration hook |

Friends APIs need real account relationships and played history; simulated Studio clients cannot establish that
coverage. Report those checks separately as LIVE TESTED only if actually performed.

## Failure paths and limits
At most 200 leaderboard clients does not imply enough budget for every 100-key friend batch. The budget check
fails closed and serves stale data; it does not promise full friend coverage. Cache on demand rather than doing an
N-friend refresh for every join. Ordered writes are coalesced once a minute and on shutdown, but shutdown cannot
guarantee every index write; canonical-on-load repair is mandatory. A production large-server integration should
share its global DataStore budget manager with this service. Store migrations and friend pagination are deliberate
extensions, not silently supported capabilities.

## Verification
From the skill directory, run `python tools/check_all.py`. Pure tests for this recipe:
`luau examples/tests/leaderboard.spec.luau`. The checker runs both Luau solvers. Engine coverage remains NOT RUN until you retain
assertion output from the specified Studio scenario with Studio build, place revision, peers, and device.

Sources: cd:players/leaderboards, cd:reference/engine/classes/OrderedDataStore, cd:reference/engine/classes/GlobalDataStore, cd:reference/engine/classes/Player, api:GlobalDataStore.BatchGetAsync, api:Player.GetFriendsWhoPlayedAsync.
