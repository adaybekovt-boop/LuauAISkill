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
