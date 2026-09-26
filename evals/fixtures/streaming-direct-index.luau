-- BAD: intentionally broken eval fixture (do not copy). LocalScript; errors only in the live game, "works in Studio".
local door = workspace.Map.Building3.Door
local prompt = door.ProximityPrompt

prompt.Triggered:Connect(function()
	door.Transparency = 1
	door.CanCollide = false
end)
