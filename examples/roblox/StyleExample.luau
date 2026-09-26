--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: Roblox client ModuleScript
-- Minimal native StyleSheet demo; single owner and explicit teardown.
export type Release = () -> ()
local StyleExample = {}
function StyleExample.mount(playerGui: PlayerGui): Release
    local gui = Instance.new("ScreenGui")
    gui.Name = "TKStyleExample"
    gui.ResetOnSpawn = false
    local sheet = Instance.new("StyleSheet")
    sheet.Name = "Theme"
    sheet:SetAttribute("PanelColor", Color3.fromRGB(24, 26, 29))
    sheet:SetAttribute("TextColor", Color3.fromRGB(232, 231, 227))
    sheet.Parent = gui
    local panelRule = Instance.new("StyleRule")
    panelRule.Selector = "Frame"
    panelRule:SetProperties({BackgroundColor3 = "$PanelColor", BorderSizePixel = 0})
    panelRule.Parent = sheet
    local textRule = Instance.new("StyleRule")
    textRule.Selector = "TextLabel"
    textRule:SetProperties({TextColor3 = "$TextColor", BackgroundTransparency = 1})
    textRule.Parent = sheet
    local link = Instance.new("StyleLink")
    link.StyleSheet = sheet
    link.Parent = gui
    local panel = Instance.new("Frame")
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.fromScale(0.6, 0.2)
    panel.Parent = gui
    local label = Instance.new("TextLabel")
    label.Text = "Native UI styling demo"
    label.Size = UDim2.fromScale(1, 1)
    label.TextSize = 20
    label.Parent = panel
    gui.Parent = playerGui
    local alive = true
    return function(): ()
        if not alive then return end
        alive = false
        gui:Destroy()
    end
end
return table.freeze(StyleExample)
