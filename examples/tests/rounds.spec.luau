--!strict
-- Unit tests for the round state machine and match forming. Run: luau examples/tests/rounds.spec.luau
local RoundState = require("../rounds/ReplicatedStorage/Rounds/RoundState")
local QueueLogic = require("../rounds/ServerScriptService/Matchmaking/QueueLogic")

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

local CONFIG = { minPlayers = 2, intermission = 10, roundLength = 60, results = 5, endWhenAliveAtMost = 1 }

test("full cycle with last one standing", function()
	local r = RoundState.new(CONFIG, 0)
	eq(RoundState.step(r, { now = 0, players = 1, alive = 0 }), nil, "waiting")
	eq(RoundState.step(r, { now = 1, players = 2, alive = 0 }), "Intermission")
	eq(RoundState.step(r, { now = 5, players = 2, alive = 0 }), nil)
	eq(RoundState.step(r, { now = 11, players = 2, alive = 0 }), "InRound")
	eq(RoundState.step(r, { now = 20, players = 2, alive = 2 }), nil)
	eq(RoundState.step(r, { now = 30, players = 2, alive = 1, lastAlive = "Ann" }), "Results")
	eq(r.winner, "Ann")
	eq(RoundState.step(r, { now = 36, players = 2, alive = 0 }), "Intermission")
end)
test("timer ends the round without a winner", function()
	local r = RoundState.new(CONFIG, 0)
	RoundState.step(r, { now = 0, players = 3, alive = 0 })
	RoundState.step(r, { now = 10, players = 3, alive = 0 })
	eq(RoundState.step(r, { now = 70, players = 3, alive = 3 }), "Results")
	eq(r.winner, nil)
end)
test("players leaving during intermission / after results", function()
	local r = RoundState.new(CONFIG, 0)
	RoundState.step(r, { now = 0, players = 2, alive = 0 })
	eq(RoundState.step(r, { now = 3, players = 1, alive = 0 }), "Waiting")
	local r2 = RoundState.new(CONFIG, 0)
	RoundState.step(r2, { now = 0, players = 2, alive = 0 })
	RoundState.step(r2, { now = 10, players = 2, alive = 0 })
	RoundState.step(r2, { now = 15, players = 2, alive = 0 }) -- everyone died → Results (alive 0 ≤ 1)
	eq(r2.phase, "Results")
	eq(r2.winner, nil, "no survivor")
	eq(RoundState.step(r2, { now = 21, players = 1, alive = 0 }), "Waiting")
end)

local RULES = { matchSize = 4, baseGap = 100, gapPerSecond = 10, maxGap = 1000 }
local function entry(key: string, n: number, rating: number, joinedAt: number): any
	local ids = {}
	for i = 1, n do
		table.insert(ids, tonumber(key) :: number * 10 + i)
	end
	return { key = key, userIds = ids, rating = rating, joinedAt = joinedAt }
end
test("forms a match of similar ratings, keeps parties together", function()
	local matches, left = QueueLogic.form({
		entry("1", 1, 1000, 0), entry("2", 2, 1050, 1), entry("3", 1, 1900, 2), entry("4", 1, 990, 3),
	}, RULES, 5)
	eq(#matches, 1)
	local count = 0
	for _, e in matches[1] do
		count += #e.userIds
	end
	eq(count, 4)
	eq(#left, 1)
	eq(left[1].key, "3", "far rating left over")
end)
test("gap widens with waiting time", function()
	local entries = { entry("1", 1, 1000, 0), entry("2", 1, 1500, 0), entry("3", 1, 1500, 0), entry("4", 1, 1500, 0) }
	eq(#(QueueLogic.form(entries, RULES, 10)), 0, "gap 200 after 10 s: no match")
	eq(#(QueueLogic.form(entries, RULES, 50)), 1, "gap 600 after 50 s: match")
end)
test("oversized party never matches", function()
	eq(#(QueueLogic.form({ entry("1", 5, 1000, 0) }, RULES, 100)), 0)
end)

print(`rounds.spec: {passed} passed, {failed} failed`)
if failed > 0 then
	error("rounds tests failed")
end
