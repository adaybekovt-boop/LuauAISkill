-- BAD: intentionally broken eval fixture (do not copy). Bullets pass through walls and players at high speed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local fire = ReplicatedStorage:WaitForChild("Fire")

fire.OnServerEvent:Connect(function(player, direction)
	local bullet = Instance.new("Part")
	bullet.Size = Vector3.new(0.2, 0.2, 1)
	bullet.CFrame = player.Character.Head.CFrame
	bullet.Velocity = direction * 800
	bullet.Parent = workspace
	bullet.Touched:Connect(function(hit)
		local hum = hit.Parent:FindFirstChild("Humanoid")
		if hum then
			hum:TakeDamage(30)
		end
		bullet:Destroy()
	end)
end)
