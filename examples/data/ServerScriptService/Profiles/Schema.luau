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
