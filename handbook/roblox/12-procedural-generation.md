# Procedural generation: seeds, layouts, chunks, guarantees

## TL;DR
- Separate deterministic layout from instance creation.
- Use explicit seeds and stable random-number ownership.
- Guarantee navigable connections before decoration.
- Validate overlaps and chunk boundaries.
- Budget instantiation and clean up unloaded chunks.

Read when: Backrooms/liminal mazes, dungeons, roguelike rooms, infinite corridors, scattered props, terrain.
Related: [terrain](11-terrain.md), [streaming](10-streaming.md), [environment art](../graphics/05-environment-art.md),
recipe [procedural Backrooms generator](../../recipes/gameplay/procedural-backrooms.md).

## Principles
1. **Data first, instances last.** Generate a layout (grid/graph of cells, rooms, doors, props) as plain tables,
   validate it (connectivity, overlaps, budgets), then instantiate from templates. Validation on data is cheap
   and deterministic; validation with parts/raycasts is slow.
2. **Deterministic from a seed.** Same seed + same generator version → same world. Use `Random.new(seed)`, never
   `math.random` (global state shared with other scripts) and never `os.time()` inside the generator. Log the seed
   and generator version with every bug report.
3. **Per-chunk seeds** so chunks generate independently and in any order: `chunkSeed = hash(worldSeed, cx, cz)`.
4. **Guarantees are checked, not hoped for**: reachability via BFS/union-find on the cell graph; spawn and exits
   inside the main connected component; minimum corridor width ≥ character width + margin.
5. **Budgets**: max cells, max parts per chunk, time budget per frame; every loop has a bound (no `while true` retry
   loops without an attempt cap).
6. **Server owns gameplay layout**; clients may generate *cosmetic* detail from the same seed (decals, clutter)
   to save bandwidth — only if it doesn't affect collision/gameplay.

## Deterministic RNG and hashing
```luau
--!strict
-- 32-bit integer hash. Multiplication is split into 16-bit halves so every partial product stays below 2^53
-- (a plain h * 0x45d9f3b would exceed double precision and silently round).
local function mul32(a: number, b: number): number
	local aLo, aHi = a % 65536, a // 65536
	local bLo, bHi = b % 65536, b // 65536
	return ((aHi * bLo + aLo * bHi) % 65536 * 65536 + aLo * bLo) % 4294967296
end
local function hash3(a: number, b: number, c: number): number
	local h = bit32.bxor(a, bit32.lrotate(b, 16), bit32.lrotate(c, 8))
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x45d9f3b)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x45d9f3b)
	return bit32.bxor(h, bit32.rshift(h, 16))
end
local WORLD_SEED = 20260926
local function chunkRng(cx: number, cz: number): Random
	return Random.new(hash3(WORLD_SEED % 2^32, cx % 2^32, cz % 2^32))
end
local r = chunkRng(-3, 7)
print(r:NextInteger(1, 100), r:NextNumber())
```
Notes: `Random` sequences are deterministic per seed within Roblox; don't assume they match other languages. Keep
the **order of RNG calls stable** — adding one extra `NextNumber()` early changes everything after it (version
your generator; draw sub-seeds for independent features).

## Noise
`math.noise(x, y?, z?)` (Perlin, ~[-1, 1]; exactly 0 at integer lattice points). Use fractional frequencies and
seed-derived offsets. fBm = sum of octaves (amplitude ×0.5, frequency ×2). Domain warping (noise of noise) breaks
grid-like patterns. Threshold 2D noise for "open area vs wall mass"; 3D noise for caves.

## Layout algorithms (pick by feel)
| Feel | Algorithm | Notes |
|---|---|---|
| Backrooms / liminal office (endless, uniform, repetitive with variation) | **grid of cells** with walls on cell edges; random wall removal + guaranteed spanning tree; occasional "rooms" (merged cells) and pillars | uniform ceiling height, repeating fluorescent grid; see recipe |
| Classic maze (single path feel) | recursive backtracker / randomized Prim / Kruskal (union-find) | perfect maze = tree; add loops by removing extra walls (5–15 %) |
| Dungeon rooms + corridors | BSP partition, or scatter rooms → Delaunay/MST → add some edges back → carve corridors | rooms as templates with door sockets |
| Handcrafted pieces snapped together | **module/socket assembly**: templates with door sockets (Attachments), grow from open sockets, overlap-check AABBs, cap depth | best visual quality; the standard for horror |
| Organic caves | cellular automata on a grid, or 3D noise terrain | flood-fill to keep largest region |
| Content scatter (props, clutter, trees) | Poisson-disk sampling (min distance), with per-surface rules | avoid pure uniform random (clumping) |
| Tile rules / adjacency (WFC-lite) | constraint propagation over tiles with allowed neighbours | expensive; only small grids |

