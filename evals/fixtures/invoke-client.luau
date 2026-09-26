-- BAD: intentionally broken eval fixture (do not copy). Server hangs sometimes when a round starts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local getLoadout = ReplicatedStorage:WaitForChild("GetLoadout")

local function startRound(players)
	for _, player in ipairs(players) do
		local loadout = getLoadout:InvokeClient(player)
		for _, itemName in ipairs(loadout) do
			game.ServerStorage.Items[itemName]:Clone().Parent = player.Backpack
		end
	end
end

return startRound
