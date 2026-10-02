# Recipe: procedural Backrooms (infinite, deterministic, connected, budgeted)

## When NOT to use
Do not use random room placement without navigation, overlap, and reproducibility checks.

Evidence: layout CLI-EXECUTED (`examples/tests/procgen.spec.luau`: determinism, 121 chunks fully connected,
border agreement on 49 chunk pairs, light mix) · builder TYPECHECKED · **not run in Studio**.
Chapters: [procedural generation](../../handbook/roblox/12-procedural-generation.md), [streaming](../../handbook/roblox/10-streaming.md).
Look: [Backrooms fluorescent office](../graphics/backrooms-fluorescent-office.md), [flickering fluorescent](../graphics/flickering-fluorescent.md).

## Architecture
```text
Layout.chunk(seed, cx, cz, params)   pure data, same result on any machine, any order
   internal edges: randomized Kruskal spanning tree (all 64 cells connected) + 35 % extra openings (loops)
   border edges: hash of the SHARED edge → both chunks agree; one forced opening per border → world connected
   lights every 2 cells: ~86 % on, ~8 % dead, ~6 % flickering · pillars in open 2×2 areas
BackroomsServer
   start: build 3×3 chunks around the origin (CharacterAutoLoads off until the floor exists), spawn at cell (0,0)
   every 1 s: chunks within 2 of any player → build (≤ 120 parts per frame); beyond 3 → destroy
   build: floor + ceiling slabs, wall runs merged along each line, pillars, neon panels,
          SurfaceLight on every other lit panel (Shadows off), flicker panels tagged "FlickerLight"
Clients: StreamingEnabled delivers nearby chunks; flicker/ambience scripts are client-side cosmetics
```
Why:
- **Data first**: connectivity is proven on tables (BFS) — no raycasts or physics to "check" a maze.
- **Hash per shared edge** is what makes chunked generation seamless without storing anything.
- **Deterministic from a seed**: a bug report with the seed reproduces the exact layout. `Layout.VERSION` must
  change whenever generation changes.
- **Merged walls**: ~20–30 wall parts per chunk instead of ~100 single-cell walls (fewer parts = less memory,
  replication and draw calls).
- **Budgeted building**: generation never spikes the server frame; players can't outrun it at 2-chunk radius
  (96 studs per chunk, 192 studs ahead).
- **Sealed ceiling + no sun leaking in** is part of the look (see the graphics recipe).

