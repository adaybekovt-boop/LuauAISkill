--!strict
-- Real UpdateAsync smoke of the recipe transforms, using ONLY a dedicated disposable store/key.
-- NOT RUN. Does not prove Profiles.start lifecycle, rejoin, autosave or BindToClose.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Context = require(script.Parent.Context)

return function(ctx: Context.Context)
	assert(Workspace:GetAttribute("ReleaseSmokeAllowDataStore") == true, "DataStore writes not opted in")
	local expected = Workspace:GetAttribute("ReleaseSmokeTestUniverseId")
	assert(type(expected) == "number" and expected > 0 and game.GameId == expected,
		"explicit dedicated test universe ID must match game.GameId")
	local transforms = Context.child(ServerScriptService, "Profiles")
	local Lock = Context.module(transforms, "SessionLock")
	local Schema = Context.module(transforms, "Schema")
	local store = DataStoreService:GetDataStore("LuauAISkill_ReleaseSmoke_v1")
	local key = "Smoke_" .. HttpService:GenerateGUID(false)
	local owner = HttpService:GenerateGUID(false)
	local ok, err = xpcall(function()
		local value = store:UpdateAsync(key, function(old: any): any
			local nextValue = Lock.acquire(old, owner, os.time(), 120, Schema.template)
			return nextValue
		end)
		ctx.check("acquire-real-key", value ~= nil and value.lock.id == owner)
		local contender = "other-" .. owner
		local status = ""
		store:UpdateAsync(key, function(old: any): any
			local nextValue, result = Lock.acquire(old, contender, os.time(), 120, Schema.template)
			status = result
			return nextValue
		end)
		ctx.check("foreign-lock-rejected", status == "locked")
		local profile = Schema.template()
		profile.coins = 37
		store:UpdateAsync(key, function(old: any): any
			local nextValue, result = Lock.save(old, owner, os.time(), profile)
			status = result
			return nextValue
		end)
		local options = Instance.new("DataStoreGetOptions")
		options.UseCache = false
		local saved = store:GetAsync(key, options)
		ctx.check("uncached-save-readback", status == "ok" and saved.data.coins == 37)
		store:UpdateAsync(key, function(old: any): any
			local nextValue = Lock.release(old, owner, profile)
			return nextValue
		end)
		local released = store:GetAsync(key, options)
		ctx.check("release-clears-lock", released.lock == nil and released.data.coins == 37)
		local acquired = store:UpdateAsync(key, function(old: any): any
			local nextValue = Lock.acquire(old, contender, os.time(), 120, Schema.template)
			return nextValue
		end)
		ctx.check("second-owner-preserves-data", acquired.lock.id == contender and acquired.data.coins == 37)
		return true
	end, function(message: any): string return debug.traceback(tostring(message)) end)
	-- Remove only this run's unique key. This is a recoverable DataStore removal, not a purge of versions.
	local cleaned, cleanupError = pcall(function() store:RemoveAsync(key) end)
	ctx.check("disposable-key-cleaned", cleaned, if cleaned then key else tostring(cleanupError))
	assert(ok, tostring(err))
end
