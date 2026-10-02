# Recipe: save system (session-locked profiles, autosave, BindToClose, migrations, purchases)

Evidence: lock transforms + migrations TYPECHECKED + CLI-EXECUTED (`examples/tests/data.spec.luau`, 9 tests with a
fake store that reproduces the UpdateAsync contract) · service TYPECHECKED · **not run against real DataStores**.
Side: server only. Chapter: [data persistence](../../handbook/roblox/06-data-persistence.md) (limits, rules).
Needs: `examples/lib` (Signal).

## When to use this vs a library
This is the minimum correct design, small enough to read. Community libraries (ProfileStore and similar) implement
the same ideas with more features; using one is a fine choice — verify it does session locking, never saves failed
loads, and handles BindToClose. Don't combine two profile systems on the same keys.

Freshness note (API 0.741, creator-docs 2026-10-01): the engine dump contains an engine-managed player data system —
`PlayerDataService`, `Player:GetData()` → `PlayerData:GetRecordAsync()` → `PlayerDataRecord` (undocumented; `GetValue`/`SetValue`,
`Loaded`, `Flushed`, `ReleaseAsync`) — but it is **undocumented** (no creator-docs pages, no announcement in the
pinned sources). Don't build on it yet; re-check with `python tools/api.py PlayerDataService` after
`python tools/fetch_sources.py --latest`. The module here is named `Profiles` to avoid colliding with the engine's
`PlayerData` class name.

