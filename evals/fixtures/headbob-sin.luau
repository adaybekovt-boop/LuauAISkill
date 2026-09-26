-- BAD: intentionally broken eval fixture (do not copy). LocalScript: "realistic" head bob players call nauseating.
local RunService = game:GetService("RunService")
local player = game.Players.LocalPlayer
local camera = workspace.CurrentCamera

RunService.RenderStepped:Connect(function()
	local character = player.Character
	if character and character.Humanoid.MoveDirection.Magnitude > 0 then
		local t = tick()
		camera.CFrame = camera.CFrame * CFrame.new(math.sin(t * 10) * 0.5, math.abs(math.cos(t * 10)) * 0.5, 0)
			* CFrame.Angles(0, 0, math.sin(t * 10) * 0.05)
	end
end)
