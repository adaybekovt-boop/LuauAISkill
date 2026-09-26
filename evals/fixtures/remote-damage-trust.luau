-- BAD: intentionally broken eval fixture (do not copy). Server script from a real-looking sword game.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local damageEvent = ReplicatedStorage:WaitForChild("DamageEvent")

damageEvent.OnServerEvent:Connect(function(player, target, damage)
	local humanoid = target.Parent:FindFirstChild("Humanoid")
	humanoid:TakeDamage(damage)
	player.leaderstats.Kills.Value = player.leaderstats.Kills.Value + (humanoid.Health <= 0 and 1 or 0)
end)
