--!strict
local Sway = require("../viewmodel/ReplicatedStorage/Viewmodel/Sway")
local zero: Sway.SwayData = { x = 0, y = 0 }
local moved = Sway.step(zero, 500, -500, 1, false)
assert(moved.x <= 0.03 and moved.y >= -0.03 and zero.x == 0)
local reduced = Sway.step(moved, 20, 20, 0.016, true)
assert(reduced.x == 0 and reduced.y == 0)
assert(Sway.step(zero, 20, 20, -1, false).x == 0)
print("viewmodel.spec: bounded delta/offset, immutable step and Reduced Motion passed")
