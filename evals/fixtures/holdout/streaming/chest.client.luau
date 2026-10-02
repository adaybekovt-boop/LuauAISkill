local chest = workspace.World.Island.TreasureChest
chest.ProximityPrompt.Triggered:Connect(function()
    game.ReplicatedStorage.ClaimChest:FireServer(chest)
end)
