# Recipe: inventory, pickups and hotbar (server-authoritative)

Evidence: pure model TYPECHECKED + CLI-EXECUTED (`examples/tests/inventory.spec.luau`, 6 tests) · service/client
TYPECHECKED · **not run in Studio**. Side: server authority, client view.
Needs: [interaction system](interaction-system.md) (pickups), `examples/lib`. Persistence: [save system](save-system.md).

## Architecture
```text
ReplicatedStorage/Inventory/Items           item defs (name, maxStack) — shared, frozen
ReplicatedStorage/Inventory/InventoryModel  pure functions: add/take/move/removeAt/serialize/deserialize (tested)
ServerScriptService/Inventory/InventoryService  per-player Inventory in memory; the ONLY mutator
ServerScriptService/InventoryServer         wiring: pickups → add, doors → has, Bandage use, drops → world pickups
StarterPlayerScripts/InventoryClient        hotbar view; sends intents "Use"/"Drop"/"Move" + slot numbers
Remotes: InventoryAction (C→S intents), InventorySync (S→C full snapshot of that player only)
```
Why:
- **Client never names an item** it wants — it names a *slot*; the server looks up what is actually there. Item
  ids from the client would be an item-spawning exploit.
- **Pure model** = the risky logic (stacking, merging, clamping, loading old data) is unit-tested without Studio.
- **Full snapshots** for ≤ 20 slots are small; diffs add complexity and desync bugs for no measurable gain.
  Switch to diffs only for large containers (chests with 100+ slots).
- **Private data goes through `FireClient`**, not attributes on the Player (attributes replicate to everyone).
- **Wire format is a dense array** `{ {s=slot, i=id, c=count} }` — sparse arrays break in JSON/remotes.

## Code
<!-- code: examples/interaction/ReplicatedStorage/Inventory/Items.luau -->
```luau
-- file: examples/interaction/ReplicatedStorage/Inventory/Items.luau
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
```
<!-- /code -->

<!-- code: examples/interaction/ReplicatedStorage/Inventory/InventoryModel.luau -->
```luau
-- file: examples/interaction/ReplicatedStorage/Inventory/InventoryModel.luau
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
```
<!-- /code -->

<!-- code: examples/interaction/ServerScriptService/Inventory/InventoryService.luau -->
```luau
-- file: examples/interaction/ServerScriptService/Inventory/InventoryService.luau
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
```
<!-- /code -->

<!-- code: examples/interaction/ServerScriptService/InventoryServer.server.luau -->
```luau
-- file: examples/interaction/ServerScriptService/InventoryServer.server.luau
--!strict
-- Wires the inventory into the interaction system and defines item behaviours. The only script that knows both.
-- Status: TYPECHECKED. Not run in Studio.
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local InventoryService = require(ServerScriptService.Inventory.InventoryService)
local Handlers = require(ServerScriptService.Interaction.Handlers)

InventoryService.start()

Handlers.onPickup = function(player: Player, itemId: string): boolean
	return InventoryService.add(player, itemId, 1) == 1
end
Handlers.hasItem = InventoryService.has

InventoryService.registerUse("Bandage", function(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.Health >= humanoid.MaxHealth then
		return false -- not consumed
	end
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 25)
	return true
end)

-- Dropped items become pickups again if a template exists: ServerStorage.ItemModels.<ItemId> (a BasePart or Model).
InventoryService.onDrop = function(player: Player, itemId: string, count: number)
	local templates = ServerStorage:FindFirstChild("ItemModels")
	local template = templates and templates:FindFirstChild(itemId)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (template and root and root:IsA("BasePart")) then
		return
	end
	for _ = 1, math.min(count, 10) do -- cap world spam; the rest is discarded
		local drop = template:Clone()
		local offset = Vector3.new(math.random() * 2 - 1, 0, math.random() * 2 - 1)
		local at = root.CFrame * CFrame.new(offset + Vector3.new(0, -1, -3))
		if drop:IsA("Model") then
			drop:PivotTo(at)
		elseif drop:IsA("BasePart") then
			drop.CFrame = at
		end
		drop:SetAttribute("InteractionType", "Pickup")
		drop:SetAttribute("ItemId", itemId)
		drop:SetAttribute("ActionText", "Pick up")
		CollectionService:AddTag(drop, "Interactable")
		drop.Parent = Workspace
	end
end
```
<!-- /code -->

