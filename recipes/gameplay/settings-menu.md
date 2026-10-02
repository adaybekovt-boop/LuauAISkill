# Recipe: settings menu (schema-driven, saved on the server, gamepad/touch friendly)

## When NOT to use
Do not let client preferences modify authoritative gameplay rules or bypass server permissions.

Evidence: schema CLI-EXECUTED (`examples/tests/settings.spec.luau`, 4 tests) · client/server TYPECHECKED ·
**not run in Studio**. Chapters: [UI/UX](../../handbook/roblox/18-ui-ux.md), [input](../../handbook/roblox/19-input.md).
Graphics part: [graphics presets](../graphics/graphics-presets.md). Persistence: [save system](save-system.md).

## Architecture
```text
Settings/Schema (shared, pure): defs {id, label, kind range|toggle|choice, default, bounds/options}
                                sanitize(untrusted) → complete valid table (clamp, snap, drop unknown keys)
Settings/ClientSettings (client): get/all/set/load + changed signal — camera, audio, graphics read from here
SettingsClient: menu rows generated from Schema · buttons only (−/+, toggle, cycle) → mouse/touch/gamepad
                apply immediately · save 1 s after the last change (debounce) · M / gamepad Select / touch button
SettingsServer: SaveSettings (flood-limited) → sanitize → persistence hook
                SettingsSync: client asks after its handler is connected → server sends saved settings
```
Why:
- **One schema** drives UI, validation and defaults → adding a setting is one line; server and client can't
  disagree about valid values.
- **Server sanitizes** even though settings are "harmless": saved junk (huge strings, NaN, extra keys) bloats
  profiles and crashes other code later.
- **Client asks for its settings** instead of the server pushing on join → no race with the handler connecting.
- **Buttons, not drag-only sliders**: gamepad and accessibility. Selection starts on the first control
  (`GuiService.SelectedObject`).
- **Other systems read ClientSettings** rather than the menu writing everything → camera/audio/graphics stay the
  single owners of their properties (the FOV line in `apply` is only for projects without a custom camera).

## Code
<!-- code: examples/settings/ReplicatedStorage/Settings/Schema.luau -->
```luau
-- file: examples/settings/ReplicatedStorage/Settings/Schema.luau
--!strict
-- Player settings schema: the single definition used by the menu (rows), the client (apply) and the server
-- (sanitize before saving). Pure → CLI-tested (examples/tests/settings.spec.luau).
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Def =
	{ id: string, label: string, kind: "range", default: number, min: number, max: number, step: number }
	| { id: string, label: string, kind: "toggle", default: boolean }
	| { id: string, label: string, kind: "choice", default: string, options: { string } }
export type Values = { [string]: number | boolean | string }

local Schema = {}

Schema.defs = {
	{ id = "MasterVolume", label = "Master volume", kind = "range", default = 0.8, min = 0, max = 1, step = 0.1 },
	{ id = "MusicVolume", label = "Music", kind = "range", default = 0.6, min = 0, max = 1, step = 0.1 },
	{ id = "FieldOfView", label = "Field of view", kind = "range", default = 70, min = 70, max = 100, step = 5 },
	{ id = "CameraShake", label = "Camera shake", kind = "range", default = 1, min = 0, max = 1, step = 0.25 },
	{ id = "ViewBobbing", label = "View bobbing", kind = "toggle", default = true },
	{ id = "Subtitles", label = "Subtitles", kind = "toggle", default = true },
	{ id = "GraphicsTier", label = "Graphics", kind = "choice", default = "Auto", options = { "Auto", "Low", "Medium", "High", "Ultra" } },
} :: { Def }

function Schema.defaults(): Values
	local out: Values = {}
	for _, def in Schema.defs do
		out[def.id] = def.default
	end
	return out
end

-- Untrusted input (client payload or old saved data) → complete, valid settings. Unknown keys are dropped.
function Schema.sanitize(raw: unknown): Values
	local out = Schema.defaults()
	if type(raw) ~= "table" then
		return out
	end
	local t = raw :: { [any]: any }
	for _, def in Schema.defs do
		local v = t[def.id]
		if def.kind == "range" then
			if type(v) == "number" and v == v then
				local snapped = def.min + math.floor((math.clamp(v, def.min, def.max) - def.min) / def.step + 0.5) * def.step
				out[def.id] = math.clamp(snapped, def.min, def.max)
			end
		elseif def.kind == "toggle" then
			if type(v) == "boolean" then
				out[def.id] = v
			end
		elseif def.kind == "choice" then
			if type(v) == "string" and table.find(def.options, v) then
				out[def.id] = v
			end
		end
	end
	return out
end

return Schema
```
<!-- /code -->

