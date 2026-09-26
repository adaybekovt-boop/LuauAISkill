--!strict
-- Server-authoritative inventory: one in-memory Inventory per player, mutated only here.
-- Clients send intents (Use/Drop/Move + slot numbers) through one RemoteEvent and receive full snapshots
-- (a 20-slot snapshot is a few hundred bytes — simpler and safer than diffs at this size).
-- Persistence is external: the save system calls InventoryService.load / serialize (see save-system recipe).
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
local Validate = require(ReplicatedStorage.Lib.Validate)
local Items = require(ReplicatedStorage.Inventory.Items)
local InventoryModel = require(ReplicatedStorage.Inventory.InventoryModel)

export type UseHandler = (player: Player) -> boolean -- return true to consume one item

local CAPACITY = 9
local ACTIONS = { Use = true, Drop = true, Move = true }

local InventoryService = {}

local inventories: { [Player]: InventoryModel.Inventory } = {}
local useHandlers: { [string]: UseHandler } = {}
local limiter = TokenBucket.new({ Action = { capacity = 8, rate = 4 } })
local syncRemote: RemoteEvent
local started = false

local function sync(player: Player)
	local inv = inventories[player]
	if inv then
		syncRemote:FireClient(player, InventoryModel.serialize(inv))
	end
end

-- Hook for dropping into the world (e.g. clone a pickup model); default: the item is discarded.
InventoryService.onDrop = function(_player: Player, _itemId: string, _count: number) end

function InventoryService.registerUse(itemId: string, handler: UseHandler)
	assert(Items[itemId], "unknown item " .. itemId)
	useHandlers[itemId] = handler
end

function InventoryService.add(player: Player, itemId: string, count: number): number
	local inv = inventories[player]
	if not inv then
		return 0
	end
	local added = InventoryModel.add(inv, Items, itemId, count)
	if added > 0 then
		sync(player)
	end
	return added
end

function InventoryService.has(player: Player, itemId: string): boolean
	local inv = inventories[player]
	return inv ~= nil and InventoryModel.count(inv, itemId) > 0
end

function InventoryService.take(player: Player, itemId: string, count: number): boolean
	local inv = inventories[player]
	if inv and InventoryModel.take(inv, itemId, count) then
		sync(player)
		return true
	end
	return false
end

function InventoryService.serialize(player: Player): InventoryModel.Serialized?
	local inv = inventories[player]
	return if inv then InventoryModel.serialize(inv) else nil
end

-- Replace the player's inventory with saved data (call once the profile has loaded).
function InventoryService.load(player: Player, data: unknown)
	local inv, dropped = InventoryModel.deserialize(data, Items, CAPACITY)
	if dropped > 0 then
		warn(`[Inventory] dropped {dropped} invalid entries for {player.UserId}`)
	end
	inventories[player] = inv
	sync(player)
end

local function onAction(player: Player, action: unknown, a: unknown, b: unknown)
	if not limiter:allow(player, "Action", os.clock()) then
		return
	end
	local inv = inventories[player]
	local kind = Validate.oneOf(action, ACTIONS)
	local slot = Validate.integer(a, 1, CAPACITY)
	if not inv or not kind or not slot then
		return
	end
	if kind == "Move" then
		local target = Validate.integer(b, 1, CAPACITY)
		if target and InventoryModel.move(inv, Items, slot, target) then
			sync(player)
		end
	elseif kind == "Drop" then
		local id, removed = InventoryModel.removeAt(inv, slot, math.huge)
		if id then
			InventoryService.onDrop(player, id, removed)
			sync(player)
		end
	elseif kind == "Use" then
		local entry = inv.slots[slot]
		local handler = entry and useHandlers[entry.id]
		if entry and handler and handler(player) then
			InventoryModel.removeAt(inv, slot, 1)
			sync(player)
		end
	end
end

function InventoryService.start()
	assert(not started, "InventoryService.start called twice")
	started = true
	local folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	local action = Instance.new("RemoteEvent")
	action.Name = "InventoryAction"
	action.Parent = folder
	syncRemote = Instance.new("RemoteEvent")
	syncRemote.Name = "InventorySync"
	syncRemote.Parent = folder
	action.OnServerEvent:Connect(onAction)

	local function onPlayerAdded(player: Player)
		if not inventories[player] then
			inventories[player] = InventoryModel.new(CAPACITY) -- replaced by load() when saved data arrives
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		-- The save system must read serialize(player) BEFORE this runs; connect its handler first or have it
		-- take a snapshot in its own PlayerRemoving handler (handlers run in connection order, same frame).
		inventories[player] = nil
		limiter:forget(player)
	end)
end

InventoryService.CAPACITY = CAPACITY
return InventoryService
