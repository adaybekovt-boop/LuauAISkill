--!strict
-- Release smoke scenarios against original recipe sources. NOT RUN in Roblox.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Context = require(script.Parent.Context)
local Fixtures = require(script.Parent.Fixtures)
local Cases: { [string]: (Context.Context) -> () } = {}

local function character(ctx: Context.Context, player: Player): (Model, Humanoid, BasePart)
	ctx.waitFor("living character", function()
		local model = player.Character
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		return humanoid ~= nil and humanoid.RootPart ~= nil and humanoid.Health > 0
	end)
	local model = player.Character :: Model
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	return model, humanoid, humanoid.RootPart :: BasePart
end

Cases["save-system"] = require(script.Parent.DataCase)

Cases["network-rate-limiter"] = function(ctx: Context.Context)
	local Net = Context.module(Context.child(ServerScriptService, "Net"), "NetServer")
	local count: { [Player]: number } = {}
	Net.request("ReleaseSmokeBudget", {
		limit = { capacity = 3, rate = 0 },
		parse = function(value: unknown): number?
			return if type(value) == "number" and value == 7 then value else nil
		end,
	}, function(player: Player, value: number): number
		count[player] = (count[player] or 0) + 1
		return value * 2
	end)
	local first = ctx.client(ctx.players[1], "network-burst")
	local second = ctx.client(ctx.players[2], "network-burst")
	ctx.check("invalid-payload-rejected", first.invalid == true and second.invalid == true)
	ctx.check("valid-request-roundtrip", first.accepted == 2 and second.accepted == 2)
	ctx.check("rate-limit-enforced", first.limited == 4 and second.limited == 4)
	ctx.check("per-player-budget-isolated", count[ctx.players[1]] == 2 and count[ctx.players[2]] == 2)
	local stats = Net.stats().ReleaseSmokeBudget
	ctx.check("server-counters-match", stats.accepted == 4 and stats.invalid == 2 and stats.limited == 8)
end

