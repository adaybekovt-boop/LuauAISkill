--!strict
-- Registry of interaction behaviours keyed by the target's "InteractionType" attribute.
-- Other systems register their own handlers (e.g. the door recipe registers "Door").
export type Context = {
	player: Player,
	character: Model,
	target: Instance,
	prompt: ProximityPrompt,
}
export type Handler = (ctx: Context) -> ()

local handlers: { [string]: Handler } = {}
local Handlers = {}

function Handlers.register(kind: string, handler: Handler)
	assert(handlers[kind] == nil, "duplicate interaction handler: " .. kind)
	handlers[kind] = handler
end

function Handlers.get(kind: string): Handler?
	return handlers[kind]
end

-- Built-in: flip a boolean "On" attribute (switches, lamps). Clients react to the attribute for visuals.
Handlers.register("Toggle", function(ctx: Context)
	ctx.target:SetAttribute("On", ctx.target:GetAttribute("On") ~= true)
end)

-- Integration hooks, replaced at startup by the game (InventoryServer wires them to the inventory).
Handlers.hasItem = function(_player: Player, _itemId: string): boolean
	return false
end

-- Built-in: one-shot pickup. `onPickup` is replaced by the game (e.g. inventory add) at startup.
Handlers.onPickup = function(player: Player, itemId: string): boolean
	print(player.Name, "picked up", itemId)
	return true
end

Handlers.register("Pickup", function(ctx: Context)
	local itemId = ctx.target:GetAttribute("ItemId")
	if type(itemId) ~= "string" then
		return
	end
	ctx.target:SetAttribute("Enabled", false) -- claim first: a second request in the same frame is rejected
	if Handlers.onPickup(ctx.player, itemId) then
		ctx.target:Destroy()
	else
		ctx.target:SetAttribute("Enabled", true) -- inventory full etc.
	end
end)

return Handlers
