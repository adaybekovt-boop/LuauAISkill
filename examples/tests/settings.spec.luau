--!strict
-- Unit tests for the settings schema. Run: luau examples/tests/settings.spec.luau (from repo root).
local Schema = require("../settings/ReplicatedStorage/Settings/Schema")

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

test("defaults for garbage input", function()
	local s = Schema.sanitize("nope")
	eq(s.FieldOfView, 70)
	eq(s.GraphicsTier, "Auto")
end)
test("ranges clamp and snap to step", function()
	local s = Schema.sanitize({ FieldOfView = 93, MasterVolume = 5, CameraShake = 0.3 })
	eq(s.FieldOfView, 95, "snapped to 5")
	eq(s.MasterVolume, 1, "clamped")
	eq(s.CameraShake, 0.25, "snapped to 0.25")
end)
test("wrong types, NaN, unknown options and extra keys are rejected", function()
	local s = Schema.sanitize({ ViewBobbing = "yes", FieldOfView = 0 / 0, GraphicsTier = "Insane", Admin = true })
	eq(s.ViewBobbing, true, "default kept")
	eq(s.FieldOfView, 70, "NaN → default")
	eq(s.GraphicsTier, "Auto")
	eq((s :: any).Admin, nil, "unknown key dropped")
end)
test("valid values survive", function()
	local s = Schema.sanitize({ ViewBobbing = false, GraphicsTier = "Low", MusicVolume = 0.3 })
	eq(s.ViewBobbing, false)
	eq(s.GraphicsTier, "Low")
	assert(math.abs((s.MusicVolume :: number) - 0.3) < 1e-9)
end)

print(`settings.spec: {passed} passed, {failed} failed`)
if failed > 0 then
	error("settings tests failed")
end
