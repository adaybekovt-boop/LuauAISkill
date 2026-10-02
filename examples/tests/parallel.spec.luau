--!strict
local Planner = require("../parallel/ServerScriptService/Parallel/Planner")
local choices = Planner.plan({ { id = 1, x = 0, z = 0 }, { id = 2, x = 999, z = 999 } },
    { { id = 4, x = 10, z = 0 }, { id = 3, x = -10, z = 0 } })
assert(choices[1].targetId == 3 and choices[2].targetId == 0)
assert(Planner.equal(choices, Planner.plan({ { id = 1, x = 0, z = 0 }, { id = 2, x = 999, z = 999 } },
    { { id = 3, x = -10, z = 0 }, { id = 4, x = 10, z = 0 } })))
local baseline, candidate = {}, {}
for _ = 1, 20 do table.insert(baseline, 0.002); table.insert(candidate, 0.001) end
assert(Planner.gate(baseline, candidate, true))
assert(not Planner.gate(baseline, candidate, false))
assert(not Planner.gate(candidate, baseline, true))
assert(not Planner.gate({ 0.002 }, { 0.001 }, true))
-- These are synthetic decision-function tests, NOT measurements or a performance claim.
print("parallel.spec: nearest/tie/range, output parity and fail-closed measurement gate passed")