## Code
<!-- code: examples/procgen/ReplicatedStorage/Procgen/Layout.luau -->
```luau
-- file: examples/procgen/ReplicatedStorage/Procgen/Layout.luau
--!strict
-- Backrooms-style chunk layout: a grid of cells with walls on cell edges. Pure and deterministic from
-- (seed, chunk coordinates) → any server/client/CLI produces the same layout; chunks generate in any order.
--   1. every internal edge starts closed; a randomized Kruskal spanning tree opens enough edges to connect all cells
--   2. extra edges open with `loopChance` (loops, open areas — Backrooms are not a perfect maze)
--   3. border edges are decided by a hash of the SHARED edge, so neighbouring chunks agree; each border has at
--      least one guaranteed opening → the infinite world stays connected
--   4. ceiling lights on a regular grid; a hash marks some broken (off) or flickering
-- Status: TYPECHECKED + CLI-EXECUTED (examples/tests/procgen.spec.luau).
local Hash = require("../Lib/Hash") -- require-by-string: resolves the same way in Roblox and the Luau CLI

export type Light = { x: number, z: number, state: "on" | "off" | "flicker" }
export type Chunk = {
	cx: number,
	cz: number,
	size: number,
	openEast: { [number]: boolean }, -- key = z * size + x; edge between (x, z) and (x + 1, z); x = size-1 → border
	openSouth: { [number]: boolean }, -- edge between (x, z) and (x, z + 1); z = size-1 → border
	openWestBorder: { [number]: boolean }, -- by z: edge between this chunk's x = 0 and the west neighbour
	openNorthBorder: { [number]: boolean }, -- by x
	lights: { Light },
	pillars: { { x: number, z: number } },
}
export type Params = { size: number, loopChance: number, borderChance: number, lightSpacing: number, pillarChance: number }

local Layout = {}
Layout.VERSION = 1 -- bump when generation changes (saved seeds must be regenerated identically)

local SALT_TREE, SALT_LOOP, SALT_BORDER_E, SALT_BORDER_S, SALT_FORCE, SALT_LIGHT, SALT_PILLAR = 11, 12, 13, 14, 15, 16, 17

-- Deterministic uniform [0,1) for (seed, salt, a, b).
local function u(seed: number, salt: number, a: number, b: number): number
	return Hash.unit(Hash.hash3(seed, salt, 0), a, b)
end

-- Border edge east of global cell column gx (between gx and gx + 1) at row gz: same answer from both chunks.
local function borderOpen(seed: number, p: Params, gx: number, gz: number, salt: number, forcedAt: number, index: number): boolean
	return index == forcedAt or u(seed, salt, gx, gz) < p.borderChance
end

-- The forced opening index on the border line east of chunk column cx (for chunk row cz).
local function forcedIndex(seed: number, p: Params, a: number, b: number, salt: number): number
	return math.floor(u(seed, SALT_FORCE + salt, a, b) * p.size)
end

function Layout.chunk(seed: number, cx: number, cz: number, p: Params): Chunk
	local n = p.size
	local chunk: Chunk = {
		cx = cx,
		cz = cz,
		size = n,
		openEast = {},
		openSouth = {},
		openWestBorder = {},
		openNorthBorder = {},
		lights = {},
		pillars = {},
	}
	local ox, oz = cx * n, cz * n -- global cell origin
	-- 1. spanning tree over internal edges (randomized Kruskal with union-find).
	local parent: { [number]: number } = {}
	local function find(i: number): number
		while parent[i] ~= nil and parent[i] ~= i do
			local grand = parent[parent[i]] or parent[i]
			parent[i] = grand
			i = grand
		end
		return i
	end
	type Edge = { key: number, east: boolean, a: number, b: number, w: number }
	local edges: { Edge } = {}
	for z = 0, n - 1 do
		for x = 0, n - 1 do
			local id = z * n + x
			parent[id] = id
			if x < n - 1 then
				table.insert(edges, { key = id, east = true, a = id, b = id + 1, w = u(seed, SALT_TREE, ox + x, (oz + z) * 2) })
			end
			if z < n - 1 then
				table.insert(edges, { key = id, east = false, a = id, b = id + n, w = u(seed, SALT_TREE, ox + x, (oz + z) * 2 + 1) })
			end
		end
	end
	table.sort(edges, function(e1: Edge, e2: Edge)
		return e1.w < e2.w
	end)
	for _, e in edges do
		local ra, rb = find(e.a), find(e.b)
		local open = ra ~= rb
		if open then
			parent[ra] = rb
		elseif u(seed, SALT_LOOP, e.a + ox * 7919, e.b + oz * 104729) < p.loopChance then
			open = true -- 2. extra openings create loops and wider areas
		end
		if open then
			if e.east then
				chunk.openEast[e.key] = true
			else
				chunk.openSouth[e.key] = true
			end
		end
	end
	-- 3. borders: east/south lines belong to this chunk, west/north lines are computed exactly like the neighbour's.
	local forcedE = forcedIndex(seed, p, cx, cz, 0)
	local forcedS = forcedIndex(seed, p, cx, cz, 1)
	local forcedW = forcedIndex(seed, p, cx - 1, cz, 0)
	local forcedN = forcedIndex(seed, p, cx, cz - 1, 1)
	for i = 0, n - 1 do
		if borderOpen(seed, p, ox + n - 1, oz + i, SALT_BORDER_E, forcedE, i) then
			chunk.openEast[i * n + (n - 1)] = true
		end
		if borderOpen(seed, p, ox + i, oz + n - 1, SALT_BORDER_S, forcedS, i) then
			chunk.openSouth[(n - 1) * n + i] = true
		end
		chunk.openWestBorder[i] = borderOpen(seed, p, ox - 1, oz + i, SALT_BORDER_E, forcedW, i)
		chunk.openNorthBorder[i] = borderOpen(seed, p, ox + i, oz - 1, SALT_BORDER_S, forcedN, i)
	end
	-- 4. lights on a grid; ~8 % broken, ~6 % flickering. Pillars only in fully open 2×2 areas.
	for z = 0, n - 1, p.lightSpacing do
		for x = 0, n - 1, p.lightSpacing do
			local r = u(seed, SALT_LIGHT, ox + x, oz + z)
			local light: Light = { x = x, z = z, state = if r < 0.08 then "off" elseif r < 0.14 then "flicker" else "on" }
			table.insert(chunk.lights, light)
		end
	end
	for z = 0, n - 2 do
		for x = 0, n - 2 do
			local id = z * n + x
			local open2x2 = chunk.openEast[id] and chunk.openSouth[id] and chunk.openEast[id + n] and chunk.openSouth[id + 1]
			if open2x2 and u(seed, SALT_PILLAR, ox + x, oz + z) < p.pillarChance then
				table.insert(chunk.pillars, { x = x, z = z }) -- pillar at the shared corner of the 2×2 block
			end
		end
	end
	return chunk
end

-- All cells of the chunk reachable from cell 0 using internal edges only (guaranteed by the spanning tree).
function Layout.fullyConnected(c: Chunk): boolean
	local n = c.size
	local seen = { [0] = true }
	local queue = { 0 }
	local head, count = 1, 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		local x, z = id % n, id // n
		local neighbours = {}
		if x < n - 1 and c.openEast[id] then
			table.insert(neighbours, id + 1)
		end
		if x > 0 and c.openEast[id - 1] then
			table.insert(neighbours, id - 1)
		end
		if z < n - 1 and c.openSouth[id] then
			table.insert(neighbours, id + n)
		end
		if z > 0 and c.openSouth[id - n] then
			table.insert(neighbours, id - n)
		end
		for _, nb in neighbours do
			if not seen[nb] then
				seen[nb] = true
				count += 1
				table.insert(queue, nb)
			end
		end
	end
	return count == n * n
end

return table.freeze(Layout)
```
<!-- /code -->

