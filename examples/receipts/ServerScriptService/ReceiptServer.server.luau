--!strict
-- Dedicated ledger: ALL writers of PurchasedCoins must use this atomic store.
-- Configure the real CoinProductId on this Script before enabling sales. No invented IDs.
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Ledger = require(script.Parent.Receipts.Ledger)
local store = DataStoreService:GetDataStore("ReceiptLedger_v1")
local productId = script:GetAttribute("CoinProductId")
local productValid = type(productId) == "number" and productId > 0 and productId % 1 == 0
local closing = false
local active = 0
local connections: { RBXScriptConnection } = {}
local function receive(receipt: { [string]: any }, kind: string): Enum.ReceiptDecision
	if closing then return Enum.ReceiptDecision.NotProcessedYet end
	local userId, id = receipt.PlayerId, receipt.PurchaseId
	if type(userId) ~= "number" or type(id) ~= "string" then return Enum.ReceiptDecision.NotProcessedYet end
	local player = Players:GetPlayerByUserId(userId)
	if not player then return Enum.ReceiptDecision.NotProcessedYet end
	local delta: number
	if kind == "product" then
		if not productValid or receipt.ProductId ~= productId then
			warn("[Receipts] Unknown product; reconcile configuration before retrying")
			return Enum.ReceiptDecision.NotProcessedYet
		end
		delta = 100 -- server-owned reward mapping; never compare CurrencySpent with a list price
	else
		delta = receipt.CurrencySpent -- audit totals ONLY, not a grant of in-experience coins
	end
	local event: Ledger.Event = { id = id, kind = kind, delta = delta,
		transferRequestId = if kind ~= "product" then receipt.TransferRequestId else nil }
	active += 1
	local reason = "request failed"
	local ok, saved = pcall(function()
		return store:UpdateAsync("User_" .. tostring(userId), function(old: any)
			local nextState, why = Ledger.apply(old, event)
			reason = why
			-- No grants, remotes, or yielding inside this retryable transform.
			return nextState, { userId }
		end)
	end)
	active -= 1
	if not ok or saved == nil then
		warn("[Receipts] Deferred:", reason)
		return Enum.ReceiptDecision.NotProcessedYet
	end
	-- Presentation only: never spend from this attribute or another independent profile.
	if player.Parent == Players then
		local shown = player:GetAttribute("PurchasedCoins")
		player:SetAttribute("PurchasedCoins", math.max(saved.coins, if type(shown) == "number" then shown else 0))
	end
	return Enum.ReceiptDecision.Processed
end
-- Catch-all owns unknown products too, preventing accidental auto-acknowledgement.
table.insert(connections, MarketplaceService:BindReceiptHandler(Enum.ReceiptType.DeveloperProduct,
	function(r: { [string]: any }) return receive(r, "product") end))
table.insert(connections, MarketplaceService:BindReceiptHandler(Enum.ReceiptType.RobuxTransferSender,
	function(r: { [string]: any }) return receive(r, "sender") end))
table.insert(connections, MarketplaceService:BindReceiptHandler(Enum.ReceiptType.RobuxTransferReceiver,
	function(r: { [string]: any }) return receive(r, "receiver") end))
local function load(player: Player)
	local ok, value = pcall(function() return store:GetAsync("User_" .. tostring(player.UserId)) end)
	if ok and type(value) == "table" and type(value.coins) == "number" and player.Parent == Players then
		-- Concurrent receipt callbacks may already have published a newer total.
		local shown = player:GetAttribute("PurchasedCoins")
		player:SetAttribute("PurchasedCoins", math.max(value.coins, if type(shown) == "number" then shown else 0))
	end
end
Players.PlayerAdded:Connect(load)
for _, player in Players:GetPlayers() do task.spawn(load, player) end
game:BindToClose(function()
	closing = true
	local deadline = os.clock() + 25
	while active > 0 and os.clock() < deadline do task.wait(0.1) end
	for _, connection in connections do connection:Disconnect() end
end)
