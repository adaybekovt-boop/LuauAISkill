-- BAD: intentionally broken eval fixture (do not copy). Players sometimes get coins twice, sometimes never.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	player.leaderstats.Coins.Value += 100
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
	if purchased then
		local player = Players:GetPlayerByUserId(userId)
		player.leaderstats.Coins.Value += 100
	end
end)
