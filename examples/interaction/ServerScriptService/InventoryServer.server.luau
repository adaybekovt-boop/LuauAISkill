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
