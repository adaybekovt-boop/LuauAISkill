--!strict
-- Pure inventory logic: slots, stacking, moving, (de)serialization. No Roblox APIs → unit-testable in the Luau CLI
-- (examples/tests/inventory.spec.luau). The server owns the only authoritative copy; clients get snapshots.
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Slot = { id: string, count: number }
export type Inventory = { capacity: number, slots: { [number]: Slot } } -- sparse: slots[i] == nil means empty
export type ItemDef = { name: string, maxStack: number }
export type Defs = { [string]: ItemDef }
-- Wire/DataStore format: dense array (sparse arrays break when serialized to JSON or sent through remotes).
export type Serialized = { { s: number, i: string, c: number } }

local InventoryModel = {}

function InventoryModel.new(capacity: number): Inventory
	assert(capacity >= 1 and capacity % 1 == 0, "capacity must be a positive integer")
	return { capacity = capacity, slots = {} }
end

-- Adds up to `count` items: tops up existing stacks first, then fills empty slots in order.
-- Returns how many were actually added (0 for unknown ids or a full inventory).
function InventoryModel.add(inv: Inventory, defs: Defs, id: string, count: number): number
	local def = defs[id]
	if def == nil or count < 1 or count % 1 ~= 0 then
		return 0
	end
	local remaining = count
	for i = 1, inv.capacity do
		local slot = inv.slots[i]
		if slot and slot.id == id and slot.count < def.maxStack then
			local n = math.min(def.maxStack - slot.count, remaining)
			slot.count += n
			remaining -= n
			if remaining == 0 then
				return count
			end
		end
	end
	for i = 1, inv.capacity do
		if inv.slots[i] == nil then
			local n = math.min(def.maxStack, remaining)
			inv.slots[i] = { id = id, count = n }
			remaining -= n
			if remaining == 0 then
				break
			end
		end
	end
	return count - remaining
end

-- Removes up to `count` from one slot. Returns (itemId, removed).
function InventoryModel.removeAt(inv: Inventory, index: number, count: number): (string?, number)
	local slot = inv.slots[index]
	if slot == nil or count < 1 then
		return nil, 0
	end
	local n = math.min(slot.count, count)
	slot.count -= n
	if slot.count == 0 then
		inv.slots[index] = nil
	end
	return slot.id, n
end

-- Removes `count` of an item across slots, all-or-nothing. Returns success.
function InventoryModel.take(inv: Inventory, id: string, count: number): boolean
	if InventoryModel.count(inv, id) < count then
		return false
	end
	local remaining = count
	for i = inv.capacity, 1, -1 do -- take from the last stacks first
		local slot = inv.slots[i]
		if slot and slot.id == id then
			local _, n = InventoryModel.removeAt(inv, i, remaining)
			remaining -= n
			if remaining == 0 then
				break
			end
		end
	end
	return true
end

function InventoryModel.count(inv: Inventory, id: string): number
	local total = 0
	for _, slot in inv.slots do
		if slot.id == id then
			total += slot.count
		end
	end
	return total
end

-- Move `from` onto `to`: merge same items up to maxStack, otherwise swap. Indices are validated by the caller.
function InventoryModel.move(inv: Inventory, defs: Defs, from: number, to: number): boolean
	local a = inv.slots[from]
	if a == nil or from == to then
		return false
	end
	local b = inv.slots[to]
	if b and b.id == a.id then
		local def = defs[a.id]
		local maxStack = if def then def.maxStack else 1
		local n = math.min(maxStack - b.count, a.count)
		if n <= 0 then
			inv.slots[from], inv.slots[to] = b, a
			return true
		end
		b.count += n
		a.count -= n
		if a.count == 0 then
			inv.slots[from] = nil
		end
		return true
	end
	inv.slots[to] = a
	if b then
		inv.slots[from] = b
	else
		inv.slots[from] = nil
	end
	return true
end

function InventoryModel.serialize(inv: Inventory): Serialized
	local out: Serialized = {}
	for i = 1, inv.capacity do
		local slot = inv.slots[i]
		if slot then
			table.insert(out, { s = i, i = slot.id, c = slot.count })
		end
	end
	return out
end

-- Rebuilds an inventory from untrusted/old data: unknown items dropped, counts clamped, duplicate slots ignored.
-- Returns the inventory and how many entries were dropped (log it; never silently lose data without a trace).
function InventoryModel.deserialize(data: unknown, defs: Defs, capacity: number): (Inventory, number)
	local inv = InventoryModel.new(capacity)
	local dropped = 0
	if type(data) ~= "table" then
		return inv, 0
	end
	for _, entry in data :: { any } do
		local accepted = false
		if type(entry) == "table" then
			local s, id, c = entry.s, entry.i, entry.c
			local def = if type(id) == "string" then defs[id] else nil
			if def and type(s) == "number" and s % 1 == 0 and s >= 1 and s <= capacity and inv.slots[s] == nil
				and type(c) == "number" and c == c and c >= 1 then
				inv.slots[s] = { id = id, count = math.min(math.floor(c), def.maxStack) }
				accepted = true
			end
		end
		if not accepted then
			dropped += 1
		end
	end
	return inv, dropped
end

return InventoryModel
