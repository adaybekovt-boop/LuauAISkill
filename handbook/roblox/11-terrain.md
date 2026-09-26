# Terrain: voxels, materials, water, procedural terrain

Read when: outdoor worlds, caves, biomes, water, scripted terrain generation.
Related: [procedural generation](12-procedural-generation.md), [materials](../graphics/04-materials-pbr.md),
[streaming](10-streaming.md).

## Facts
- `workspace.Terrain` (class `Terrain`, a BasePart) stores a voxel grid: **4×4×4-stud voxels**, each with a
  material and occupancy (0–1), plus optional water occupancy channels. Region operations snap to the voxel grid.
- Terrain materials: Asphalt, Basalt, Brick, Cobblestone, Concrete, CrackedLava, Glacier, Grass, Ground, Ice,
  LeafyGrass, Limestone, Mud, Pavement, Rock, Salt, Sand, Sandstone, Slate, Snow, Water, WoodPlanks, Air. Custom looks
  via `MaterialVariant` in `MaterialService` ([materials](../graphics/04-materials-pbr.md)); per-material color with
  `Terrain:SetMaterialColor(material, color)`.
- Studio-only (NotScriptable) look settings: `Terrain.Decoration` (animated grass on Grass), `GrassLength`,
  `MaterialColors`. Scriptable water look: `WaterColor`, `WaterReflectance`, `WaterTransparency`,
  `WaterWaveSize`, `WaterWaveSpeed`. Grass sway follows `Workspace.GlobalWind` and respects Reduce Motion.
- Terrain streams like parts; distant terrain can show low-detail imposters (visual only).

## Scripting API (stable)
| Operation | API |
|---|---|
| Fill primitives | `FillBlock(cframe, size, material)`, `FillBall(center, r, material)`, `FillCylinder(cf, h, r, mat)`, `FillWedge(cf, size, mat)`, `FillRegion(region3, 4, mat)` |
| Remove | fill with `Enum.Material.Air` |
| Bulk read/write | `ReadVoxels(region, 4)` / `WriteVoxels(region, 4, materials, occupancies)` (3D arrays `[x][y][z]`) |
| Channel read/write (incl. water) | `ReadVoxelChannels(region, 4, {"SolidMaterial","SolidOccupancy","LiquidOccupancy"})` / `WriteVoxelChannels` |
| Replace material | `ReplaceMaterial(region, 4, from, to)` |
| Copy/paste | `CopyRegion(region3int16)` → `TerrainRegion`, `PasteRegion(tr, corner, pasteEmpty)` |
| Clear | `Terrain:Clear()` |
`Region3` for voxel ops must be aligned: `region:ExpandToGrid(4)`. Methods ending in `_beta`
(`ModifyVoxelsAsync_beta`, `IterateVoxelsAsync_beta`, …) are beta — don't build production on them without
checking status.

## Procedural terrain pipeline (server, at startup or chunk on demand)
1. Seeded height function: layered `math.noise` octaves (fBm) with offsets derived from the seed (noise returns 0 at
   integer coordinates — scale inputs by a non-integer frequency and add a fractional offset).
2. Biome selection from two low-frequency noise fields (temperature, moisture) → material + height modifiers.
3. Write per chunk (e.g. 64×64 studs = 16×16 voxels columns) with `WriteVoxels` on a pre-sized 3D array — much
   faster than thousands of `FillBlock` calls.
4. Caves: 3D noise threshold (`math.noise(x, y, z) > t`) carving Air after the height pass; keep spawn areas solid.
5. Yield between chunks (time budget) or generate in parallel Actors (compute arrays in parallel, write after
   `task.synchronize()` — terrain writes are not parallel-safe).

```luau
--!strict
local Terrain = workspace.Terrain
local SEED = 1337
local rng = Random.new(SEED)
local ox, oz = rng:NextNumber(0, 10000), rng:NextNumber(0, 10000)

local function height(x: number, z: number): number
	local h, amp, freq = 0, 24, 1 / 180
	for _ = 1, 4 do                                   -- 4 octaves of fBm
		h += math.noise(x * freq + ox, z * freq + oz) * amp
		amp *= 0.5
		freq *= 2
	end
	return 32 + h
end

local function generateChunk(cx: number, cz: number, size: number)
	local voxels = size // 4
	local maxY = 96 // 4
	local mats, occ = {}, {}
	for x = 1, voxels do
		mats[x], occ[x] = {}, {}
		for y = 1, maxY do
			mats[x][y], occ[x][y] = table.create(voxels, Enum.Material.Air), table.create(voxels, 0)
		end
	end
	for x = 1, voxels do
		for z = 1, voxels do
			local wx, wz = cx * size + (x - 0.5) * 4, cz * size + (z - 0.5) * 4
			local top = height(wx, wz)
			for y = 1, maxY do
				local wy = (y - 1) * 4
				if wy < top then
					mats[x][y][z] = if top - wy < 4 then Enum.Material.Grass else Enum.Material.Rock
					occ[x][y][z] = math.clamp((top - wy) / 4, 0, 1)
				end
			end
		end
	end
	local min = Vector3.new(cx * size, 0, cz * size)
	local region = Region3.new(min, min + Vector3.new(size, 96, size)):ExpandToGrid(4)
	Terrain:WriteVoxels(region, 4, mats, occ)
end

for cx = -2, 1 do
	for cz = -2, 1 do
		generateChunk(cx, cz, 64)
		task.wait() -- spread over frames
	end
end
```

## Performance and design notes
- Terrain is efficient for large natural surfaces compared to thousands of parts, but water surfaces and heavy
  material variety cost rendering; keep water areas intentional.
- Avoid writing terrain every frame; batch.
- Collision follows voxels; very thin terrain features (< 4 studs) are unreliable.
- For stylized/hard-surface levels (interiors, Backrooms) use parts/meshes, not terrain.

Sources: cd:parts/terrain, cd:studio/terrain-editor, cd:reference/engine/classes/Terrain,
cd:reference/engine/datatypes/Region3, cd:environment/global-wind, cd:scripting/multithreading.