## Guaranteeing navigation
```luau
--!strict
-- Cells indexed by id; edges exist where no wall. Returns set of reachable cells from start.
local function reachable(neighbours: { [number]: { number } }, start: number): { [number]: boolean }
	local seen = { [start] = true }
	local queue = { start }
	local head = 1
	while head <= #queue do                 -- bounded by number of cells
		local cell = queue[head]
		head += 1
		local list = neighbours[cell]
		if list then
			for _, n in list do
				if not seen[n] then
					seen[n] = true
					table.insert(queue, n)
				end
			end
		end
	end
	return seen
end
print(reachable({ [1] = { 2 }, [2] = { 1, 3 }, [3] = { 2 }, [4] = {} }, 1)[3])
```
- After layout: every required cell (spawn, exits, objectives) must be in the reachable set; otherwise carve a
  connection (remove a wall along a shortest path to the main component) or regenerate with the next sub-seed
  (bounded attempts).
- Grid connectivity ≠ walkability: also enforce door width (≥ 4–5 studs for R15), ceiling height (≥ 8 studs; 10–12
  for comfort), step height, and no props blocking the path (keep prop placement out of a "walk mask").
- Optional runtime verification: `PathfindingService:CreatePath({AgentRadius=2, AgentHeight=5})` +
  `ComputeAsync` between spawn and exit on the instantiated chunk (server, occasionally, for QA not per frame).

## Overlap checks
- In data: axis-aligned rectangles/boxes per room/module (rotations in 90° steps keep boxes axis-aligned);
  reject placement if it intersects any existing box (with a small epsilon so touching walls are OK).
- In world (fallback): `workspace:GetPartBoundsInBox(cf, size, overlapParams)` against a folder of placed
  module bounds — slower; use only for irregular content.

## Chunked / infinite generation
- World divided into chunks (e.g. 64×64 or 128×128 studs). Server keeps a set of chunks needed: all chunks within
  R of any player (plus hysteresis ring for unloading). Generate missing chunks with a per-frame time budget;
  unload chunks with no player nearby for N seconds (destroy or pool).
- Chunk borders: decide edge features (doorways across the border) from a **border seed** shared by both chunks
  (`hash(seed, min(c1,c2), max(c1,c2))`) so neighbours agree without generating each other.
- With `StreamingEnabled`, instantiate server-side; clients receive only nearby chunks automatically. Keep chunk
  models `Nonatomic` or `Atomic` depending on client scripts' needs.
- Pool templates (lights, pillars, wall segments) instead of destroying/creating thousands of parts repeatedly.

## Instantiation budget
- Clone prebuilt templates from `ServerStorage` (modules made in Studio with correct pivots, materials, lights)
  rather than building everything from `Instance.new` part by part.
- Set properties **before** parenting (parent last) — avoids replication of intermediate states.
- Merge static wall segments into fewer larger parts/meshes where visual quality allows; reuse the same mesh ids for
  instancing ([performance](08-performance.md#gpu--render-thread)).
- Lights: at most a few shadow-casting lights per visible area; many fixtures can be emissive (Neon/SurfaceAppearance
  emissive) with only a subset holding actual `SurfaceLight`/`PointLight` ([local lights](../graphics/03-local-lights.md)).

## ProceduralModel (engine feature, 2026)
`ProceduralModel` + generator ModuleScript with `Attributes` defaults and `OnGenerate(params, targetContainer)`;
`params.Size`, `params.Attributes`, `params:Pause()` (call liberally in loops to avoid "Script Timeout").
The engine regenerates when parameters/Size/source change (marked dirty, regenerated later in the frame; yielded
generations are cancelled and restarted), positions results with `PivotTo`, scales with `ScaleTo`, works at edit
time and runtime, integrates with undo. Limits: not inside Actors, can't become packages, dragger joints are not
preserved. Creator Store generators are sandboxed by default. Use it for parametric props (staircases, shelves,
fences, room shells); use your own layout generator for whole levels. Generate around the origin; never modify
the DataModel outside `targetContainer`.

## Multiplayer determinism checklist
- [ ] Generator is a pure function of (seed, version, chunk coords, config) — no time, no global RNG, no
      dependency on iteration order of dictionaries (sort keys).
- [ ] Server authoritative for collision/gameplay layout; clients only add cosmetics derived from the same seed.
- [ ] Late joiners get the same world (server instantiates; or seed replicated via attribute before clients
      generate cosmetics).
- [ ] Seed + version logged; a failing seed can be replayed in Studio.

Sources: cd:reference/engine/datatypes/Random, cd:reference/engine/libraries/math, cd:parts/procedural-models,
cd:characters/pathfinding, cd:reference/engine/classes/WorldRoot, cd:workspace/streaming/techniques,
cd:scripting/multithreading, cd:performance-optimization/improve.
