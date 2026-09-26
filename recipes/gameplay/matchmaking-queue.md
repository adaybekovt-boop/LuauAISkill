# Recipe: matchmaking queue (lobby → reserved match servers with MemoryStore)

Evidence: match forming CLI-EXECUTED (`examples/tests/rounds.spec.luau`) · lobby/match server TYPECHECKED ·
**not run live** (MemoryStore, MessagingService and teleports need a published experience; teleports never work in
Studio playtests). Side: server. Chapter: [cross-server](../../handbook/roblox/07-cross-server.md).

## First decide if you need it
Roblox's built-in join matchmaking (server selection, configurable with `MatchmakingService` server attributes and
Creator Dashboard scoring) may already cover "put similar players together". Build a queue like this only for
lobby-based games with fixed match sizes, ratings, or parties.

## Architecture
```text
Lobby server (every lobby):
  QueueRequest(true)  → sorted map MatchQueue_v1: key=userId, value={userIds, rating, joinedAt}, sortKey=joinedAt,
                         TTL 90 s, refreshed every 30 s while queued (crashed lobbies' entries expire)
  QueueRequest(false) / leave → RemoveAsync
  subscribe "MatchFound_v1": for my queued players in the message → TeleportAsync(place, players,
                         TeleportOptions{ReservedServerAccessCode})
Elected matchmaker (whichever lobby holds the hash-map lock, TTL 12 s, every 5 s):
  GetRangeAsync(Ascending, 100) → QueueLogic.form (oldest first, rating gap widens with wait, parties intact)
  per match: ReserveServerAsync → (code, privateServerId) → rosters[privateServerId] = userIds (TTL 15 min)
             → remove entries → PublishAsync("MatchFound_v1", {code, userIds})
Reserved match server (same place here): roster by game.PrivateServerId → kick anyone not on it
```
Why:
- **TTL + refresh** makes the queue self-healing: if a lobby server dies, its players' entries expire.
- **One matchmaker at a time** (lock with TTL) prevents two servers from matching the same players; if it dies, the
  lock expires and another lobby takes over.
- **Oldest-first with widening gap** keeps waits bounded without mismatching early.
- **Roster check** in the match server stops strays (and players who got a stale code).
- **Fail open on missing roster**: the reserved-server access code is secret; kicking everyone on a MemoryStore
  hiccup is worse than admitting a rare stray. Choose fail-closed for ranked games.

## Code
<!-- code: examples/rounds/ServerScriptService/Matchmaking/QueueLogic.luau -->
```luau
-- file: examples/rounds/ServerScriptService/Matchmaking/QueueLogic.luau
--!strict
-- Pure match forming (CLI-tested). Entries are grouped oldest-first; the allowed rating gap widens with waiting
-- time so nobody waits forever. Parties are kept together (an entry may represent several players).
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Entry = { key: string, userIds: { number }, rating: number, joinedAt: number }
export type Rules = { matchSize: number, baseGap: number, gapPerSecond: number, maxGap: number }

local QueueLogic = {}

function QueueLogic.allowedGap(rules: Rules, waited: number): number
	return math.min(rules.maxGap, rules.baseGap + rules.gapPerSecond * math.max(0, waited))
end

-- Returns a list of matches (each a list of entries whose player counts sum to matchSize) and leftovers.
function QueueLogic.form(entries: { Entry }, rules: Rules, now: number): ({ { Entry } }, { Entry })
	local pool = table.clone(entries)
	table.sort(pool, function(a: Entry, b: Entry)
		return a.joinedAt < b.joinedAt
	end)
	local used: { [Entry]: boolean } = {}
	local matches = {}
	for _, anchor in pool do
		if used[anchor] or #anchor.userIds > rules.matchSize then
			continue
		end
		local gap = QueueLogic.allowedGap(rules, now - anchor.joinedAt)
		local group, count = { anchor }, #anchor.userIds
		for _, other in pool do
			if count == rules.matchSize then
				break
			end
			if other ~= anchor and not used[other] and count + #other.userIds <= rules.matchSize
				and math.abs(other.rating - anchor.rating) <= gap then
				table.insert(group, other)
				count += #other.userIds
			end
		end
		if count == rules.matchSize then
			for _, e in group do
				used[e] = true
			end
			table.insert(matches, group)
		end
	end
	local leftovers = {}
	for _, e in pool do
		if not used[e] then
			table.insert(leftovers, e)
		end
	end
	return matches, leftovers
end

return table.freeze(QueueLogic)
```
<!-- /code -->

