-- BAD: intentionally broken eval fixture (do not copy). Players report losing all progress sometimes.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local store = DataStoreService:GetDataStore("PlayerData")
local data = {}

Players.PlayerAdded:Connect(function(player)
	local success, saved = pcall(function()
		return store:GetAsync(player.UserId)
	end)
	data[player] = saved or { coins = 0, items = {} }
end)

Players.PlayerRemoving:Connect(function(player)
	store:SetAsync(player.UserId, data[player])
end)
