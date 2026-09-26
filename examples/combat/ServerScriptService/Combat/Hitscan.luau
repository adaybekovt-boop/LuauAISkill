--!strict
-- Hitscan: client sends "HitscanFire"(origin, direction). Server checks rate/ammo/reload, validates the origin
-- against the server-side head, raycasts itself, applies falloff/headshot damage, broadcasts a cosmetic tracer.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Combat.Weapons)
local CombatMath = require(ReplicatedStorage.Combat.CombatMath)
local Common = require(ServerScriptService.Combat.Common)
local Damage = require(ServerScriptService.Combat.Damage)

local Hitscan = {}

local function ammoOf(tool: Tool, magazine: number): number
	local ammo = tool:GetAttribute("Ammo")
	if type(ammo) ~= "number" then
		tool:SetAttribute("Ammo", magazine) -- server-owned attribute: replicated, so the client UI can show it
		return magazine
	end
	return ammo
end

function Hitscan.start()
	local fire = Common.remote("HitscanFire") :: RemoteEvent
	local reload = Common.remote("Reload") :: RemoteEvent
	local shotFx = Common.remote("ShotFx", true) :: UnreliableRemoteEvent -- cosmetic tracers for other players

	fire.OnServerEvent:Connect(function(player: Player, rawOrigin: unknown, rawDirection: unknown)
		if not Common.allow(player) then
			return
		end
		local character, _, tool, def = Common.equipped(player)
		if not character or not tool or not def or def.kind ~= "Hitscan" then
			return
		end
		local gun = def :: Weapons.Hitscan
		local s = Common.state(player)
		local now = os.clock()
		if now < s.reloadingUntil or not CombatMath.canFire(s.lastFire, now, gun.rpm, Common.FIRE_TOLERANCE) then
			return
		end
		local origin, direction = Common.shot(character, rawOrigin, rawDirection)
		if not origin or not direction then
			return
		end
		local ammo = ammoOf(tool, gun.magazine)
		if ammo <= 0 then
			return
		end
		tool:SetAttribute("Ammo", ammo - 1)
		s.lastFire = now

		local result = Workspace:Raycast(origin, direction * gun.range, Common.excludeParams({ character }))
		shotFx:FireAllClients(player.UserId, origin, if result then result.Position else origin + direction * gun.range)
		local target = result and Common.humanoidOf(result.Instance)
		if not result or not target then
			return
		end
		local headshot = result.Instance.Name == "Head"
		local amount = CombatMath.falloff(gun.damage, result.Distance, gun.falloffStart, gun.range, gun.minFalloff)
			* (if headshot then gun.headMultiplier else 1)
		if Damage.apply(target, amount, { attacker = player, weapon = "Hitscan", headshot = headshot }) then
			Common.hitConfirm:FireClient(player, amount, headshot)
		end
	end)

	reload.OnServerEvent:Connect(function(player: Player)
		if not Common.allow(player) then
			return
		end
		local _, _, tool, def = Common.equipped(player)
		local s = Common.state(player)
		local now = os.clock()
		if not tool or not def or def.kind ~= "Hitscan" or now < s.reloadingUntil then
			return
		end
		local gun = def :: Weapons.Hitscan
		if ammoOf(tool, gun.magazine) >= gun.magazine then
			return
		end
		s.reloadingUntil = now + gun.reloadTime
		task.delay(gun.reloadTime, function()
			local _, _, still = Common.equipped(player)
			if still == tool then
				tool:SetAttribute("Ammo", gun.magazine)
			end -- switching weapons cancels the reload (design choice)
		end)
	end)
end

return Hitscan
