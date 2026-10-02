--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Service = require(script.Parent.Boards.Service)
local remote = Instance.new("RemoteEvent")
remote.Name = "LeaderboardQuery"
remote.Parent = ReplicatedStorage
local nextRequest: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
remote.OnServerEvent:Connect(function(player: Player, mode: any)
	if (mode ~= "global" and mode ~= "friends") or busy[player] or os.clock() < (nextRequest[player] or 0) then return end
	nextRequest[player] = os.clock() + 3
	busy[player] = true
	local snapshot = Service.get(player, mode)
	busy[player] = nil
	if player.Parent == Players then remote:FireClient(player, mode, snapshot) end
end)
Players.PlayerRemoving:Connect(function(player) nextRequest[player], busy[player] = nil, nil end)
-- Trusted score producers call Service.recordBest(userId, score) AFTER their canonical save succeeds.
