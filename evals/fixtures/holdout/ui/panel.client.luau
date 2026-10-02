local panel = script.Parent.Panel
local coins = game.Players.LocalPlayer:WaitForChild("Coins")
local function open()
    panel.Visible = true
    coins.Changed:Connect(function(value)
        panel.Amount.Text = tostring(value)
    end)
end
return open
