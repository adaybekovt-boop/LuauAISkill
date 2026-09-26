--!strict
-- Camera "looks": Bodycam, CCTV, VHS — post effects parented to the CAMERA (local to this player) + a UI overlay.
-- What Roblox can do: colour grade, contrast, blur, bloom, retro tonemapping, UI overlays (vignette, text, your own
-- grain/scanline images), camera motion (bodycam recipe). What it can't: lens distortion, chromatic aberration,
-- custom shaders. Grain/scanlines need images YOU upload: set StringValue ReplicatedStorage.CameraLookAssets.Grain /
-- .Scanlines to "rbxassetid://<id>" — no asset ids are hard-coded here. K cycles looks (demo binding).
-- Status: TYPECHECKED. Not run in Studio.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Look = "None" | "Bodycam" | "CCTV" | "VHS"
local ORDER: { Look } = { "None", "Bodycam", "CCTV", "VHS" }

type LookDef = { cc: { [string]: any }, blur: number, retro: boolean, vignette: number, label: string }
local LOOKS: { [string]: LookDef } = {
	Bodycam = { cc = { Contrast = 0.15, Saturation = -0.15, TintColor = Color3.fromRGB(240, 245, 255), Brightness = 0 }, blur = 0, retro = false, vignette = 0.35, label = "BODY CAM 01" },
	CCTV = { cc = { Contrast = 0.25, Saturation = -1, TintColor = Color3.fromRGB(225, 255, 230), Brightness = 0.02 }, blur = 1.5, retro = false, vignette = 0.5, label = "CAM 03" },
	VHS = { cc = { Contrast = -0.05, Saturation = 0.1, TintColor = Color3.fromRGB(255, 240, 235), Brightness = 0.02 }, blur = 2, retro = true, vignette = 0.3, label = "PLAY ▶" },
}

local player = Players.LocalPlayer :: Player
local current: Look = "None"
local cc: ColorCorrectionEffect? = nil
local blur: BlurEffect? = nil
local grading: ColorGradingEffect? = nil

-- Overlay UI --------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "CameraLookOverlay"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = -1 -- under gameplay UI
gui.Enabled = false

local edges: { Frame } = {}
local function edge(anchor: Vector2, size: UDim2, rotation: number)
	local f = Instance.new("Frame")
	f.AnchorPoint = anchor
	f.Position = UDim2.fromScale(anchor.X, anchor.Y)
	f.Size = size
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation -- transparent toward the screen centre
	gradient.Transparency = NumberSequence.new(0, 1)
	gradient.Parent = f
	f.Parent = gui
	table.insert(edges, f)
end
edge(Vector2.new(0, 0.5), UDim2.fromScale(0.25, 1), 0) -- left
edge(Vector2.new(1, 0.5), UDim2.fromScale(0.25, 1), 180) -- right
edge(Vector2.new(0.5, 0), UDim2.fromScale(1, 0.25), 90) -- top
edge(Vector2.new(0.5, 1), UDim2.fromScale(1, 0.25), 270) -- bottom

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Position = UDim2.fromScale(0.04, 0.05)
label.Size = UDim2.fromScale(0.5, 0.05)
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextScaled = true
label.FontFace = Font.fromEnum(Enum.Font.RobotoMono)
label.TextColor3 = Color3.fromRGB(235, 235, 235)
label.TextStrokeTransparency = 0.6
label.Parent = gui

local assets = ReplicatedStorage:FindFirstChild("CameraLookAssets")
local grain: ImageLabel? = nil
local grainId = assets and assets:FindFirstChild("Grain")
if grainId and grainId:IsA("StringValue") and grainId.Value ~= "" then
	local g = Instance.new("ImageLabel")
	g.Image = grainId.Value
	g.BackgroundTransparency = 1
	g.ImageTransparency = 0.85
	g.Size = UDim2.fromScale(1, 1)
	g.ScaleType = Enum.ScaleType.Tile
	g.TileSize = UDim2.fromOffset(256, 256)
	g.Parent = gui
	grain = g
end
gui.Parent = player:WaitForChild("PlayerGui")

-- Apply -------------------------------------------------------------------
local function clear()
	for _, e in { cc, blur, grading } :: { Instance? } do
		if e then
			e:Destroy()
		end
	end
	cc, blur, grading = nil, nil, nil
	gui.Enabled = false
end

local function setLook(look: Look)
	current = look
	clear()
	local def = LOOKS[look]
	local camera = Workspace.CurrentCamera
	if not def or not camera then
		return
	end
	local c = Instance.new("ColorCorrectionEffect")
	for prop, value in def.cc do
		(c :: any)[prop] = value
	end
	c.Parent = camera -- in Camera = only this player sees it
	cc = c
	if def.blur > 0 then
		local b = Instance.new("BlurEffect")
		b.Size = def.blur
		b.Parent = camera
		blur = b
	end
	if def.retro then
		local g = Instance.new("ColorGradingEffect")
		g.TonemapperPreset = Enum.TonemapperPreset.Retro
		g.Parent = camera
		grading = g
	end
	for _, f in edges do
		f.BackgroundTransparency = 1 - def.vignette
	end
	gui.Enabled = true
end

ContextActionService:BindAction("CycleCameraLook", function(_n: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		local i = table.find(ORDER, current) or 1
		setLook(ORDER[i % #ORDER + 1])
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.K)

-- Overlay text + grain jitter (10 Hz is enough and cheaper than every frame).
local accumulator = 0
local recBlink = false
RunService.PreRender:Connect(function(dt: number)
	if current == "None" then
		return
	end
	accumulator += dt
	if accumulator < 0.1 then
		return
	end
	accumulator = 0
	local def = LOOKS[current]
	local stamp = os.date("%d.%m.%Y  %H:%M:%S")
	if current == "Bodycam" then
		recBlink = not recBlink
		label.Text = `{if recBlink then "● REC" else "      "}  {stamp}  {def.label}`
	else
		label.Text = `{def.label}  {stamp}`
	end
	if grain then
		grain.Position = UDim2.fromOffset(math.random(-64, 0), math.random(-64, 0)) -- cheap animated grain
	end
end)