Cases["inventory"] = function(ctx: Context.Context)
	Context.child(Context.child(ReplicatedStorage, "Remotes"), "InventoryAction")
	local service = Context.module(Context.child(ServerScriptService, "Inventory"), "InventoryService")
	local player, other = ctx.players[1], ctx.players[2]
	local _, humanoid = character(ctx, player)
	service.load(player, { { s = 1, i = "Bandage", c = 2 } })
	service.load(other, {})
	humanoid.Health = 40
	ctx.client(player, "inventory-listen")
	local before = HttpService:JSONEncode(service.serialize(player))
	ctx.client(player, "inventory-action", { "Use", -1 } :: { any })
	task.wait(0.3)
	ctx.check("invalid-slot-no-mutation", before == HttpService:JSONEncode(service.serialize(player)))
	ctx.client(player, "inventory-action", { "Move", 1, 2 } :: { any })
	ctx.waitFor("server inventory move", function() local s = service.serialize(player); return s[1].s == 2 end)
	ctx.check("move-server-authoritative", service.serialize(player)[1].s == 2)
	ctx.client(player, "inventory-action", { "Use", 2 } :: { any })
	ctx.waitFor("bandage consumed", function() return service.serialize(player)[1].c == 1 end)
	ctx.check("use-consumes-and-heals", humanoid.Health >= 65 and service.serialize(player)[1].c == 1)
	local snapshot = ctx.client(player, "inventory-snapshot")
	ctx.check("owner-receives-snapshot", snapshot[1].s == 2 and snapshot[1].c == 1)
	ctx.check("other-inventory-unchanged", #service.serialize(other) == 0)
end

Cases["interaction"] = function(ctx: Context.Context)
	local player = ctx.players[1]
	local model, _, root = character(ctx, player)
	model:PivotTo(CFrame.new(0, 5, 0))
	root.Anchored = true
	local target = Fixtures.part("ReleaseSmokeSwitch", Vector3.new(0, 5, -5), Vector3.new(2, 2, 2))
	target:SetAttribute("InteractionType", "Toggle")
	target:SetAttribute("Cooldown", 0.25)
	CollectionService:AddTag(target, "Interactable")
	ctx.waitFor("bound prompt", function() return target:FindFirstChildOfClass("ProximityPrompt") ~= nil end)
	ctx.check("tag-creates-prompt", target:FindFirstChildOfClass("ProximityPrompt") ~= nil)
	ctx.client(player, "prompt", target.Name)
	ctx.waitFor("near interaction", function() return target:GetAttribute("On") == true end)
	ctx.check("near-prompt-dispatched", target:GetAttribute("On") == true)
	target:SetAttribute("Enabled", false)
	task.wait(0.35)
	ctx.client(player, "prompt", target.Name)
	task.wait(0.35)
	ctx.check("disabled-target-unchanged", target:GetAttribute("On") == true)
	target:SetAttribute("Enabled", true)
	model:PivotTo(CFrame.new(0, 5, 100))
	task.wait(0.35)
	ctx.client(player, "prompt", target.Name)
	task.wait(0.35)
	ctx.check("distant-attempt-unchanged", target:GetAttribute("On") == true,
		"Engine prompt restrictions and server validation jointly reject this ordinary client attempt")
	CollectionService:RemoveTag(target, "Interactable")
	ctx.waitFor("prompt cleanup", function() return target:FindFirstChildOfClass("ProximityPrompt") == nil end)
	ctx.check("untag-destroys-prompt", target:FindFirstChildOfClass("ProximityPrompt") == nil)
	root.Anchored = false
	target:Destroy()
end

Cases["hitscan-gun"] = function(ctx: Context.Context)
	local Hitscan = Context.module(Context.child(ServerScriptService, "Combat"), "Hitscan")
	Hitscan.start()
	local player = ctx.players[1]
	local model, _, root = character(ctx, player)
	model:PivotTo(CFrame.new(0, 5, 0))
	root.Anchored = true
	local head = Context.child(model, "Head") :: BasePart
	local tool = Instance.new("Tool")
	tool.Name, tool.RequiresHandle = "SmokePistol", false
	tool:SetAttribute("WeaponId", "Pistol")
	tool:SetAttribute("Ammo", 12)
	tool.Parent = model
	local victim = Instance.new("Model")
	victim.Name, victim.Parent = "ReleaseSmokeVictim", Workspace
	local target = Fixtures.part("Head", head.Position + Vector3.new(0, 0, -30), Vector3.new(5, 5, 2), victim)
	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.Parent = victim
	local direction = (target.Position - head.Position).Unit
	ctx.client(player, "hitscan", { origin = head.Position + Vector3.new(100, 0, 0), direction = direction })
	task.wait(0.3)
	ctx.check("spoofed-origin-rejected", humanoid.Health == 100 and tool:GetAttribute("Ammo") == 12)
	ctx.client(player, "hitscan", { origin = head.Position, direction = direction })
	ctx.waitFor("raycast damage", function() return humanoid.Health < 100 end)
	ctx.check("server-raycast-damages", humanoid.Health == 56)
	ctx.check("server-ammo-decrements", tool:GetAttribute("Ammo") == 11)
	local wall = Fixtures.part("ReleaseSmokeWall", head.Position + Vector3.new(0, 0, -15), Vector3.new(20, 20, 2))
	task.wait(0.3)
	ctx.client(player, "hitscan", { origin = head.Position, direction = direction })
	task.wait(0.3)
	ctx.check("wall-blocks-damage", humanoid.Health == 56 and tool:GetAttribute("Ammo") == 10)
	ctx.client(player, "reload")
	ctx.waitFor("reload finish", function() return tool:GetAttribute("Ammo") == 12 end, 5)
	ctx.check("reload-restores-magazine", tool:GetAttribute("Ammo") == 12)
	root.Anchored = false
	wall:Destroy(); victim:Destroy(); tool:Destroy()
end

Cases["round-manager"] = function(ctx: Context.Context)
	local first = ctx.players[1]
	local second = ctx.players[2]
	character(ctx, first); character(ctx, second)
	local info = Context.child(ReplicatedStorage, "Round")
	ctx.waitFor("round starts", function() return info:GetAttribute("Phase") == "InRound" end, 25)
	ctx.check("two-players-start-round", info:GetAttribute("Phase") == "InRound")
	ctx.check("map-created", Workspace:FindFirstChild("CurrentMap") ~= nil)
	local observed = ctx.client(first, "round-state")
	ctx.check("phase-and-deadline-replicate", observed.phase == "InRound" and type(observed.endsAt) == "number"
		and observed.endsAt > Workspace:GetServerTimeNow())
	local survivorBefore = first.Character
	local _, humanoid = character(ctx, second)
	humanoid.Health = 0
	ctx.waitFor("winner result", function() return info:GetAttribute("Phase") == "Results" end)
	ctx.check("elimination-selects-winner", info:GetAttribute("Winner") == first.Name)
	ctx.waitFor("map unload", function() return Workspace:FindFirstChild("CurrentMap") == nil end, 15)
	ctx.check("map-cleaned-after-results", Workspace:FindFirstChild("CurrentMap") == nil)
	ctx.waitFor("fresh character", function() return first.Character ~= nil and first.Character ~= survivorBefore end)
	ctx.check("next-cycle-respawns", first.Character ~= survivorBefore)
end

Cases["sprint-crouch-stamina"] = function(ctx: Context.Context)
	local player = ctx.players[1]
	character(ctx, player)
	ctx.waitFor("server stamina attribute", function() return type(player:GetAttribute("Stamina")) == "number" end)
	local result = ctx.client(player, "movement")
	ctx.check("input-actions-created", result.actions == true)
	ctx.check("crouch-speed-applied", result.crouch == true and result.crouchSpeed == 8)
	ctx.check("stand-speed-restored", result.stand == true and result.standSpeed == 16)
	ctx.check("sprint-speed-applied", result.sprint == true and result.sprintSpeed == 24)
	ctx.waitFor("server stamina drains", function() local v = player:GetAttribute("Stamina"); return type(v) == "number" and v < 100 end)
	ctx.check("server-stamina-drains", (player:GetAttribute("Stamina") :: number) < 100)
	ctx.client(player, "movement-stop")
	local before = player:GetAttribute("Stamina") :: number
	ctx.waitFor("stamina recovery", function() return (player:GetAttribute("Stamina") :: number) > before end, 8)
	ctx.check("server-stamina-recovers", (player:GetAttribute("Stamina") :: number) > before)
	local old = player.Character
	player:LoadCharacterAsync()
	ctx.waitFor("respawn", function() return player.Character ~= nil and player.Character ~= old end)
	local reset = ctx.client(player, "movement-reset")
	ctx.check("respawn-clears-movement", reset == true)
end

Cases["npc-patrol"] = function(ctx: Context.Context)
	local characterModel = character(ctx, ctx.players[1])
	characterModel:PivotTo(CFrame.new(60, 5, 0))
	local routes = Instance.new("Folder")
	routes.Name, routes.Parent = "PatrolRoutes", Workspace
	local route = Instance.new("Folder")
	route.Name, route.Parent = "SmokeRoute", routes
	for i, x in { 0, 25 } do
		local point = Fixtures.part(tostring(i), Vector3.new(x, 3, 0), Vector3.new(1, 1, 1), route)
		point.CanCollide, point.CanQuery, point.Transparency = false, false, 1
	end
	local description = Instance.new("HumanoidDescription")
	local npc = Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R6)
	description:Destroy()
	npc.Name = "ReleaseSmokeNpc"
	npc:PivotTo(CFrame.new(0, 5, 0))
	npc:SetAttribute("PatrolRoute", "SmokeRoute")
	npc:SetAttribute("SightRange", 0)
	npc:SetAttribute("Hearing", 0)
	npc.Parent = Workspace
	local root = Context.child(npc, "HumanoidRootPart") :: BasePart
	local start = root.Position
	CollectionService:AddTag(npc, "Npc")
	ctx.waitFor("patrol state", function() return npc:GetAttribute("State") == "Patrol" end)
	ctx.check("tag-binds-patrol", npc:GetAttribute("State") == "Patrol")
	ctx.waitFor("physical patrol movement", function() return (root.Position - start).Magnitude > 8 end, 25)
	ctx.check("path-and-physics-move-npc", math.abs(root.Position.X - start.X) > 8)
	ctx.check("server-owns-npc", root:GetNetworkOwner() == nil)
	CollectionService:RemoveTag(npc, "Npc")
	task.wait(0.2)
	npc:SetAttribute("State", "Unbound")
	task.wait(0.6)
	ctx.check("untag-stops-manager-writes", npc:GetAttribute("State") == "Unbound")
	npc:Destroy(); routes:Destroy()
