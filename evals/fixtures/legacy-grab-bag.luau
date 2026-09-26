-- LEGACY: intentionally outdated eval fixture (do not copy). Asked: "modernize this without changing behaviour".
local Players = game:GetService("Players")

local function onCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://0"
	local track = humanoid:LoadAnimation(anim)
	track:Play()

	local root = character:WaitForChild("HumanoidRootPart")
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 0, 1e5)
	bv.Velocity = root.CFrame.lookVector * 20
	bv.Parent = root
	game:GetService("Debris"):AddItem(bv, 0.3)

	spawn(function()
		while wait(1) do
			local ray = Ray.new(root.Position, Vector3.new(0, -10, 0))
			local hit = workspace:FindPartOnRayWithIgnoreList(ray, { character })
			if hit then
				print("ground", hit.Name)
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacter)
	if player:IsInGroup(1234) then
		print("group member")
	end
end)
