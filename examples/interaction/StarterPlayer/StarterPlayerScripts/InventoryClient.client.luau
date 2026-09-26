--!strict
-- Hotbar view for the server inventory. Displays snapshots and sends intents; never edits inventory state itself.
-- Keys 1–9 / click / tap = Use; right click = Drop. Built in code for the recipe; in a real project author the
-- ScreenGui in StarterGui and keep only the binding logic here.
-- Status: TYPECHECKED. Not run in Studio.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Inventory.Items)

local SLOTS = 9 -- must match InventoryService.CAPACITY
local KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
assert(remotes, "Remotes folder missing (is InventoryServer running?)")
local action = remotes:WaitForChild("InventoryAction", 30) :: RemoteEvent
local syncRemote = remotes:WaitForChild("InventorySync", 30) :: RemoteEvent

local gui = Instance.new("ScreenGui")
gui.Name = "Hotbar"
gui.ResetOnSpawn = false -- survives respawn; state comes from the server anyway
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -12)
bar.Size = UDim2.fromScale(0.6, 0.09)
bar.BackgroundTransparency = 1
bar.Parent = gui
local barAspect = Instance.new("UIAspectRatioConstraint")
barAspect.AspectRatio = SLOTS -- square slots at any resolution
barAspect.Parent = bar

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0.005, 0)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

local buttons: { TextButton } = {}
for i = 1, SLOTS do
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. i
	button.LayoutOrder = i
	button.Size = UDim2.fromScale(1 / SLOTS - 0.006, 1)
	button.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	button.BackgroundTransparency = 0.25
	button.TextColor3 = Color3.fromRGB(235, 235, 235)
	button.TextScaled = true
	button.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	button.Text = ""
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 18
	constraint.Parent = button
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = button
	button.Activated:Connect(function() -- Activated covers mouse, touch and gamepad selection
		action:FireServer("Use", i)
	end)
	button.MouseButton2Click:Connect(function()
		action:FireServer("Drop", i)
	end)
	button.Parent = bar
	buttons[i] = button
end
gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

syncRemote.OnClientEvent:Connect(function(snapshot: unknown)
	for i = 1, SLOTS do
		buttons[i].Text = ""
	end
	if type(snapshot) ~= "table" then
		return
	end
	for _, entry in snapshot :: { any } do
		if type(entry) ~= "table" or type(entry.s) ~= "number" or type(entry.c) ~= "number" then
			continue
		end
		local button = buttons[entry.s]
		local def = Items[entry.i]
		if button and def then
			button.Text = if entry.c > 1 then `{def.name}\n×{entry.c}` else def.name
		end
	end
end)

ContextActionService:BindAction("HotbarUse", function(_name: string, state: Enum.UserInputState, input: InputObject)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local index = table.find(KEYS, input.KeyCode)
	if index then
		action:FireServer("Use", index)
	end
	return Enum.ContextActionResult.Sink
end, false, table.unpack(KEYS))
