-- BAD: intentionally broken eval fixture (do not copy). LocalScript in a coin-collecting game.
local player = game.Players.LocalPlayer

for _, coin in pairs(workspace.Coins:GetChildren()) do
	coin.Touched:Connect(function(hit)
		if hit.Parent == player.Character then
			player.leaderstats.Coins.Value += 1
			coin:Destroy()
		end
	end)
end
