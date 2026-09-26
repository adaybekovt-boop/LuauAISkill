--!strict
-- Item definitions (shared, read-only). The server trusts only these tables, never client-sent names or stacks.
local InventoryModel = require(script.Parent.InventoryModel)
export type ItemDef = InventoryModel.ItemDef

local Items: { [string]: ItemDef } = {
	Flashlight = { name = "Flashlight", maxStack = 1 },
	Battery = { name = "Battery", maxStack = 8 },
	Keycard = { name = "Keycard", maxStack = 1 },
	Bandage = { name = "Bandage", maxStack = 5 },
}

for _, def in Items do
	table.freeze(def)
end
return table.freeze(Items)