## Architecture
```text
PlayerAdded → load: UpdateAsync(User_<id>) with SessionLock.acquire
               ├─ ok      → Schema.load (migrate + reconcile) → status "ready" → Profiles.loaded:fire
               ├─ locked  → retry 5× every 4 s (previous server still releasing) → kick with message
               ├─ corrupt / newer schema → "errored": play with defaults, never save, never grant purchases
               └─ request failures after retries → "errored"
ready: gameplay mutates Profiles.get(player) in memory only
autosave loop (one loop, every 5 s checks due sessions; each session every ~120 s, staggered, budget-aware)
   └─ UpdateAsync with SessionLock.save → "lost"? another server owns it → stop saving + kick
ProcessReceipt → grant in memory + record PurchaseId → save → PurchaseGranted only if the save succeeded
PlayerRemoving / BindToClose → release: final save + clear lock (parallel at shutdown, ≤ 25 s)
One DataStore request per key at a time (per-session mutex) → writes land in order.
```
Why each rule exists:
| Rule | Failure it prevents |
|---|---|
| Session lock in the value | fast rejoin on another server loads old data while the first server is still saving → item duplication or rollback |
| Errored sessions never save | a failed load treated as "new player" overwrites real data with defaults (the #1 data-loss bug) |
| Refuse newer `schemaVersion` | during a rolling update an old server would load v4 data and save it back without the v4 fields |
| `UpdateAsync` everywhere, pure transforms | `SetAsync` blindly overwrites; transforms may re-run and must not yield |
| Save refreshes the lock; expiry ≫ autosave | crashed servers' locks expire; live servers keep theirs |
| Purchase ids in the profile, bounded | `ProcessReceipt` can be called again (retries, rejoin on another server) → no double grant |
| Stagger + budget check | autosave bursts exhaust `60 + 40×players`/min and queue/drop requests |

## Code
<!-- code: examples/data/ServerScriptService/Profiles/SessionLock.luau -->
```luau
-- file: examples/data/ServerScriptService/Profiles/SessionLock.luau
--!strict
-- Pure UpdateAsync transforms for session-locked profiles. No Roblox APIs → tested in the Luau CLI
-- (examples/tests/data.spec.luau). Each transform returns (newValue, status); newValue == nil aborts the write.
-- Transforms may run several times per request and must not yield (UpdateAsync contract).
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Lock = { id: string, time: number }
export type Stored = { data: any, lock: Lock? }
export type AcquireStatus = "ok" | "locked" | "corrupt"
export type SaveStatus = "ok" | "lost"

local SessionLock = {}

-- Take the lock if the key is new, unlocked, ours, or the lock is older than `expiry` seconds (dead server).
function SessionLock.acquire(old: unknown, lockId: string, now: number, expiry: number,
	makeDefault: () -> any): (Stored?, AcquireStatus)
	if old ~= nil and (type(old) ~= "table" or (old :: any).data == nil) then
		return nil, "corrupt" -- never overwrite a value we don't understand
	end
	local stored: Stored = if old ~= nil then old :: Stored else { data = makeDefault() }
	local lock = stored.lock
	if lock and lock.id ~= lockId and now - lock.time < expiry then
		return nil, "locked"
	end
	stored.lock = { id = lockId, time = now }
	return stored, "ok"
end

-- Write `data` only while we still own the lock; refreshes the lock time (autosave keeps the lock alive).
function SessionLock.save(old: unknown, lockId: string, now: number, data: any): (Stored?, SaveStatus)
	if type(old) ~= "table" then
		return nil, "lost"
	end
	local stored = old :: Stored
	if not stored.lock or stored.lock.id ~= lockId then
		return nil, "lost" -- another server took over (our lock expired): our copy is stale, don't write it
	end
	stored.data = data
	stored.lock = { id = lockId, time = now }
	return stored, "ok"
end

-- Final save + unlock (player left / server closing).
function SessionLock.release(old: unknown, lockId: string, data: any): (Stored?, SaveStatus)
	local stored: Stored?, status: SaveStatus = SessionLock.save(old, lockId, 0, data)
	if stored then
		stored.lock = nil
	end
	return stored, status
end

return table.freeze(SessionLock)
```
<!-- /code -->

<!-- code: examples/data/ServerScriptService/Profiles/Schema.luau -->
```luau
-- file: examples/data/ServerScriptService/Profiles/Schema.luau
--!strict
-- Profile template, migrations and reconciliation (pure; CLI-tested).
-- Rules: never reuse or repurpose a field name; migrations are append-only; data from a NEWER schema is never
-- loaded by an older server (rolling updates) because saving it would silently drop the new fields.
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Profile = {
	schemaVersion: number,
	coins: number,
	inventory: { any },
	settings: { [string]: any },
	purchases: { string }, -- processed PurchaseIds, newest last (bounded)
	stats: { playTime: number, joins: number },
}

local Schema = {}

Schema.VERSION = 3
Schema.MAX_PURCHASE_IDS = 200

function Schema.template(): Profile
	return {
		schemaVersion = Schema.VERSION,
		coins = 0,
		inventory = {},
		settings = {},
		purchases = {},
		stats = { playTime = 0, joins = 0 },
	}
end

-- migrations[v] upgrades data from version v to v + 1. Keep old steps forever.
local migrations: { [number]: (data: { [string]: any }) -> () } = {
	[1] = function(data)
		-- v1 stored `gold`; v2 renamed it to `coins`.
		data.coins = data.gold or 0
		data.gold = nil
	end,
	[2] = function(data)
		-- v2 had a flat `playTime`; v3 groups stats.
		data.stats = { playTime = data.playTime or 0, joins = 0 }
		data.playTime = nil
	end,
}

-- Returns (profile, nil) or (nil, reason). Missing fields are filled from the template (deep, tables only).
function Schema.load(raw: unknown): (Profile?, string?)
	if type(raw) ~= "table" then
		return nil, "not a table"
	end
	local data = raw :: { [string]: any }
	local version = data.schemaVersion
	if version == nil then
		version = 1
	end
	if type(version) ~= "number" or version % 1 ~= 0 or version < 1 then
		return nil, "bad schemaVersion"
	end
	if version > Schema.VERSION then
		return nil, `data is from newer schema {version} (server knows {Schema.VERSION})`
	end
	for v = version, Schema.VERSION - 1 do
		local step = migrations[v]
		if not step then
			return nil, `missing migration {v} -> {v + 1}`
		end
		step(data)
	end
	data.schemaVersion = Schema.VERSION
	Schema.reconcile(data, Schema.template() :: any)
	return data :: any, nil
end

-- Adds keys that exist in `template` but not in `data` (recursively). Never removes unknown keys.
function Schema.reconcile(data: { [string]: any }, template: { [string]: any })
	for key, value in template do
		if data[key] == nil then
			data[key] = value
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil then
			Schema.reconcile(data[key], value)
		end
	end
end

-- Records a PurchaseId; returns false if it was already processed. Keeps the list bounded.
function Schema.recordPurchase(profile: Profile, purchaseId: string): boolean
	if table.find(profile.purchases, purchaseId) then
		return false
	end
	table.insert(profile.purchases, purchaseId)
	while #profile.purchases > Schema.MAX_PURCHASE_IDS do
		table.remove(profile.purchases, 1)
	end
	return true
end

return Schema
```
<!-- /code -->

<!-- code: examples/data/ServerScriptService/Profiles/init.luau -->
```luau
-- file: examples/data/ServerScriptService/Profiles/init.luau
--!strict
-- Profiles: session-locked player profiles on DataStoreService.
--   load (UpdateAsync + lock, migrations) → ready (gameplay edits profile in memory) → autosave (refreshes lock)
--   → release on leave / BindToClose. Failed or locked loads become "errored" sessions that never save.
-- One key per player ("User_<UserId>"), one request at a time per key, bounded retries with backoff.
-- Studio: needs "Enable Studio Access to API Services" and writes REAL data — use a separate test universe.
-- Status: TYPECHECKED (pure transforms CLI-EXECUTED in examples/tests/data.spec.luau). Not run in Studio.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Lib.Signal)
local Schema = require(script.Schema)
local SessionLock = require(script.SessionLock)

local STORE_NAME = "PlayerData_v1"
local LOCK_EXPIRY = 20 * 60 -- seconds; must be much longer than AUTOSAVE_INTERVAL
local AUTOSAVE_INTERVAL = 120
local LOCK_RETRIES = 5 -- the previous server may still be releasing (fast rejoin / teleport)
local LOCK_RETRY_DELAY = 4
local MAX_ATTEMPTS = 4 -- per request, backoff 2/4/8 s + jitter
local SHUTDOWN_BUDGET = 25 -- BindToClose gets ~30 s in total
local KICK_ON_LOCKED = true

export type Status = "loading" | "ready" | "errored" | "released"
type Session = {
	player: Player,
	userId: number,
	key: string,
	status: Status,
	data: Schema.Profile,
	busy: boolean, -- one DataStore request per key at a time (keeps writes ordered)
	nextSave: number,
	lastTick: number,
}

local Profiles = {}
Profiles.loaded = Signal.new() :: Signal.Signal<Player, Schema.Profile>

local sessions: { [Player]: Session } = {}
local lockId = HttpService:GenerateGUID(false)
local store: DataStore? = nil

local function setStatus(session: Session, status: Status)
	session.status = status
	-- Public, harmless flag so the client can show "progress will not be saved" banners.
	session.player:SetAttribute("DataStatus", status)
end

local function exclusive(session: Session, fn: () -> ())
	while session.busy do
		task.wait(0.1)
	end
	session.busy = true
	xpcall(fn, function(err: any)
		warn("[Profiles]", err, debug.traceback())
	end)
	session.busy = false
end

-- Runs a yielding DataStore call with bounded retries. A failed call may still have succeeded server-side,
-- which is why every write is an idempotent UpdateAsync transform.
local function withRetries(label: string, fn: () -> ()): boolean
	for attempt = 1, MAX_ATTEMPTS do
		local ok = xpcall(fn, function(err: any)
			warn(`[Profiles] {label} failed (attempt {attempt}/{MAX_ATTEMPTS}): {err}`)
		end)
		if ok then
			return true
		end
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ attempt + math.random())
		end
	end
	return false
end

local function userIdsOf(keyInfo: DataStoreKeyInfo?, userId: number): { number }
	local ids = if keyInfo then keyInfo:GetUserIds() else nil
	return if ids and #ids > 0 then ids else { userId }
end

local function release(session: Session)
	exclusive(session, function()
		if session.status ~= "ready" then
			return
		end
		setStatus(session, "released") -- stop autosave/purchases immediately
		local ds = store
		if not ds then
			return
		end
		session.data.stats.playTime += os.clock() - session.lastTick
		local data = session.data
		withRetries("release " .. session.key, function()
			ds:UpdateAsync(session.key, function(old: unknown, keyInfo: DataStoreKeyInfo?)
				local new = SessionLock.release(old, lockId, data)
				if not new then
					return nil -- lock lost: another server owns the profile now; our copy is stale
				end
				return new, userIdsOf(keyInfo, session.userId)
			end)
		end)
	end)
end

local function save(session: Session): boolean
	local saved = false
	exclusive(session, function()
		local ds = store
		if session.status ~= "ready" or not ds then
			return
		end
		local now = os.clock()
		session.data.stats.playTime += now - session.lastTick
		session.lastTick = now
		session.nextSave = now + AUTOSAVE_INTERVAL
		local data = session.data
		local status: SessionLock.SaveStatus = "lost"
		local ok = withRetries("save " .. session.key, function()
			ds:UpdateAsync(session.key, function(old: unknown, keyInfo: DataStoreKeyInfo?)
				local new: SessionLock.Stored?, s: SessionLock.SaveStatus = SessionLock.save(old, lockId, os.time(), data)
				status = s
				if not new then
					return nil
				end
				return new, userIdsOf(keyInfo, session.userId)
			end)
		end)
		if ok and status == "lost" then
			setStatus(session, "errored")
			session.player:Kick("Your data is open on another server. Please rejoin.")
		end
		saved = ok and status == "ok"
	end)
	return saved
end

local function load(player: Player)
	local session: Session = {
		player = player,
		userId = player.UserId,
		key = "User_" .. player.UserId,
		status = "loading",
		data = Schema.template(),
		busy = false,
		nextSave = os.clock() + AUTOSAVE_INTERVAL * (0.5 + math.random()), -- stagger autosaves
		lastTick = os.clock(),
	}
	sessions[player] = session
	setStatus(session, "loading")
	local ds = store
	if not ds then
		setStatus(session, "ready") -- memory-only mode (no DataStore access): nothing will be saved
		Profiles.loaded:fire(player, session.data)
		return
	end
	local final: Status = "errored"
	exclusive(session, function()
		for _ = 1, LOCK_RETRIES do
			local status: SessionLock.AcquireStatus = "corrupt"
			local stored: SessionLock.Stored? = nil
			local ok = withRetries("load " .. session.key, function()
				local value = ds:UpdateAsync(session.key, function(old: unknown, keyInfo: DataStoreKeyInfo?)
					local new: SessionLock.Stored?, s: SessionLock.AcquireStatus =
						SessionLock.acquire(old, lockId, os.time(), LOCK_EXPIRY, Schema.template)
					status = s -- the transform can re-run; the last run wins
					if not new then
						return nil
					end
					return new, userIdsOf(keyInfo, session.userId)
				end)
				stored = if status == "ok" then value :: SessionLock.Stored else nil
			end)
			if not ok then
				return -- request failures: errored session (defaults, never saved)
			end
			if status == "locked" then
				task.wait(LOCK_RETRY_DELAY)
				continue
			end
			if status ~= "ok" or not stored then
				warn(`[Profiles] {session.key}: stored value is not a profile; refusing to touch it`)
				return
			end
			local profile, err = Schema.load(stored.data)
			if not profile then
				warn(`[Profiles] {session.key}: {err}`)
				-- We hold the lock but can't use the data (e.g. newer schema): keep lock until release,
				-- which writes nothing because status stays "errored".
				return
			end
			profile.stats.joins += 1
			session.data = profile
			final = "ready"
			return
		end
		if KICK_ON_LOCKED then
			player:Kick("Your data is still being saved on another server. Please rejoin in a minute.")
		end
	end)
	if sessions[player] ~= session then
		-- Player left while loading: release what we acquired.
		if final == "ready" then
			setStatus(session, "ready")
			release(session)
		end
		return
	end
	setStatus(session, final)
	if final == "ready" then
		Profiles.loaded:fire(player, session.data)
	end
end

-- Profile for gameplay code; nil while loading or if the profile is errored (don't grant rewards then).
function Profiles.get(player: Player): Schema.Profile?
	local session = sessions[player]
	return if session and session.status == "ready" then session.data else nil
end

function Profiles.saveNow(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and save(session)
end

-- Developer products: grant in memory, record the PurchaseId, save; acknowledge only after a successful save.
function Profiles.processReceipt(receipt: { [string]: any },
	grant: (player: Player, profile: Schema.Profile) -> boolean): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local session = player and sessions[player]
	if not player or not session or session.status ~= "ready" then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retried when the player rejoins
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if table.find(session.data.purchases, purchaseId) then
		-- Already granted. Acknowledge only once that grant is durably saved.
		return if save(session) then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not grant(player, session.data) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Schema.recordPurchase(session.data, purchaseId)
	if save(session) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Grant + id stay in memory; the next callback retry finds the id and acknowledges after a successful save.
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function Profiles.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[Profiles] DataStores unavailable, running memory-only:", result)
	end

	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local session = sessions[player]
		sessions[player] = nil
		if session then
			release(session)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(5)
			local budget = math.min(
				DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardRead),
				DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardWrite)
			)
			local now = os.clock()
			for _, session in sessions do
				if budget <= 5 then
					break -- leave headroom for joins, leaves and purchases
				end
				if session.status == "ready" and not session.busy and now >= session.nextSave then
					budget -= 1
					task.spawn(save, session)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, session in sessions do
			sessions[player] = nil
			pending += 1
			task.spawn(function()
				release(session)
				pending -= 1
			end)
		end
		local deadline = os.clock() + SHUTDOWN_BUDGET
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return Profiles
```
<!-- /code -->

<!-- code: examples/data/ServerScriptService/DataServer.server.luau -->
```luau
-- file: examples/data/ServerScriptService/DataServer.server.luau
--!strict
-- Entry point: starts Profiles, owns MarketplaceService.ProcessReceipt (set exactly once, here), shows leaderstats.
-- Status: TYPECHECKED. Not run in Studio.
local MarketplaceService = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")

local Profiles = require(ServerScriptService.Profiles)

type Grant = (player: Player, profile: { coins: number }) -> boolean

local function grantCoins(amount: number): Grant
	return function(_player, profile)
		profile.coins += amount
		return true
	end
end

-- Developer product ids from the Creator Dashboard → grant. Unknown ids are never acknowledged.
local PRODUCTS: { [number]: Grant } = {
	-- [<your product id>] = grantCoins(100),
}

Profiles.start()

MarketplaceService.ProcessReceipt = function(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local grant = PRODUCTS[receipt.ProductId]
	if not grant then
		warn("[Purchases] unknown product", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Profiles.processReceipt(receipt, grant)
end

-- Public stat: leaderstats replicate to everyone, so only put public numbers here. Keep it in sync wherever coins
-- change (e.g. a small Economy module that edits profile.coins and the IntValue together).
Profiles.loaded:connect(function(player: Player, profile)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = profile.coins
	coins.Parent = folder
	folder.Parent = player
end)
```
<!-- /code -->

## Using it from gameplay
- Read/modify: `local profile = Profiles.get(player); if not profile then return end` — nil while loading or
  errored; don't award rewards into a profile that will never save (queue them or reject).
- Inventory integration: in a `Profiles.loaded` handler call `InventoryService.load(player, profile.inventory)`;
  before saves copy `InventoryService.serialize(player)` into `profile.inventory` (or write-through on every
  inventory change). See [inventory](inventory.md).
- Important moments (trade completed, rare drop, purchase): `Profiles.saveNow(player)`.
- Values must be DataStore-serializable: numbers, strings, booleans, plain tables (no mixed/sparse arrays), buffers.
  No Vector3/CFrame/Instance, NaN or inf.

## How to test
1. CLI: `luau examples/tests/data.spec.luau` — lock contention, stale lock expiry, lost-lock write rejection,
   autosave lock refresh, corrupt values untouched, v1→v3 migration, newer schema refused, purchase-id idempotency.
2. Studio (test universe, API access on): join, gain coins, leave, rejoin → coins persist; check Output for
   `[Profiles]` warnings.
3. Studio failure injection: temporarily add `error("test")` as the first line of the load transform → after the
   retries the session must end "errored", the `DataStatus` attribute shows it, and nothing is ever saved.
4. Live/Team Test: two servers of the same place — join server A, quickly teleport/rejoin into B → B waits for A's
   release (lock retries) instead of loading stale data.
5. Shutdown: with several players, shut down the server from the Creator Dashboard → all releases logged within the
   budget.
Studio playtests use separate, lower static limits and real data; never test against a production universe.

## Pitfalls
- Don't call `Profiles.get(player).coins += x` without the nil check.
- Don't save on every change; don't save from the client (impossible anyway — DataStoreService is server-only).
- Renaming `STORE_NAME` starts everyone from scratch — use migrations instead.
- `GetAsync` for other players' data (e.g. offline profile view) is cached 4 s and bypasses locks: read-only use.
- Leaderboards: separate `OrderedDataStore` with integer values, written on session end, read with caching.
- Right to be forgotten: keys follow `User_<UserId>`, so deletion requests can be processed by key.

Sources: cd:cloud-services/data-stores/index, cd:cloud-services/data-stores/error-codes-and-limits,
cd:cloud-services/data-stores/best-practices, cd:cloud-services/data-stores/player-data-purchasing,
cd:cloud-services/data-stores/versioning-listing-and-caching, cd:reference/engine/classes/GlobalDataStore,
cd:reference/engine/classes/DataStoreService, cd:reference/engine/classes/MarketplaceService,
cd:production/monetization/developer-products.
