--!strict
-- Unit tests for the pure inventory model. Run: luau examples/tests/inventory.spec.luau (from repo root).
local InventoryModel = require("../interaction/ReplicatedStorage/Inventory/InventoryModel")

local defs = { Battery = { name = "Battery", maxStack = 8 }, Keycard = { name = "Keycard", maxStack = 1 } }
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

test("add stacks then fills empty slots", function()
	local inv = InventoryModel.new(3)
	eq(InventoryModel.add(inv, defs, "Battery", 5), 5)
	eq(InventoryModel.add(inv, defs, "Battery", 5), 5, "3 topped up + 2 new stack")
	eq(inv.slots[1].count, 8)
	eq(inv.slots[2].count, 2)
	eq(InventoryModel.count(inv, "Battery"), 10)
end)
test("add reports partial when full, rejects unknown/invalid", function()
	local inv = InventoryModel.new(2)
	eq(InventoryModel.add(inv, defs, "Keycard", 3), 2, "only two slots")
	eq(InventoryModel.add(inv, defs, "Battery", 1), 0, "full")
	eq(InventoryModel.add(inv, defs, "Nope", 1), 0, "unknown")
	eq(InventoryModel.add(InventoryModel.new(2), defs, "Battery", 0.5), 0, "fractional")
	eq(InventoryModel.add(InventoryModel.new(2), defs, "Battery", 0 / 0), 0, "NaN")
end)
test("take is all-or-nothing", function()
	local inv = InventoryModel.new(3)
	InventoryModel.add(inv, defs, "Battery", 10)
	eq(InventoryModel.take(inv, "Battery", 11), false)
	eq(InventoryModel.count(inv, "Battery"), 10, "unchanged after failed take")
	eq(InventoryModel.take(inv, "Battery", 3), true)
	eq(InventoryModel.count(inv, "Battery"), 7)
end)
test("move merges up to maxStack, swaps otherwise", function()
	local inv = InventoryModel.new(3)
	inv.slots[1] = { id = "Battery", count = 6 }
	inv.slots[2] = { id = "Battery", count = 5 }
	inv.slots[3] = { id = "Keycard", count = 1 }
	eq(InventoryModel.move(inv, defs, 1, 2), true)
	eq(inv.slots[2].count, 8)
	eq(inv.slots[1].count, 3)
	eq(InventoryModel.move(inv, defs, 3, 1), true, "swap")
	eq(inv.slots[1].id, "Keycard")
	eq(inv.slots[3].id, "Battery")
	eq(InventoryModel.move(inv, defs, 2, 2), false, "same slot")
end)
test("removeAt clears empty slots", function()
	local inv = InventoryModel.new(2)
	InventoryModel.add(inv, defs, "Battery", 2)
	local id, n = InventoryModel.removeAt(inv, 1, math.huge)
	eq(id, "Battery")
	eq(n, 2)
	eq(inv.slots[1], nil)
end)
test("serialize/deserialize round-trip and sanitize hostile data", function()
	local inv = InventoryModel.new(4)
	InventoryModel.add(inv, defs, "Battery", 9)
	InventoryModel.add(inv, defs, "Keycard", 1)
	local copy, dropped = InventoryModel.deserialize(InventoryModel.serialize(inv), defs, 4)
	eq(dropped, 0)
	eq(InventoryModel.count(copy, "Battery"), 9)
	eq(InventoryModel.count(copy, "Keycard"), 1)
	local hostile = {
		{ s = 1, i = "Battery", c = 999 }, -- clamped to maxStack
		{ s = 1, i = "Keycard", c = 1 }, -- duplicate slot
		{ s = 9, i = "Battery", c = 1 }, -- out of range
		{ s = 2, i = "Gold", c = 1 }, -- unknown item
		{ s = 3, i = "Battery", c = 0 / 0 }, -- NaN
		"garbage",
	}
	local clean, bad = InventoryModel.deserialize(hostile, defs, 4)
	eq(bad, 5)
	eq(clean.slots[1].count, 8)
	eq(InventoryModel.deserialize(nil, defs, 4).capacity, 4, "nil data → empty inventory")
end)

print(`inventory.spec: {passed} passed, {failed} failed`)
if failed > 0 then
	error("inventory tests failed")
end
