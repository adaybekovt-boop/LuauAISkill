--!strict
-- Receives settings from clients (rate-limited, sanitized) and hands them to persistence; sends saved settings on join.
-- Persistence hooks default to memory; with the save-system recipe use profile.settings (the template has it):
--   getSaved = function(p) local prof = Profiles.get(p); return prof and prof.settings end
--   save = function(p, s) local prof = Profiles.get(p); if prof then prof.settings = s end end
-- Status: TYPECHECKED (schema CLI-EXECUTED). Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
local Schema = require(ReplicatedStorage.Settings.Schema)

local memory: { [Player]: Schema.Values } = {}
local hooks = {
	getSaved = function(player: Player): unknown
		return memory[player]
	end,
	save = function(player: Player, settings: Schema.Values)
		memory[player] = settings
	end,
}

local folder = Instance.new("Folder")
folder.Name = "SettingsRemotes"
local saveRemote = Instance.new("RemoteEvent")
saveRemote.Name = "SaveSettings"
saveRemote.Parent = folder
local syncRemote = Instance.new("RemoteEvent")
syncRemote.Name = "SettingsSync"
syncRemote.Parent = folder
folder.Parent = ReplicatedStorage

local limiter = TokenBucket.new({ Save = { capacity = 3, rate = 0.5 } }) -- the client debounces; this is a flood guard

saveRemote.OnServerEvent:Connect(function(player: Player, raw: unknown)
	if not limiter:allow(player, "Save", os.clock()) then
		return
	end
	hooks.save(player, Schema.sanitize(raw))
end)

-- The client asks once its UI is ready (avoids firing before its handler is connected).
syncRemote.OnServerEvent:Connect(function(player: Player)
	if limiter:allow(player, "Save", os.clock()) then
		syncRemote:FireClient(player, Schema.sanitize(hooks.getSaved(player)))
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	memory[player] = nil
	limiter:forget(player)
end)
