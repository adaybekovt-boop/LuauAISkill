--!strict
-- Unit tests for the Backrooms chunk layout. Run: luau examples/tests/procgen.spec.luau (from repo root).
-- Layout requires "../Lib/Hash" by string; tools/check_code.py links examples/lib into the project first.
local Layout = require("../procgen/ReplicatedStorage/Procgen/Layout")

local P = { size = 8, loopChance = 0.35, borderChance = 0.3, lightSpacing = 2, pillarChance = 0.12 }
local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(`{msg or "expected equal"}: {tostring(a)} ~= {tostring(b)}`, 2)
	end
end

local function signature(c: any): string
	local parts = {}
	for i = 0, c.size * c.size - 1 do
		table.insert(parts, (if c.openEast[i] then "E" else "-") .. (if c.openSouth[i] then "S" else "-"))
	end
	for _, l in c.lights do
		table.insert(parts, l.state)
	end
	return table.concat(parts)
end

test("deterministic for the same seed and chunk", function()
	eq(signature(Layout.chunk(42, 3, -2, P)), signature(Layout.chunk(42, 3, -2, P)))
end)
test("different seeds or chunks give different layouts", function()
	assert(signature(Layout.chunk(42, 0, 0, P)) ~= signature(Layout.chunk(43, 0, 0, P)), "seed")
	assert(signature(Layout.chunk(42, 0, 0, P)) ~= signature(Layout.chunk(42, 1, 0, P)), "chunk")
end)
test("every chunk is internally fully connected (spanning tree)", function()
	for cx = -5, 5 do
		for cz = -5, 5 do
			assert(Layout.fullyConnected(Layout.chunk(7, cx, cz, P)), `chunk {cx},{cz}`)
		end
	end
end)
test("neighbouring chunks agree on shared borders and each border has an opening", function()
	local n = P.size
	for cx = -3, 3 do
		for cz = -3, 3 do
			local c = Layout.chunk(99, cx, cz, P)
			local east = Layout.chunk(99, cx + 1, cz, P)
			local south = Layout.chunk(99, cx, cz + 1, P)
			local anyE, anyS = false, false
			for i = 0, n - 1 do
				local e = c.openEast[i * n + (n - 1)] == true
				eq(e, east.openWestBorder[i], `east border {cx},{cz} row {i}`)
				local s = c.openSouth[(n - 1) * n + i] == true
				eq(s, south.openNorthBorder[i], `south border {cx},{cz} col {i}`)
				anyE = anyE or e
				anyS = anyS or s
			end
			assert(anyE and anyS, `chunk {cx},{cz} has a sealed border`)
		end
	end
end)
test("lights on the grid with a mix of states", function()
	local counts = { on = 0, off = 0, flicker = 0 }
	for cx = 0, 9 do
		for _, l in Layout.chunk(5, cx, 0, P).lights do
			counts[l.state] += 1
		end
	end
	eq(counts.on + counts.off + counts.flicker, 10 * 16, "16 lights per 8×8 chunk at spacing 2")
	assert(counts.on > counts.off and counts.off > 0 and counts.flicker > 0, "expected mostly on, some off/flicker")
end)

print(`procgen.spec: {passed} passed, {failed} failed`)
if failed > 0 then
	error("procgen tests failed")
end
