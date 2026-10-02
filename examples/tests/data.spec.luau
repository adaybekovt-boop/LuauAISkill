--!strict
-- Unit tests for session locking + schema migrations. Run: luau examples/tests/data.spec.luau (from repo root).
-- A fake store reproduces the UpdateAsync contract: transform(old) → new value, or nil to abort (value unchanged).
local SessionLock = require("../data/ServerScriptService/Profiles/SessionLock")
local Schema = require("../data/ServerScriptService/Profiles/Schema")

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(function(): boolean
		fn()
		return true
	end)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(`{msg or "expected equal"}: {tostring(a)} ~= {tostring(b)}`, 2)
	end
end

type Fake = { values: { [string]: any }, update: (self: Fake, key: string, fn: (any) -> any) -> any }
local function fakeStore(): Fake
	local store = { values = {} } :: Fake
	function store.update(self: Fake, key: string, fn: (any) -> any): any
		-- deep-copy like the real service (values are serialized), so tests can't cheat via shared references
		local function copy(v: any): any
			if type(v) ~= "table" then
				return v
			end
			local t = {}
			for k, x in v do
				t[k] = copy(x)
			end
			return t
		end
		local new = fn(copy(self.values[key]))
		if new ~= nil then
			self.values[key] = copy(new)
		end
		return copy(self.values[key])
	end
	return store
end

local EXPIRY = 600
local function acquire(store: Fake, key: string, server: string, now: number): string
	local status = "?"
	store:update(key, function(old)
		local new, s = SessionLock.acquire(old, server, now, EXPIRY, Schema.template)
		status = s
		return new
	end)
	return status
end
local function save(store: Fake, key: string, server: string, now: number, data: any): string
	local status = "?"
	store:update(key, function(old)
		local new, s = SessionLock.save(old, server, now, data)
		status = s
		return new
	end)
	return status
end

test("new player gets defaults and the lock", function()
	local store = fakeStore()
	eq(acquire(store, "User_1", "A", 0), "ok")
	eq(store.values.User_1.lock.id, "A")
	eq(store.values.User_1.data.coins, 0)
end)
test("second server is blocked while the lock is fresh, succeeds after release", function()
	local store = fakeStore()
	acquire(store, "User_1", "A", 0)
	eq(acquire(store, "User_1", "B", 10), "locked")
	store:update("User_1", function(old)
		return (SessionLock.release(old, "A", { coins = 5, schemaVersion = Schema.VERSION }))
	end)
	eq(store.values.User_1.lock, nil, "released")
	eq(acquire(store, "User_1", "B", 11), "ok")
	eq(store.values.User_1.data.coins, 5, "B sees A's final save")
end)
test("stale lock (crashed server) expires", function()
	local store = fakeStore()
	acquire(store, "User_1", "A", 0)
	eq(acquire(store, "User_1", "B", EXPIRY + 1), "ok")
end)
test("server that lost its lock cannot overwrite newer data", function()
	local store = fakeStore()
	acquire(store, "User_1", "A", 0)
	acquire(store, "User_1", "B", EXPIRY + 1) -- A froze, B took over
	eq(save(store, "User_1", "B", EXPIRY + 2, { coins = 50 }), "ok")
	eq(save(store, "User_1", "A", EXPIRY + 3, { coins = 1 }), "lost")
	eq(store.values.User_1.data.coins, 50, "A's stale write was rejected")
end)
test("autosave refreshes the lock time", function()
	local store = fakeStore()
	acquire(store, "User_1", "A", 0)
	save(store, "User_1", "A", 500, { coins = 1 })
	eq(acquire(store, "User_1", "B", 700), "locked", "lock refreshed at t=500")
end)
test("non-profile values are never overwritten", function()
	local store = fakeStore()
	store.values.User_1 = "legacy string value"
	eq(acquire(store, "User_1", "A", 0), "corrupt")
	eq(store.values.User_1, "legacy string value")
end)
test("migrations v1 -> v3 and reconcile", function()
	local profile, err = Schema.load({ gold = 42, playTime = 100 }) -- v1 (no schemaVersion)
	eq(err, nil)
	assert(profile)
	eq(profile.coins, 42)
	eq((profile :: any).gold, nil)
	eq(profile.stats.playTime, 100)
	eq(profile.schemaVersion, Schema.VERSION)
	eq(type(profile.purchases), "table", "filled from template")
end)
test("newer schema is refused (rolling update safety)", function()
	local profile, err = Schema.load({ schemaVersion = Schema.VERSION + 1, coins = 1 })
	eq(profile, nil)
	assert(err and string.find(err, "newer"), "reason mentions newer schema")
end)
test("purchase ids remain idempotent beyond the old cap and across sessions", function()
	local p = Schema.template()
	eq(Schema.recordPurchase(p, "abc"), true)
	eq(Schema.recordPurchase(p, "abc"), false)
	for i = 1, 1501 do
		Schema.recordPurchase(p, tostring(i))
	end
	eq(#p.purchases, 1502)
	eq(Schema.recordPurchase(p, "abc"), false, "oldest receipt must not be evicted")
	local store = fakeStore()
	eq(acquire(store, "User_1", "A", 0), "ok")
	p.coins = 1502
	eq(save(store, "User_1", "A", 1, p), "ok")
	store:update("User_1", function(old)
		return (SessionLock.release(old, "A", p))
	end)
	eq(acquire(store, "User_1", "B", 2), "ok")
	local loaded = Schema.load(store.values.User_1.data)
	assert(loaded)
	eq(Schema.recordPurchase(loaded, "abc"), false, "rejoin must preserve oldest receipt")
	eq(loaded.coins, 1502)
	eq(#loaded.purchases, 1502)
end)

print(`data.spec: {passed} passed, {failed} failed`)
if failed > 0 then
	error("data tests failed")
end