<!-- code: examples/interaction/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau -->
```luau
-- file: examples/interaction/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau
--!strict
-- Hotbar view for the server inventory. Displays snapshots and sends intents; never edits inventory state itself.
-- Keys 1–9 / click / tap = Use; right click = Drop. Built in code for the recipe; in a real project author the
-- ScreenGui in StarterGui and keep only the binding logic here.
-- Status: TYPECHECKED. Not run in Studio.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Inventory.Items)

local SLOTS = 9 -- must match InventoryService.CAPACITY
local KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine,
}

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
assert(remotes, "Remotes folder missing (is InventoryServer running?)")
local action = remotes:WaitForChild("InventoryAction", 30) :: RemoteEvent
local syncRemote = remotes:WaitForChild("InventorySync", 30) :: RemoteEvent

local gui = Instance.new("ScreenGui")
gui.Name = "Hotbar"
gui.ResetOnSpawn = false -- survives respawn; state comes from the server anyway
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -12)
bar.Size = UDim2.fromScale(0.6, 0.09)
bar.BackgroundTransparency = 1
bar.Parent = gui
local barAspect = Instance.new("UIAspectRatioConstraint")
barAspect.AspectRatio = SLOTS -- square slots at any resolution
barAspect.Parent = bar

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0.005, 0)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

local buttons: { TextButton } = {}
for i = 1, SLOTS do
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. i
	button.LayoutOrder = i
	button.Size = UDim2.fromScale(1 / SLOTS - 0.006, 1)
	button.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	button.BackgroundTransparency = 0.25
	button.TextColor3 = Color3.fromRGB(235, 235, 235)
	button.TextScaled = true
	button.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	button.Text = ""
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 18
	constraint.Parent = button
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = button
	button.Activated:Connect(function() -- Activated covers mouse, touch and gamepad selection
		action:FireServer("Use", i)
	end)
	button.MouseButton2Click:Connect(function()
		action:FireServer("Drop", i)
	end)
	button.Parent = bar
	buttons[i] = button
end
gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

syncRemote.OnClientEvent:Connect(function(snapshot: unknown)
	for i = 1, SLOTS do
		buttons[i].Text = ""
	end
	if type(snapshot) ~= "table" then
		return
	end
	for _, entry in snapshot :: { any } do
		if type(entry) ~= "table" or type(entry.s) ~= "number" or type(entry.c) ~= "number" then
			continue
		end
		local button = buttons[entry.s]
		local def = Items[entry.i]
		if button and def then
			button.Text = if entry.c > 1 then `{def.name}\n×{entry.c}` else def.name
		end
	end
end)

ContextActionService:BindAction("HotbarUse", function(_name: string, state: Enum.UserInputState, input: InputObject)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local index = table.find(KEYS, input.KeyCode)
	if index then
		action:FireServer("Use", index)
	end
	return Enum.ContextActionResult.Sink
end, false, table.unpack(KEYS))
```
<!-- /code -->

## Pickup setup
World item: Part/Model tagged `Interactable`, attributes `InteractionType="Pickup"`, `ItemId="Battery"`,
`ActionText="Pick up"`. For drops, put a template named after the item under `ServerStorage.ItemModels`.

## Persistence hook (with the [save system](save-system.md))
- After the profile loads: `InventoryService.load(player, profile.data.inventory)`.
- Before saving: `profile.data.inventory = InventoryService.serialize(player)`.
- On leave, the save system must snapshot **before** `InventoryService` forgets the player: connect the save
  system's `PlayerRemoving` first (connection order) or have the inventory write into the profile on every change.
- `deserialize` drops invalid entries and reports how many — log it; a sudden spike means a bad migration.

## How to test
- CLI: `luau examples/tests/inventory.spec.luau` (stacking, partial add, all-or-nothing take, merge/swap, hostile
  saved data).
- Studio (Server & Clients): pick up 10 batteries (stacks 8 + 2); press 1 with a Bandage at full health (not
  consumed) and when hurt (heals 25, consumed); right-click drop → pickups appear in front; a second player can pick
  them up; respawn → hotbar persists (`ResetOnSpawn=false`, server state unchanged).
- Adversarial (temporary client script): `InventoryAction:FireServer("Use", 0/0)`, `("Use", 99)`, `("Move", 1, 1.5)`,
  `("Spawn", "Keycard")`, 100 calls in a loop → all rejected or rate limited, no server errors.

## Variations
- **Equippable tools**: on "Use" of a tool item, the server clones a `Tool` from ServerStorage into the Backpack;
  inventory stays the source of truth.
- **Containers/chests**: same model, a second `Inventory` keyed by the container; transfer = `take` from one +
  `add` to the other inside one server function (no yields between) so it's atomic.
- **Trading**: never two independent remotes "give" + "give". Server holds both offers, both players confirm, then
  a single non-yielding swap; persist both profiles (session locks prevent dupes across servers).
- **Weight/volume limits**: add to `ItemDef`, check in `InventoryModel.add` (and test it).

## Pitfalls
- Don't trust client-side counts for UI decisions that matter (e.g. "can craft") — ask the server or accept that the
  server may reject.
- Keep item ids stable forever (they are saved); rename display names instead.
- `math.huge` as "remove all" is fine in-memory; never serialize it.

Sources: cd:scripting/events/remote, cd:scripting/security/client-server-boundary, cd:scripting/attributes,
cd:reference/engine/classes/ContextActionService, cd:ui/size-modifiers, cd:reference/engine/classes/ScreenGui.
