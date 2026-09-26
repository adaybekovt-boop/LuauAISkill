-- BAD: intentionally broken eval fixture (do not copy). "Shop button is off-screen on phones and doesn't work on Xbox."
local player = game.Players.LocalPlayer
local gui = Instance.new("ScreenGui", player.PlayerGui)
local button = Instance.new("TextButton", gui)
button.Size = UDim2.new(0, 400, 0, 120)
button.Position = UDim2.new(0, 1500, 0, 900)
button.Text = "SHOP"
button.TextSize = 60
button.MouseButton1Click:Connect(function()
	print("open shop")
end)
