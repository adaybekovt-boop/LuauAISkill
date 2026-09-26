--!strict
-- Three typical remotes declared with NetServer: a discrete action, a continuous cosmetic stream, a request.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Validate = require(ReplicatedStorage.Lib.Validate)
local NetServer = require(ServerScriptService.Net.NetServer)

local EMOTES: { [string]: boolean } = { Wave = true, Point = true, Cheer = true }
local SHOP = { "Flashlight", "Battery", "Bandage", "Keycard", "Glowstick", "Map" }
local PAGE_SIZE = 4

-- 1. Discrete action (reliable): a few per burst, one every 2 s sustained.
NetServer.event("RequestEmote", {
	limit = { capacity = 3, rate = 0.5 },
	parse = function(emote: unknown): string?
		return Validate.oneOf(emote, EMOTES)
	end,
}, function(player: Player, emote: string)
	local character = player.Character
	if character then
		character:SetAttribute("Emote", emote) -- replicated state; clients play the animation
	end
end)

-- 2. Continuous cosmetic stream (unreliable): head pitch for other players' views, ≤ 20 Hz.
local aimRelay = NetServer.broadcast("AimPitchRelay", true)
NetServer.event("AimPitch", {
	limit = { capacity = 25, rate = 20 },
	parse = function(pitch: unknown): number?
		return Validate.number(pitch, -80, 80) -- degrees; also rejects NaN/inf
	end,
}, function(player: Player, pitch: number)
	-- Quantize: 0.5° steps are invisible and keep the payload tiny.
	(aimRelay :: UnreliableRemoteEvent):FireAllClients(player.UserId, math.round(pitch * 2) / 2)
end, true)

-- 3. Request/response: shop page. Non-yielding handler; returns a fresh table (never internal state).
NetServer.request("GetShopPage", {
	limit = { capacity = 5, rate = 1 },
	parse = function(page: unknown): number?
		return Validate.integer(page, 1, math.ceil(#SHOP / PAGE_SIZE))
	end,
}, function(_player: Player, page: number)
	local items = {}
	for i = (page - 1) * PAGE_SIZE + 1, math.min(page * PAGE_SIZE, #SHOP) do
		table.insert(items, SHOP[i])
	end
	return items
end)
