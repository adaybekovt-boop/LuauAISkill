game.ReplicatedStorage.Hit.OnServerEvent:Connect(function(player, humanoid, damage)
    humanoid:TakeDamage(math.clamp(damage, 0, 100))
end)
