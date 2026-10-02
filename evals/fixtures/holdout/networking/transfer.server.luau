local transfer = game.ReplicatedStorage.Transfer
local balances = {}
transfer.OnServerEvent:Connect(function(player, fromUserId, toUserId, amount)
    balances[fromUserId] = (balances[fromUserId] or 0) - amount
    balances[toUserId] = (balances[toUserId] or 0) + amount
end)
