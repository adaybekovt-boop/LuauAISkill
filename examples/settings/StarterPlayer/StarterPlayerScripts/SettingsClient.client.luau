--!strict
-- Settings menu generated from Schema: works with mouse, touch and gamepad (buttons only, Selectable, no drag-only
-- controls). Changes apply immediately and are saved to the server 1 s after the last change.
-- Toggle: M key or gamepad Select; ContextActionService also creates a touch button.
-- Status: TYPECHECKED. Not run in Studio.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Schema = require(ReplicatedStorage.Settings.Schema)
local ClientSettings = require(ReplicatedStorage.Settings.ClientSettings)

local remotes = ReplicatedStorage:WaitForChild("SettingsRemotes", 30)
assert(remotes, "SettingsRemotes missing (is SettingsServer running?)")
local saveRemote = remotes:WaitForChild("SaveSettings", 30) :: RemoteEvent
local syncRemote = remotes:WaitForChild("SettingsSync", 30) :: RemoteEvent

---------------------------------------------------------------- apply
-- Volume buses: a SoundGroup (legacy Sound) or an AudioFader (Audio API) named like this in SoundService.
local function setBus(name: string, volume: number)
	local bus = SoundService:FindFirstChild(name)
	if bus and bus:IsA("SoundGroup") then
		bus.Volume = volume
	elseif bus and bus:IsA("AudioFader") then
		bus.Volume = volume
	end
end

local function apply(id: string, value: any)
	if id == "MasterVolume" then
		setBus("Master", value)
	elseif id == "MusicVolume" then
		setBus("Music", value)
	elseif id == "FieldOfView" then
		-- If a custom camera controller owns the FOV (e.g. the bodycam recipe), let IT read ClientSettings instead.
		local camera = Workspace.CurrentCamera
		if camera then
			camera.FieldOfView = value
		end
	end
	-- CameraShake / ViewBobbing / Subtitles / GraphicsTier are read by their own systems via ClientSettings.
end
ClientSettings.changed:connect(apply)

---------------------------------------------------------------- save (debounced)
local saveToken = 0
local suppressSave = false -- true while applying settings that came FROM the server
ClientSettings.changed:connect(function()
	if suppressSave then
		return
	end
	saveToken += 1
	local token = saveToken
	task.delay(1, function()
		if token == saveToken then
			saveRemote:FireServer(ClientSettings.all())
		end
	end)
end)

---------------------------------------------------------------- UI
local gui = Instance.new("ScreenGui")
gui.Name = "SettingsMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Enabled = false

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromScale(0.42, 0.7)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
panel.BackgroundTransparency = 0.1
panel.Parent = gui
local constraint = Instance.new("UISizeConstraint")
constraint.MinSize = Vector2.new(320, 300) -- stays usable on small phones
constraint.MaxSize = Vector2.new(640, 720)
constraint.Parent = panel
local padding = Instance.new("UIPadding")
padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12)
padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 16), UDim.new(0, 16)
padding.Parent = panel
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = panel

local function text(parent: Instance, className: string, value: string, size: UDim2): TextLabel | TextButton
	local t = Instance.new(className) :: any
	t.Text = value
	t.Size = size
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(235, 235, 235)
	t.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
	t.BackgroundTransparency = if className == "TextLabel" then 1 else 0
	t.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.Parent = t
	return t
end

local firstButton: GuiObject? = nil
local refreshers: { [string]: () -> () } = {}

local function valueText(def: Schema.Def): string
	local v = ClientSettings.get(def.id)
	if def.kind == "toggle" then
		return if v then "On" else "Off"
	elseif def.kind == "range" then
		return if def.max <= 1 then `{math.floor(v * 100 + 0.5)}%` else tostring(v)
	end
	return tostring(v)
end

for i, def in Schema.defs do
	local row = Instance.new("Frame")
	row.LayoutOrder = i
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundTransparency = 1
	row.Parent = panel
	local label = text(row, "TextLabel", def.label, UDim2.fromScale(0.45, 1)) :: TextLabel
	label.TextXAlignment = Enum.TextXAlignment.Left
	local value = text(row, "TextButton", "", UDim2.fromScale(0.3, 1)) :: TextButton
	value.Position = UDim2.fromScale(0.57, 0)
	refreshers[def.id] = function()
		value.Text = valueText(def)
	end
	if def.kind == "range" then
		local minus = text(row, "TextButton", "−", UDim2.fromScale(0.1, 1)) :: TextButton
		minus.Position = UDim2.fromScale(0.46, 0)
		local plus = text(row, "TextButton", "+", UDim2.fromScale(0.1, 1)) :: TextButton
		plus.Position = UDim2.fromScale(0.88, 0)
		minus.Activated:Connect(function()
			ClientSettings.set(def.id, ClientSettings.get(def.id) - def.step)
		end)
		plus.Activated:Connect(function()
			ClientSettings.set(def.id, ClientSettings.get(def.id) + def.step)
		end)
		firstButton = firstButton or minus
	elseif def.kind == "toggle" then
		value.Activated:Connect(function()
			ClientSettings.set(def.id, not ClientSettings.get(def.id))
		end)
		firstButton = firstButton or value
	else
		value.Activated:Connect(function() -- cycle through options
			local options = def.options
			local index = table.find(options, ClientSettings.get(def.id)) or 1
			ClientSettings.set(def.id, options[index % #options + 1])
		end)
		firstButton = firstButton or value
	end
	refreshers[def.id]()
end
ClientSettings.changed:connect(function(id: string)
	local refresh = refreshers[id]
	if refresh then
		refresh()
	end
end)
gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

ContextActionService:BindAction("ToggleSettings", function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		gui.Enabled = not gui.Enabled
		-- Gamepad: put selection on the first control when opening, clear it when closing.
		GuiService.SelectedObject = if gui.Enabled then firstButton else nil
	end
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.M, Enum.KeyCode.ButtonSelect)

syncRemote.OnClientEvent:Connect(function(saved: unknown)
	suppressSave = true
	ClientSettings.load(saved)
	suppressSave = false
end)
syncRemote:FireServer() -- ask for saved settings now that the handler is connected
for id, v in ClientSettings.all() do
	apply(id, v)
end
