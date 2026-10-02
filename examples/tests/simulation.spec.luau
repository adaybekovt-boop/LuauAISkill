--!strict
local Model = require("../simulation/ReplicatedStorage/Dash/DashState")
local initial: Model.DashData = { cooldown = 0, remaining = 0, held = false }
local first, started = Model.step(initial, true, 1/60)
assert(started and first.remaining == 0.18 and initial.cooldown == 0)
local replay, replayStarted = Model.step(initial, true, 1/60)
assert(replayStarted and replay.remaining == first.remaining and replay.cooldown == first.cooldown)
local held, twice = Model.step(first, true, 1/60)
assert(not twice and held.cooldown < first.cooldown)
local state = held
for _ = 1, 120 do state = Model.step(state, true, 1/60) end
local _, heldAgain = Model.step(state, true, 1/60)
assert(not heldAgain, "holding never auto-repeats")
state = Model.step(state, false, 1/60)
local _, nextPress = Model.step(state, true, 1/60)
assert(nextPress)
local corrected = Model.step(initial, false, 1/60)
assert(corrected.remaining == 0, "rollback removes state-driven effect")
print("simulation.spec: deterministic replay, cooldown, press latch and reversible effect state passed")
