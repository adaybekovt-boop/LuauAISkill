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
