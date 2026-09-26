--!strict
-- Doors: server owns state + collision, clients animate the visual (see DoorVisuals.client.luau).
-- Door contract (set up in Studio):
--   Model tagged "Door" and "Interactable", attribute InteractionType = "Door"
--   ├─ Blocker (Part, PrimaryPart): invisible, Anchored, CanCollide — the only colliding part; prompt anchor
--   ├─ Hinge   (Part): invisible, Anchored, CanCollide=false; its CFrame is the swing axis (rotates around its Y)
--   └─ Visual  (Model): the door leaf, all parts Anchored, CanCollide=false (never moved by the server)
--   Attributes: Swing (number, replicated state: 0 closed, 1/-1 open away from the opener), Locked (bool),
--   KeyItem (string, inventory item that unlocks), AutoClose (seconds, 0 = never), DeniedAt (server time; set on
--   a locked attempt so clients can rattle the door).
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Binder = require(ReplicatedStorage.Lib.Binder)
local Validate = require(ReplicatedStorage.Lib.Validate)
local Handlers = require(ServerScriptService.Interaction.Handlers)

local DOOR_TAG = "Door"
local BLOCKED_RETRY = 1 -- seconds between auto-close attempts while someone stands in the doorway

local generation: { [Instance]: number } = {}

local function blockerOf(door: Instance): BasePart?
	local blocker = door:FindFirstChild("Blocker")
	return if blocker and blocker:IsA("BasePart") then blocker else nil
end

-- Closing on top of a character traps or flings them: only close when the doorway is empty.
local function doorwayOccupied(blocker: BasePart): boolean
	for _, part in Workspace:GetPartsInPart(blocker) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			return true
		end
	end
	return false
end

local setSwing: (door: Instance, swing: number) -> ()

local function scheduleAutoClose(door: Instance, gen: number)
	local delaySeconds = Validate.number(door:GetAttribute("AutoClose"), 0, 600) or 0
	if delaySeconds <= 0 then
		return
	end
	local function attempt()
		if generation[door] ~= gen or door.Parent == nil then
			return -- door was toggled again or removed; this timer is stale
		end
		local blocker = blockerOf(door)
		if blocker and doorwayOccupied(blocker) then
			task.delay(BLOCKED_RETRY, attempt)
			return
		end
		setSwing(door, 0)
	end
	task.delay(delaySeconds, attempt)
end

setSwing = function(door: Instance, swing: number)
	local gen = (generation[door] or 0) + 1
	generation[door] = gen
	door:SetAttribute("Swing", swing)
	local blocker = blockerOf(door)
	if blocker then
		blocker.CanCollide = swing == 0
	end
	if swing ~= 0 then
		scheduleAutoClose(door, gen)
	end
end

Handlers.register("Door", function(ctx: Handlers.Context)
	local door = ctx.target
	if door:GetAttribute("Locked") == true then
		local key = door:GetAttribute("KeyItem")
		if type(key) ~= "string" or not Handlers.hasItem(ctx.player, key) then
			door:SetAttribute("DeniedAt", Workspace:GetServerTimeNow())
			return
		end
		door:SetAttribute("Locked", false) -- design choice: a key unlocks the door permanently
	end
	local current = door:GetAttribute("Swing")
	if current ~= nil and current ~= 0 then
		local blocker = blockerOf(door)
		if blocker and doorwayOccupied(blocker) then
			return -- refuse to close on someone
		end
		setSwing(door, 0)
		return
	end
	-- Swing away from the opener: which side of the hinge's look vector is the player on?
	local hinge = door:FindFirstChild("Hinge")
	local root = ctx.character:FindFirstChild("HumanoidRootPart")
	local side = 1
	if hinge and hinge:IsA("BasePart") and root and root:IsA("BasePart") then
		side = if (root.Position - hinge.Position):Dot(hinge.CFrame.LookVector) > 0 then -1 else 1
	end
	setSwing(door, side)
end)

Binder.bind(DOOR_TAG, function(door, cleanup)
	local swing = Validate.number(door:GetAttribute("Swing"), -1, 1) or 0
	door:SetAttribute("Swing", swing)
	local blocker = blockerOf(door)
	if blocker then
		blocker.CanCollide = swing == 0
	end
	cleanup:add(function()
		generation[door] = nil
	end)
end)
