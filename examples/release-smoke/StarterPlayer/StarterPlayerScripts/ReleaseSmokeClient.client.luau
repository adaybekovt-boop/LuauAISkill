--!strict
-- Test-only client driver. NOT RUN. Loaded only into the disposable release-smoke place.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer :: Player

local function child(parent: Instance, name: string): Instance
	local found = parent:WaitForChild(name, 20)
	assert(found, "missing " .. name)
	return found
end
local function waitFor(label: string, predicate: () -> boolean, seconds: number?)
	local deadline = os.clock() + (seconds or 8)
	repeat
		if predicate() then return end
		task.wait(0.05)
	until os.clock() >= deadline
	error("client timeout: " .. label)
end
local function load(parent: Instance, name: string): any
	local source = child(parent, name)
	assert(source:IsA("ModuleScript"), name .. " must be a module")
	local loadModule: (ModuleScript) -> any = require :: any
	return loadModule(source)
end
local function humanoid(): Humanoid
	waitFor("character", function()
		return player.Character ~= nil and player.Character:FindFirstChildOfClass("Humanoid") ~= nil
	end)
	return (player.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
end
local function remote(folder: string, name: string): RemoteEvent
	return child(child(ReplicatedStorage, folder), name) :: RemoteEvent
end

-- The server doesn't create control until explicitly enabled. A timeout is a setup error, never a pass.
local control = child(ReplicatedStorage, "ReleaseSmokeControl") :: RemoteEvent
local inventorySnapshot: any = nil
local inventoryConnection: RBXScriptConnection? = nil
local movementBinding: InputBinding? = nil
local handlers: { [string]: (any) -> any } = {}
handlers["network-burst"] = function(_data: any): any
	local request = child(child(ReplicatedStorage, "Remotes"), "ReleaseSmokeBudget") :: RemoteFunction
	local invalid = request:InvokeServer("not a number") == nil
	local accepted, limited = 0, 0
	for _ = 1, 6 do
		local value = request:InvokeServer(7)
		if value == 14 then accepted += 1 elseif value == nil then limited += 1 end
	end
	return { invalid = invalid, accepted = accepted, limited = limited }
end
handlers["inventory-listen"] = function(_data: any): any
	if inventoryConnection then inventoryConnection:Disconnect() end
	inventoryConnection = remote("Remotes", "InventorySync").OnClientEvent:Connect(function(value: unknown)
		inventorySnapshot = value
	end)
	return true
end
handlers["inventory-action"] = function(data: any): any
	remote("Remotes", "InventoryAction"):FireServer(table.unpack(data))
	return true
end
handlers["inventory-snapshot"] = function(_data: any): any
	waitFor("inventory sync", function() return inventorySnapshot ~= nil and inventorySnapshot[1].c == 1 end)
	return inventorySnapshot
end
handlers["prompt"] = function(name: any): any
	local target = child(Workspace, name)
	local prompt = target:FindFirstChildOfClass("ProximityPrompt")
	assert(prompt, "target has no prompt")
	prompt:InputHoldBegin()
	task.wait(0.15)
	prompt:InputHoldEnd()
	return true
end
handlers["hitscan"] = function(data: any): any
	remote("CombatRemotes", "HitscanFire"):FireServer(data.origin, data.direction)
	return true
end
handlers["reload"] = function(_data: any): any
	remote("CombatRemotes", "Reload"):FireServer()
	return true
end
handlers["round-state"] = function(_data: any): any
	local info = child(ReplicatedStorage, "Round")
	waitFor("replicated round", function() return info:GetAttribute("Phase") == "InRound" end)
	return { phase = info:GetAttribute("Phase"), endsAt = info:GetAttribute("EndsAt") }
end

local function scriptedBinding(name: string): InputBinding
	local context = child(child(ReplicatedStorage, "Inputs"), "PlayContext") :: InputContext
	local action = child(context, name) :: InputAction
	assert(context.Enabled and action.Enabled, "recipe input context/action is disabled")
	local binding = Instance.new("InputBinding")
	binding.Name, binding.Type = "ReleaseSmokeBinding", Enum.InputBindingType.Scriptable
	binding.Parent = action
	return binding
end
handlers["movement"] = function(_data: any): any
	local hum = humanoid()
	local model = player.Character :: Model
	local crouch = scriptedBinding("Crouch")
	local sprint = scriptedBinding("Sprint")
	crouch:Fire(true); crouch:Fire(false)
	waitFor("crouch", function() return model:GetAttribute("Crouching") == true end)
	local crouchSpeed = hum.WalkSpeed
	crouch:Fire(true); crouch:Fire(false)
	waitFor("standing", function() return model:GetAttribute("Crouching") == false end)
	local standSpeed = hum.WalkSpeed
	crouch:Destroy()
	movementBinding = sprint
	-- Scripted movement/input smoke, not physical keyboard/touch/controller coverage.
	RunService:BindToRenderStep("ReleaseSmokeMove", Enum.RenderPriority.Last.Value, function()
		local h = (player.Character :: Model):FindFirstChildOfClass("Humanoid")
		local root = h and h.RootPart
		if h and root then h:Move(root.CFrame.LookVector, false) end
	end)
	sprint:Fire(true)
	waitFor("sprinting", function() return model:GetAttribute("Sprinting") == true end)
	local speed = hum.WalkSpeed
	task.wait(1.3)
	return { actions = true, crouch = true, crouchSpeed = crouchSpeed, stand = true, standSpeed = standSpeed,
		sprint = true, sprintSpeed = speed }
end
handlers["movement-stop"] = function(_data: any): any
	if movementBinding then
		movementBinding:Fire(false)
		movementBinding:Destroy()
		movementBinding = nil
	end
	RunService:UnbindFromRenderStep("ReleaseSmokeMove")
	humanoid():Move(Vector3.zero, false)
	return true
end
handlers["movement-reset"] = function(_data: any): any
	local hum = humanoid()
	waitFor("movement reset", function()
		local model = player.Character :: Model
		return model:GetAttribute("Sprinting") == false and model:GetAttribute("Crouching") == false
	end)
	return hum.WalkSpeed == 16
end
handlers["settings"] = function(_data: any): any
	local menu = child(child(player, "PlayerGui"), "SettingsMenu") :: ScreenGui
	local controls = 0
	for _, item in menu:GetDescendants() do
		if item:IsA("GuiButton") and item.Selectable then controls += 1 end
	end
	menu.Enabled = true -- exposes the actual recipe menu for optional screenshots; does not synthesize a button click
	local settings = load(child(ReplicatedStorage, "Settings"), "ClientSettings")
	settings.set("FieldOfView", 999)
	local sanitized = settings.get("FieldOfView") == 100
	settings.set("FieldOfView", 85)
	waitFor("camera FOV", function() return Workspace.CurrentCamera ~= nil and Workspace.CurrentCamera.FieldOfView == 85 end)
	task.wait(2.5) -- real menu debounce (1s), replication, then limiter headroom
	local received: any = nil
	local sync = remote("SettingsRemotes", "SettingsSync")
	local connection = sync.OnClientEvent:Connect(function(value: unknown) received = value end)
	sync:FireServer()
	local ok, err = pcall(function() waitFor("saved settings sync", function() return received ~= nil end) end)
	connection:Disconnect()
	assert(ok, tostring(err))
	return { controls = controls, sanitized = sanitized, fov = (Workspace.CurrentCamera :: Camera).FieldOfView,
		roundtrip = received.FieldOfView == 85 }
end
handlers["settings-after-respawn"] = function(_data: any): any
	humanoid()
	local gui = child(player, "PlayerGui")
	local count = 0
	for _, candidate in gui:GetChildren() do if candidate.Name == "SettingsMenu" then count += 1 end end
	local menu = gui:FindFirstChild("SettingsMenu")
	return count == 1 and menu ~= nil and menu:IsA("ScreenGui") and not menu.ResetOnSpawn
end

local function near(actual: any, expected: any): boolean
	if typeof(expected) == "Color3" then
		return typeof(actual) == "Color3" and math.abs(actual.R - expected.R) < 0.015
			and math.abs(actual.G - expected.G) < 0.015 and math.abs(actual.B - expected.B) < 0.015
	elseif type(expected) == "number" then
		return type(actual) == "number" and math.abs(actual - expected) < 0.02
	end
	return actual == expected
end
handlers["lighting"] = function(name: any): any
	local presets = load(ReplicatedStorage, "LightingPresets")
	local preset = presets[name]
	assert(preset, "unknown preset")
	local camera = Workspace.CurrentCamera :: Camera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 9, 25), Vector3.new(0, 4, -8))
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	assert(atmosphere, "missing Atmosphere")
	local groups: { { instance: Instance, props: any } } = {
		{ instance = Lighting, props = preset.lighting },
		{ instance = atmosphere, props = preset.atmosphere },
		{ instance = child(Lighting, "LC_Grade"), props = preset.colorCorrection },
		{ instance = child(Lighting, "LC_Bloom"), props = preset.bloom },
	}
	local rays = child(Lighting, "LC_SunRays") :: SunRaysEffect
	if preset.sunRays then table.insert(groups, { instance = rays :: Instance, props = preset.sunRays }) end
	local mismatch = ""
	waitFor("lighting blend " .. name, function()
		if rays.Enabled ~= (preset.sunRays ~= nil) then mismatch = "SunRays.Enabled"; return false end
		for _, group in groups do
			for property, expected in group.props do
				if not near((group.instance :: any)[property], expected) then
					mismatch = group.instance.ClassName .. "." .. property
					return false
				end
			end
		end
		return true
	end, 8)
	return { matched = true, detail = "all declared properties match; last transition: " .. mismatch }
end
handlers["lighting-counts"] = function(_data: any): any
	for _, name in { "LC_Grade", "LC_Bloom", "LC_SunRays" } do
		local count = 0
		for _, instance in Lighting:GetChildren() do if instance.Name == name then count += 1 end end
		if count ~= 1 then return false end
	end
	return true
end

control.OnClientEvent:Connect(function(id: string, action: string, data: any)
	local ok, value = xpcall(function(): any
		local handler = handlers[action]
		assert(handler, "unknown smoke action: " .. action)
		return handler(data)
	end, function(err: any): string return debug.traceback(tostring(err)) end)
	control:FireServer(id, if ok then { ok = true, value = value } else { ok = false, error = value })
end)
control:FireServer("ready")
