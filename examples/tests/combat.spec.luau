--!strict
-- Unit tests for shared combat math (portable vectors: runs on the CLI's native vectors).
-- Run: luau examples/tests/combat.spec.luau (from repo root).
local CombatMath = require("../combat/ReplicatedStorage/Combat/CombatMath")

local v = vector.create
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
local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(`{msg or "expected equal"}: {tostring(a)} ~= {tostring(b)}`, 2)
	end
end

test("inCone: in front, behind, too far, edge of angle", function()
	local o, f = v(0, 0, 0), v(0, 0, -1) -- Roblox forward is -Z
	eq(CombatMath.inCone(o, f :: any, v(0, 0, -5) :: any, 6, 45), true, "straight ahead")
	eq(CombatMath.inCone(o, f :: any, v(0, 0, 5) :: any, 6, 45), false, "behind")
	eq(CombatMath.inCone(o, f :: any, v(0, 0, -7) :: any, 6, 45), false, "out of reach")
	eq(CombatMath.inCone(o, f :: any, v(3, 0, -3.1) :: any, 6, 45), true, "just inside 45°")
	eq(CombatMath.inCone(o, f :: any, v(3.1, 0, -3) :: any, 6, 45), false, "just outside 45°")
	eq(CombatMath.inCone(o, f :: any, v(0, 50, -3) :: any, 6, 45), true, "height ignored (box handles it)")
end)
test("canFire honours rpm with tolerance", function()
	-- 600 rpm = 0.1 s interval; 15 % tolerance → 0.085 s allowed
	eq(CombatMath.canFire(0, 0.09, 600, 0.15), true)
	eq(CombatMath.canFire(0, 0.08, 600, 0.15), false)
	eq(CombatMath.canFire(-math.huge, 0, 600, 0), true, "first shot")
end)
test("falloff is flat, then linear to minMult at range", function()
	near(CombatMath.falloff(20, 10, 50, 150, 0.5), 20)
	near(CombatMath.falloff(20, 100, 50, 150, 0.5), 15)
	near(CombatMath.falloff(20, 1000, 50, 150, 0.5), 10, "clamped beyond range")
end)
test("ballistic matches closed form", function()
	local p = CombatMath.ballistic(v(0, 10, 0) :: any, v(10, 20, 0) :: any, v(0, -40, 0) :: any, 0.5)
	near(p.X, 5)
	near(p.Y, 10 + 10 - 5)
	near(p.Z, 0)
end)
test("finite rejects NaN and inf", function()
	eq(CombatMath.finite(v(1, 2, 3) :: any), true)
	eq(CombatMath.finite(v(0 / 0, 0, 0) :: any), false)
	eq(CombatMath.finite(v(math.huge, 0, 0) :: any), false)
end)
test("length and dot", function()
	near(CombatMath.length(v(3, 4, 0) :: any), 5)
	near(CombatMath.dot(v(1, 2, 3) :: any, v(4, 5, 6) :: any), 32)
end)

print(`combat.spec: {passed} passed, {failed} failed`)
if failed > 0 then
	error("combat tests failed")
end
