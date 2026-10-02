--!strict
-- Optional server-only entry point for your existing, rate-limited interaction UI.
-- Caller supplies a server-configured recipient and amount, never a client supplied pair.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local nextPrompt: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player) nextPrompt[player] = nil end)
local TransferPrompt = {}
function TransferPrompt.request(sender: Player, configuredRecipient: number, configuredAmount: number): (boolean, string?)
	if sender.Parent ~= Players or configuredRecipient == sender.UserId
		or configuredRecipient <= 0 or configuredRecipient > 9007199254740991 or configuredRecipient % 1 ~= 0
		or configuredAmount <= 0 or configuredAmount > 1000 or configuredAmount % 1 ~= 0
		or configuredRecipient ~= configuredRecipient or configuredAmount ~= configuredAmount then return false, nil end
	local now = os.clock()
	if now < (nextPrompt[sender] or 0) then return false, nil end
	nextPrompt[sender] = now + 30
	local ok, result = pcall(function()
		return MarketplaceService:PromptRobuxTransferAsync(sender, configuredRecipient, configuredAmount)
	end)
	-- Request ID is NOT settlement. Sender/receiver receipts are handled independently.
	return ok, if ok then result else nil
end
return TransferPrompt
