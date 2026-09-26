--!strict
-- Unit tests for the NPC brain and noise model. Run: luau examples/tests/npc.spec.luau (from repo root).
local Brain = require("../npc/ServerScriptService/Npc/Brain")
local Noise = require("../npc/ServerScriptService/Npc/Noise")

local v = vector.create
local P = { detectGrace = 0.6, loseSightTime = 2, investigateTime = 5, searchTime = 6 }
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
local function senses(now: number, see: any?, hear: any?, atGoal: boolean?): any
	return { now = now, seePos = see, hearPos = hear, atGoal = atGoal == true }
end

test("grace period before a chase, then chase and run", function()
	local m = Brain.new(0)
	eq((Brain.think(m, senses(0, v(1, 0, 0)), P)), "Investigate", "just noticed")
	eq((Brain.think(m, senses(0.3, v(1, 0, 0)), P)), "Investigate", "still in grace")
	local state, run = Brain.think(m, senses(0.7, v(2, 0, 0)), P)
	eq(state, "Chase")
	eq(run, true)
end)
test("breaking line of sight during grace resets it", function()
	local m = Brain.new(0)
	Brain.think(m, senses(0, v(1, 0, 0)), P)
	Brain.think(m, senses(0.4, nil), P)
	eq((Brain.think(m, senses(0.5, v(1, 0, 0)), P)), "Investigate", "grace restarted")
end)
test("lost target: keep chasing briefly, then search last seen position, then patrol", function()
	local m = Brain.new(0)
	Brain.think(m, senses(0, v(5, 0, 5)), P)
	Brain.think(m, senses(1, v(5, 0, 5)), P) -- chase
	eq((Brain.think(m, senses(2, nil), P)), "Chase", "within loseSightTime")
	eq((Brain.think(m, senses(3.5, nil), P)), "Search")
	eq(m.goal, v(5, 0, 5), "search at last seen position")
	eq((Brain.think(m, senses(9, nil), P)), "Search")
	eq((Brain.think(m, senses(10, nil), P)), "Patrol")
end)
test("noise → investigate → arrive → search", function()
	local m = Brain.new(0)
	eq((Brain.think(m, senses(0, nil, v(9, 0, 9)), P)), "Investigate")
	eq(m.goal, v(9, 0, 9))
	eq((Brain.think(m, senses(1, nil, nil, true), P)), "Search", "arrived")
end)
test("noise audibility scales with loudness and distance; old events expire", function()
	local n = Noise.new(1)
	Noise.emit(n, v(30, 0, 0) :: any, 1, 0) -- audible up to 40 studs with hearing 40
	Noise.emit(n, v(10, 0, 0) :: any, 0.2, 0) -- audible up to 8 studs → not audible at 10
	eq(Noise.loudest(n, v(0, 0, 0) :: any, 40, 0.5), v(30, 0, 0))
	eq(Noise.loudest(n, v(0, 0, 0) :: any, 40, 2), nil, "expired")
	Noise.prune(n, 2)
	eq(#n.events, 0)
end)

print(`npc.spec: {passed} passed, {failed} failed`)
if failed > 0 then
	error("npc tests failed")
end
