-- Client snippet
remote:FireServer(game.Players.LocalPlayer, "hello")
-- Server snippet
remote.OnServerEvent:Connect(function(player, text)
	print(string.upper(text))
end)