<!-- code: examples/rounds/ServerScriptService/Matchmaking/init.server.luau -->
```luau
-- file: examples/rounds/ServerScriptService/Matchmaking/init.server.luau
--!strict
-- Lobby → match matchmaking with MemoryStore + reserved servers. One script, two modes:
--   lobby server:    players queue (sorted map entry with TTL, refreshed while waiting); one elected server
--                    forms matches (QueueLogic), reserves a server, stores the roster, publishes "match found";
--                    every lobby teleports its own players with the access code
--   reserved server: loads its roster by PrivateServerId and kicks players who aren't on it
-- Teleporting into a reserved server of the SAME place keeps the example free of placeholder place ids; use your
-- match place's id for a multi-place game. Teleports don't work in Studio playtests (logged instead).
-- Status: TYPECHECKED (QueueLogic CLI-EXECUTED). Not run live — MemoryStore/Teleport need a published experience.
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
local Validate = require(ReplicatedStorage.Lib.Validate)
local QueueLogic = require(script.QueueLogic)

local MATCH_PLACE_ID = game.PlaceId
local RULES: QueueLogic.Rules = { matchSize = 4, baseGap = 100, gapPerSecond = 10, maxGap = 1000 }
local QUEUE_TTL = 90 -- seconds; entries refresh every 30 s while the player is still queued and present
local ROSTER_TTL = 15 * 60
local LOCK_TTL = 12
local PASS_INTERVAL = 5
local TOPIC = "MatchFound_v1"

local queue = MemoryStoreService:GetSortedMap("MatchQueue_v1")
local rosters = MemoryStoreService:GetHashMap("MatchRosters_v1")
local control = MemoryStoreService:GetHashMap("Matchmaker_v1")

local function isReservedMatchServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

---------------------------------------------------------------- match server mode
local function runMatchServer()
	local roster: { [number]: boolean }? = nil
	for attempt = 1, 5 do
		local ok, ids = pcall(rosters.GetAsync, rosters, game.PrivateServerId)
		if ok and type(ids) == "table" then
			local set = {}
			for _, id in ids :: { any } do
				if type(id) == "number" then
					set[id] = true
				end
			end
			roster = set
			break
		end
		task.wait(attempt)
	end
	if not roster then
		-- Fail open: the access code is secret, strays are rare; failing closed would kick the real players.
		warn("[Match] roster unavailable; admitting everyone")
		return
	end
	local function check(player: Player)
		if not (roster :: { [number]: boolean })[player.UserId] then
			player:Kick("You are not part of this match.")
		end
	end
	Players.PlayerAdded:Connect(check)
	for _, player in Players:GetPlayers() do
		check(player)
	end
end

---------------------------------------------------------------- lobby mode
local queued: { [Player]: number } = {} -- player → joinedAt (os.time, shared across servers)

local function queueKey(player: Player): string
	return tostring(player.UserId)
end

local function writeEntry(player: Player)
	local joinedAt = queued[player]
	if not joinedAt then
		return
	end
	local rating = player:GetAttribute("Rating")
	local value = { userIds = { player.UserId }, rating = if type(rating) == "number" then rating else 1000, joinedAt = joinedAt }
	local ok, err = pcall(queue.SetAsync, queue, queueKey(player), value, QUEUE_TTL, joinedAt)
	if not ok then
		warn("[Match] queue write failed:", err)
	end
end

local function leaveQueue(player: Player)
	if queued[player] then
		queued[player] = nil
		pcall(queue.RemoveAsync, queue, queueKey(player))
		player:SetAttribute("Queued", false)
	end
end

local function teleport(players: { Player }, code: string)
	if RunService:IsStudio() then
		print("[Match] would teleport", #players, "players (teleports don't work in Studio)")
		return
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, MATCH_PLACE_ID, players, options)
	if not ok then
		warn("[Match] teleport failed:", err) -- players stay in the lobby; they can queue again
	end
end

local function holdLock(): boolean
	local now = os.time()
	local ok, result = pcall(control.UpdateAsync, control, "lock", function(old: any): any
		if type(old) == "table" and old.jobId ~= game.JobId and (old.expires or 0) > now then
			return nil -- another server is the matchmaker
		end
		return { jobId = game.JobId, expires = now + LOCK_TTL }
	end, LOCK_TTL)
	return ok and type(result) == "table" and result.jobId == game.JobId
end

local function matchPass()
	local ok, items = pcall(queue.GetRangeAsync, queue, Enum.SortDirection.Ascending, 100)
	if not ok or type(items) ~= "table" then
		return
	end
	local entries: { QueueLogic.Entry } = {}
	for _, item in items :: { any } do
		local v = item.value
		if type(v) == "table" and type(v.userIds) == "table" and type(v.rating) == "number" and type(v.joinedAt) == "number" then
			table.insert(entries, { key = item.key, userIds = v.userIds, rating = v.rating, joinedAt = v.joinedAt })
		end
	end
	local matches = QueueLogic.form(entries, RULES, os.time())
	for _, group in matches do
		local reserved, code, privateServerId = pcall(TeleportService.ReserveServerAsync, TeleportService, MATCH_PLACE_ID)
		if not reserved then
			warn("[Match] ReserveServerAsync failed:", code)
			return -- try again next pass
		end
		local userIds = {}
		for _, e in group do
			for _, id in e.userIds do
				table.insert(userIds, id)
			end
		end
		pcall(rosters.SetAsync, rosters, privateServerId, userIds, ROSTER_TTL)
		for _, e in group do
			pcall(queue.RemoveAsync, queue, e.key)
		end
		local payload = HttpService:JSONEncode({ code = code, userIds = userIds }) -- well under the 1 KB limit
		local published, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, payload)
		if not published then
			warn("[Match] publish failed:", err)
		end
	end
end

local function runLobby()
	local folder = Instance.new("Folder")
	folder.Name = "MatchRemotes"
	local request = Instance.new("RemoteEvent")
	request.Name = "QueueRequest"
	request.Parent = folder
	folder.Parent = ReplicatedStorage
	local limiter = TokenBucket.new({ Queue = { capacity = 3, rate = 0.5 } })

	request.OnServerEvent:Connect(function(player: Player, want: unknown)
		local on = Validate.boolean(want)
		if on == nil or not limiter:allow(player, "Queue", os.clock()) then
			return
		end
		if on and not queued[player] then
			queued[player] = os.time()
			player:SetAttribute("Queued", true) -- public flag for UI
			writeEntry(player)
		elseif not on then
			leaveQueue(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		leaveQueue(player)
		limiter:forget(player)
	end)

	local subscribed, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message: any)
		local decoded = type(message.Data) == "string" and HttpService:JSONDecode(message.Data)
		if type(decoded) ~= "table" or type(decoded.code) ~= "string" or type(decoded.userIds) ~= "table" then
			return
		end
		local mine = {}
		for _, id in decoded.userIds do
			local player = type(id) == "number" and Players:GetPlayerByUserId(id)
			if player and queued[player] then
				queued[player] = nil
				player:SetAttribute("Queued", false)
				table.insert(mine, player)
			end
		end
		if #mine > 0 then
			teleport(mine, decoded.code)
		end
	end)
	if not subscribed then
		warn("[Match] subscribe failed:", err)
	end

	-- Refresh our players' entries (TTL) and run a matching pass if we are the elected matchmaker.
	local sinceRefresh = 0
	while true do
		task.wait(PASS_INTERVAL)
		sinceRefresh += PASS_INTERVAL
		if sinceRefresh >= 30 then
			sinceRefresh = 0
			for player in queued do
				task.spawn(writeEntry, player)
			end
		end
		if holdLock() then
			matchPass()
		end
	end
end

if isReservedMatchServer() then
	runMatchServer()
else
	runLobby()
end
```
<!-- /code -->

