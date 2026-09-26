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
