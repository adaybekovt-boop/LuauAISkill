--!strict
-- Infinite Backrooms around players: deterministic chunk layouts (Layout) → instances, built with a per-frame part
-- budget and unloaded when no player is near. The server owns layout/collision; use StreamingEnabled so clients only
-- receive nearby chunks. Flickering lights are tagged "FlickerLight" for the client flicker script
-- (graphics recipe flickering-fluorescent); nothing here animates on the server.
-- Status: TYPECHECKED (layout CLI-EXECUTED). Not run in Studio.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Layout = require(ReplicatedStorage.Procgen.Layout)

local SEED = 20260926 -- log it with bug reports; a new seed per server is `Random.new():NextInteger(1, 2^31)`
local PARAMS: Layout.Params = { size = 8, loopChance = 0.35, borderChance = 0.3, lightSpacing = 2, pillarChance = 0.12 }
local CELL = 12 -- studs per cell
local HEIGHT = 10
local THICK = 1
local LOAD_RADIUS = 2 -- chunks around each player (5×5)
local UNLOAD_RADIUS = 3
local PARTS_PER_FRAME = 120

local WALL_COLOR = Color3.fromRGB(196, 181, 122) -- mono-yellow wallpaper
local FLOOR_COLOR = Color3.fromRGB(150, 128, 82) -- damp carpet
local CEILING_COLOR = Color3.fromRGB(214, 206, 180)
local LIGHT_COLOR = Color3.fromRGB(255, 244, 214) -- slightly warm fluorescent

local folder = Instance.new("Folder")
folder.Name = "Backrooms"
folder.Parent = Workspace

type ChunkState = { model: Model?, building: boolean }
local chunks: { [string]: ChunkState } = {}
local budget = PARTS_PER_FRAME

local function key(cx: number, cz: number): string
	return `{cx},{cz}`
end

-- Yield to the next frame when this frame's part budget is used up (keeps server frame time flat).
local function spend(n: number)
	budget -= n
	while budget <= 0 do
		RunService.Heartbeat:Wait()
	end
end
RunService.Heartbeat:Connect(function()
	budget = PARTS_PER_FRAME
end)

