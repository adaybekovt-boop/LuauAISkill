--!strict
local Rows = require("../leaderboard/ServerScriptService/Boards/Rows")
local rows = Rows.sorted({ ["2"] = { value = 10 }, ["1"] = { value = 10 }, bad = { value = 9 },
	["3"] = { value = 0/0 }, ["4"] = { value = -1 } }, 20)
assert(#rows == 2 and rows[1].userId == 1 and rows[2].userId == 2)
local friends = {}; for i = 1, 150 do table.insert(friends, i) end
local keys, partial = Rows.keys(1, friends)
assert(#keys == 100 and keys[1] == "1" and keys[100] == "100" and partial)
local small, limited = Rows.keys(1, { 1, 2, 2 })
assert(#small == 2 and not limited)
assert(not Rows.valid(math.huge) and not Rows.valid(1.1))
print("leaderboard.spec: stable ties, invalid entries, deduped/capped batch and partial flag passed")