<!-- code: examples/procgen/ServerScriptService/BackroomsServer.server.luau -->
```luau
-- file: examples/procgen/ServerScriptService/BackroomsServer.server.luau
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
```
<!-- /code -->
`Layout` requires `Lib/Hash` by string (`require("../Lib/Hash")`), which resolves identically in Roblox
(`script.Parent.Parent.Lib.Hash`) and in the Luau CLI — that's why the same file is unit-tested outside Studio.

## Setup
- Enable `Workspace.StreamingEnabled` (Studio property). Keep `StreamingTargetRadius` ≥ the visible distance you
  want; fog hides the edge (see the graphics recipe).
- Replace the procedural parts with modeled wall/panel templates (`ServerStorage.Backrooms.*`) once the layout is
  right — cloning a template costs about the same as creating a part.

## How to test
- CLI: `python tools/check_code.py --examples-only` (links the lib, runs all specs) or run the spec directly after
  copying `examples/lib/ReplicatedStorage/Lib` into `examples/procgen/ReplicatedStorage/`.
- Studio: walk in one direction for 2 minutes → no holes, no sealed dead-end chunks, server frame time flat
  (MicroProfiler: chunk builds spread over frames), part count stable (old chunks unloaded).
- Two players far apart → two independent loaded regions.
- Same seed on two servers → identical layouts (compare screenshots at the same coordinates).

## Variations
- Levels/biomes: pick params and templates per region with a low-frequency noise of chunk coordinates.
- Rare rooms: with probability p per chunk, replace a 3×3 cell block with a handcrafted room template whose doors
  sit on cell edges that the layout keeps open.
- Entities: spawn NPCs per chunk from the chunk hash so they are deterministic too ([NPC patrol](npc-patrol.md)).
- Save progress: store the seed + discovered chunk keys, never the geometry.

Sources: cd:workspace/streaming/index, cd:reference/engine/classes/Workspace, cd:reference/engine/classes/SurfaceLight,
cd:performance-optimization/improve, cd:reference/engine/globals/LuaGlobals.