end

Cases["settings-menu"] = function(ctx: Context.Context)
	local result = ctx.client(ctx.players[1], "settings")
	ctx.check("menu-and-controls-created", result.controls >= 7)
	ctx.check("client-sanitizes-settings", result.sanitized == true)
	ctx.check("camera-fov-applies", result.fov == 85)
	ctx.check("server-save-sync-roundtrip", result.roundtrip == true)
	local old = ctx.players[1].Character
	ctx.players[1]:LoadCharacterAsync()
	ctx.waitFor("settings respawn", function() return ctx.players[1].Character ~= nil and ctx.players[1].Character ~= old end)
	local after = ctx.client(ctx.players[1], "settings-after-respawn")
	ctx.check("menu-survives-respawn", after == true)
end

Cases["lighting-presets"] = function(ctx: Context.Context)
	local names = { "HorrorInterior", "BackroomsOffice", "DarkCorridor", "NightExterior", "Sunset", "FogDay",
		"IndustrialWarehouse", "Poolrooms", "EmergencyRed" }
	for _, name in names do
		Workspace:SetAttribute("LightingPreset", name)
		Workspace:SetAttribute("PowerState", if name == "EmergencyRed" then "Emergency" else "On")
		local result = ctx.client(ctx.players[1], "lighting", name)
		ctx.check("preset-" .. name, result.matched == true, tostring(result.detail))
		-- Optional pause lets a maintainer/MCP capture each exact client view; the receipt gate requires images.
		Workspace:SetAttribute("ReleaseSmokeCapturePreset", name)
		if Workspace:GetAttribute("ReleaseSmokePauseForScreenshots") == true then
			ctx.waitFor("screenshot acknowledgement " .. name, function()
				return Workspace:GetAttribute("ReleaseSmokeCapturedPreset") == name
			end, 120)
		end
	end
	local effects = ctx.client(ctx.players[1], "lighting-counts")
	ctx.check("effects-not-duplicated", effects == true)
end

return Cases