## Budget check (MemoryStore limits: 1000 + 120 × CCU request units/min)
Per queued player: 1 write per 30 s. Matchmaker: 1 lock update + 1 range read (≈ items read) per 5 s + a few
writes per match. At 500 CCU with 200 queued: ≈ 400 writes/min + ≈ 1,200 read units/min + lock ≈ 12/min — far
under ~61,000 units/min. Sorted maps live on one partition: at very high scale shard by region/mode
(`MatchQueue_v1_EU`, …).

## How to test
- CLI: match forming (similar ratings, party integrity, gap widening, oversized party).
- Published test experience, 2 lobby servers (Team Test / friends): queue 4 players across both servers → all four
  land in the same reserved server; a 5th player waits.
- Kill a lobby server with queued players (shutdown from dashboard) → entries vanish within 90 s.
- Manually join the reserved server with a wrong account (if you can get the code) → kicked.
- Watch MemoryStore usage in the Creator Dashboard observability page.

## Pitfalls
- `TeleportAsync` can fail (`TeleportInitFailed`): players must end up back in a usable state (here: stay in lobby,
  can requeue).
- Don't put secrets or trust decisions in `TeleportData` — the client can see and modify it; use MemoryStore/
  DataStore for anything that matters.
- MessagingService is best-effort (not guaranteed delivery): players whose lobby missed the message stay
  un-queued-but-waiting; add a timeout that re-queues them.

Sources: cd:cloud-services/memory-stores/index, cd:cloud-services/memory-stores/sorted-map,
cd:cloud-services/memory-stores/hash-map, cd:cloud-services/cross-server-messaging, cd:projects/teleport,
cd:reference/engine/classes/TeleportService, cd:reference/engine/classes/TeleportOptions, cd:matchmaking/index.