local function part(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	spend(1)
	return p
end

local function build(cx: number, cz: number, state: ChunkState)
	local c = Layout.chunk(SEED, cx, cz, PARAMS)
	local n = c.size
	local origin = Vector3.new(cx * n * CELL, 0, cz * n * CELL)
	local model = Instance.new("Model")
	model.Name = `Chunk_{cx}_{cz}`
	local size = n * CELL
	local center = origin + Vector3.new(size / 2, 0, size / 2)
	part(model, Vector3.new(size, 1, size), CFrame.new(center - Vector3.new(0, 0.5, 0)), FLOOR_COLOR, Enum.Material.Carpet)
	local ceiling = part(model, Vector3.new(size, 1, size), CFrame.new(center + Vector3.new(0, HEIGHT + 0.5, 0)),
		CEILING_COLOR, Enum.Material.Concrete)
	ceiling.CastShadow = true -- keeps sunlight/skylight out: interiors must be sealed

	-- Walls on lines x = i (along Z) from east edges, merged into runs to cut the part count.
	local function wallRun(fromCell: number, toCell: number, line: number, alongZ: boolean)
		local length = (toCell - fromCell + 1) * CELL
		local mid = (fromCell + toCell + 1) / 2 * CELL
		local pos = if alongZ then origin + Vector3.new(line * CELL, HEIGHT / 2, mid)
			else origin + Vector3.new(mid, HEIGHT / 2, line * CELL)
		local sizeV = if alongZ then Vector3.new(THICK, HEIGHT, length + THICK) else Vector3.new(length + THICK, HEIGHT, THICK)
		part(model, sizeV, CFrame.new(pos), WALL_COLOR, Enum.Material.Plaster)
	end
	for x = 0, n - 1 do
		local runStart: number? = nil
		for z = 0, n do
			local closed = z < n and not c.openEast[z * n + x]
			if closed and runStart == nil then
				runStart = z
			elseif not closed and runStart ~= nil then
				wallRun(runStart, z - 1, x + 1, true)
				runStart = nil
			end
		end
	end
	for z = 0, n - 1 do
		local runStart: number? = nil
		for x = 0, n do
			local closed = x < n and not c.openSouth[z * n + x]
			if closed and runStart == nil then
				runStart = x
			elseif not closed and runStart ~= nil then
				wallRun(runStart, x - 1, z + 1, false)
				runStart = nil
			end
		end
	end
	for _, p in c.pillars do
		part(model, Vector3.new(2, HEIGHT, 2), CFrame.new(origin + Vector3.new((p.x + 1) * CELL, HEIGHT / 2, (p.z + 1) * CELL)),
			WALL_COLOR, Enum.Material.Plaster)
	end
	-- Light panels: emissive panels everywhere, but a real light only on every other "on" panel (light count is a
	-- major GPU cost; see the heavy-scene performance recipe).
	for i, l in c.lights do
		local pos = origin + Vector3.new((l.x + 0.5) * CELL, HEIGHT - 0.1, (l.z + 0.5) * CELL)
		local panel = part(model, Vector3.new(2, 0.2, 4), CFrame.new(pos), if l.state == "off" then Color3.fromRGB(90, 90, 85)
			else LIGHT_COLOR, if l.state == "off" then Enum.Material.SmoothPlastic else Enum.Material.Neon)
		panel.CastShadow = false
		if l.state ~= "off" and (i % 2 == 0 or l.state == "flicker") then
			local light = Instance.new("SurfaceLight")
			light.Face = Enum.NormalId.Bottom
			light.Angle = 120
			light.Range = 22
			light.Brightness = 1.4
			light.Color = LIGHT_COLOR
			light.Shadows = false
			light.Parent = panel
		end
		if l.state == "flicker" then
			CollectionService:AddTag(panel, "FlickerLight")
		end
	end
	if not state.building then
		model:Destroy() -- unloaded while building
		return
	end
	model.Parent = folder
	state.model = model
	state.building = false
end

local function wanted(): { [string]: { number } }
	local set = {}
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local span = PARAMS.size * CELL
			local pcx, pcz = math.floor(root.Position.X / span), math.floor(root.Position.Z / span)
			for dx = -UNLOAD_RADIUS, UNLOAD_RADIUS do
				for dz = -UNLOAD_RADIUS, UNLOAD_RADIUS do
					local k = key(pcx + dx, pcz + dz)
					local near = math.max(math.abs(dx), math.abs(dz)) <= LOAD_RADIUS
					local entry = set[k]
					if not entry or (near and entry[3] == 0) then
						set[k] = { pcx + dx, pcz + dz, if near then 1 else 0 }
					end
				end
			end
		end
	end
	return set
end

local function ensureChunk(cx: number, cz: number)
	local k = key(cx, cz)
	if not chunks[k] then
		local state: ChunkState = { model = nil, building = true }
		chunks[k] = state
		task.spawn(build, cx, cz, state)
	end
end

-- Spawn: build the start area first, then let characters load at cell (0, 0).
Players.CharacterAutoLoads = false
for dx = -1, 1 do
	for dz = -1, 1 do
		ensureChunk(dx, dz)
	end
end
while chunks[key(0, 0)].building do
	task.wait()
end
local function spawnAt(character: Model)
	character:PivotTo(CFrame.new(CELL / 2, 4, CELL / 2))
end
local function onPlayer(player: Player)
	player.CharacterAdded:Connect(spawnAt)
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.CharacterAutoLoads = true -- from now on spawns (and respawns) load automatically
for _, player in Players:GetPlayers() do
	if not player.Character then
		task.spawn(player.LoadCharacterAsync, player) -- players who joined while the start area was building
	end
end

while true do
	task.wait(1)
	local want = wanted()
	for _, entry in want do
		if entry[3] == 1 then
			ensureChunk(entry[1], entry[2])
		end
	end
	for k, state in chunks do
		if not want[k] then -- beyond UNLOAD_RADIUS of every player
			chunks[k] = nil
			state.building = false
			if state.model then
				state.model:Destroy()
			end
		end
	end
end
