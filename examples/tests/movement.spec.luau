--!strict
-- Unit tests for the shared stamina model. Run: luau examples/tests/movement.spec.luau (from repo root).
local Stamina = require("../movement/ReplicatedStorage/Movement/Stamina")

local params = { max = 100, drainPerSecond = 20, regenPerSecond = 25, regenDelay = 1, startThreshold = 15 }
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
local function near(a: number, b: number, msg: string?)
	if math.abs(a - b) > 1e-6 then
		error(`{msg or "expected"} {b}, got {a}`, 2)
	end
end

test("drains while sprinting and reports exhaustion", function()
	local s = Stamina.new(params)
	for _ = 1, 10 do
		Stamina.step(s, 0.4, true)
	end
	near(s.value, 20, "after 4 s")
	assert(Stamina.step(s, 0.5, true), "10 left → still ok")
	assert(not Stamina.step(s, 0.6, true), "hits 0 → stop")
	near(s.value, 0)
end)
test("regen waits for the delay", function()
	local s = Stamina.new(params)
	s.value = 50
	Stamina.step(s, 0.1, true) -- drain resets the delay
	local afterDrain = s.value
	Stamina.step(s, 0.9, false)
	near(s.value, afterDrain, "still inside regen delay")
	Stamina.step(s, 0.2, false)
	near(s.value, afterDrain + 25 * 0.2, "regen after delay")
end)
test("start threshold prevents stutter sprinting", function()
	local s = Stamina.new(params)
	s.value = 10
	assert(not Stamina.canStart(s))
	s.value = 15
	assert(Stamina.canStart(s))
end)
test("huge dt is clamped", function()
	local s = Stamina.new(params)
	s.value = 0
	s.sinceDrain = 5
	Stamina.step(s, 1000, false)
	near(s.value, 25, "at most 1 s of regen per step")
end)

print(`movement.spec: {passed} passed, {failed} failed`)
if failed > 0 then
	error("movement tests failed")
end