<!-- code: examples/settings/ReplicatedStorage/Settings/ClientSettings.luau -->
```luau
-- file: examples/settings/ReplicatedStorage/Settings/ClientSettings.luau
--!strict
-- Client-side settings state other client scripts read (camera, audio, graphics tier). Client-only module.
-- Status: TYPECHECKED. Not run in Studio.
local Schema = require(script.Parent.Schema)
local Signal = require(script.Parent.Parent.Lib.Signal)

local ClientSettings = {}
ClientSettings.changed = Signal.new() :: Signal.Signal<string, any>

local values = Schema.defaults()

function ClientSettings.get(id: string): any
	return values[id]
end

function ClientSettings.all(): Schema.Values
	return table.clone(values)
end

-- Replace everything (e.g. when the server sends saved settings). Fires `changed` per changed key.
function ClientSettings.load(raw: unknown)
	local clean = Schema.sanitize(raw)
	for id, v in clean do
		if values[id] ~= v then
			values[id] = v
			ClientSettings.changed:fire(id, v)
		end
	end
end

function ClientSettings.set(id: string, value: any)
	local merged = table.clone(values)
	merged[id] = value
	ClientSettings.load(merged) -- goes through sanitize: the UI can't set invalid values either
end

return ClientSettings
```
<!-- /code -->

<!-- code: examples/settings/ServerScriptService/SettingsServer.server.luau -->
```luau
-- file: examples/settings/ServerScriptService/SettingsServer.server.luau
--!strict
-- Receives settings from clients (rate-limited, sanitized) and hands them to persistence; sends saved settings on join.
-- Persistence hooks default to memory; with the save-system recipe use profile.settings (the template has it):
--   getSaved = function(p) local prof = Profiles.get(p); return prof and prof.settings end
--   save = function(p, s) local prof = Profiles.get(p); if prof then prof.settings = s end end
-- Status: TYPECHECKED (schema CLI-EXECUTED). Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
local Schema = require(ReplicatedStorage.Settings.Schema)

local memory: { [Player]: Schema.Values } = {}
local hooks = {
	getSaved = function(player: Player): unknown
		return memory[player]
	end,
	save = function(player: Player, settings: Schema.Values)
		memory[player] = settings
	end,
}

local folder = Instance.new("Folder")
folder.Name = "SettingsRemotes"
local saveRemote = Instance.new("RemoteEvent")
saveRemote.Name = "SaveSettings"
saveRemote.Parent = folder
local syncRemote = Instance.new("RemoteEvent")
syncRemote.Name = "SettingsSync"
syncRemote.Parent = folder
folder.Parent = ReplicatedStorage

local limiter = TokenBucket.new({ Save = { capacity = 3, rate = 0.5 } }) -- the client debounces; this is a flood guard

saveRemote.OnServerEvent:Connect(function(player: Player, raw: unknown)
	if not limiter:allow(player, "Save", os.clock()) then
		return
	end
	hooks.save(player, Schema.sanitize(raw))
end)

-- The client asks once its UI is ready (avoids firing before its handler is connected).
syncRemote.OnServerEvent:Connect(function(player: Player)
	if limiter:allow(player, "Save", os.clock()) then
		syncRemote:FireClient(player, Schema.sanitize(hooks.getSaved(player)))
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	memory[player] = nil
	limiter:forget(player)
end)
```
<!-- /code -->

<!-- code: examples/settings/StarterPlayer/StarterPlayerScripts/SettingsClient.client.luau -->
```luau
-- file: examples/settings/StarterPlayer/StarterPlayerScripts/SettingsClient.client.luau
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
```
<!-- /code -->

## Accessibility checklist
- Respect `GuiService.ReducedMotionEnabled` as the default for camera shake/bobbing (the bodycam recipe does);
  `PreferredTextSize` and `PreferredTransparency` for text size and panel opacity.
- Subtitles toggle drives your caption system; show captions for important sounds by default.
- Every control reachable with a gamepad; visible selection; no hover-only information.
- Test in Studio's Device Emulator (phone portrait/landscape) and with a controller.

## How to test
- Change values, rejoin (with the save system wired) → values restored.
- Exploit: `SaveSettings:FireServer({FieldOfView = 1e9, Admin = true, GraphicsTier = string.rep("x", 1e5)})` →
  stored as clamped/defaults, no extra keys.
- Spam +/− → one save after you stop (check the server log or a temporary print).

Sources: cd:ui/index, cd:ui/position-and-size, cd:reference/engine/classes/GuiService,
cd:reference/engine/classes/ContextActionService, cd:production/publishing/accessibility, cd:input/gamepad.

## Accessibility integration obligations
Offer a flash-reduction preference and have the owning effect controller suppress
flashing bursts when enabled. This recipe's current schema does not implement that
controller; wire and verify it before claiming flash reduction is supported.
Use colour-blind-safe cues: pair colour with text, shape, icons, or patterns so colour
is never the sole carrier of information. Verify selected, disabled, and warning states.
Camera shake and bobbing should each have a user-controlled intensity slider where
those effects are present; the included ViewBobbing toggle is a minimal on/off example,
not an implementation of a bob-intensity slider.
