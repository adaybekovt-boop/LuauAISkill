--!strict
-- Melee: client sends "MeleeSwing" (no arguments). The server runs the attack timeline (windup → active → recovery)
-- and detects hits itself with an overlap box + cone + line-of-sight, using server-side positions.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Combat.Weapons)
local CombatMath = require(ReplicatedStorage.Combat.CombatMath)
local Common = require(ServerScriptService.Combat.Common)
local Damage = require(ServerScriptService.Combat.Damage)

local Melee = {}

local function sample(player: Player, def: Weapons.Melee, hitSet: { [Humanoid]: true })
	local character, humanoid, _, current = Common.equipped(player)
	local root = humanoid and humanoid.RootPart
	if not character or not root or current ~= def then
		return -- died or switched weapons during the swing
	end
	local overlap = OverlapParams.new()
	overlap.ExcludeInstances = { character }
	local box = root.CFrame * CFrame.new(0, 0, -def.reach / 2)
	for _, part in Workspace:GetPartBoundsInBox(box, Vector3.new(def.reach * 1.5, 7, def.reach), overlap) do
		local target = Common.humanoidOf(part)
		local targetRoot = target and target.RootPart
		if not target or not targetRoot or hitSet[target] then
			continue
		end
		if not CombatMath.inCone(root.Position, root.CFrame.LookVector, targetRoot.Position, def.reach + 1, def.halfAngle) then
			continue
		end
		if Common.blocked(root.Position, targetRoot.Position, { character, target.Parent :: Instance }) then
			continue
		end
		hitSet[target] = true -- one hit per target per swing
		if Damage.apply(target, def.damage, { attacker = player, weapon = "Melee" }) then
			Common.hitConfirm:FireClient(player, def.damage, false)
		end
	end
end

function Melee.start()
	local swing = Common.remote("MeleeSwing") :: RemoteEvent
	swing.OnServerEvent:Connect(function(player: Player)
		if not Common.allow(player) then
			return
		end
		local _, _, _, def = Common.equipped(player)
		local s = Common.state(player)
		local now = os.clock()
		if not def or def.kind ~= "Melee" or now < s.busyUntil then
			return -- not holding a melee weapon, or still in the previous swing
		end
		local melee = def :: Weapons.Melee
		s.busyUntil = now + melee.windup + melee.active + melee.recovery
		local hitSet: { [Humanoid]: true } = {}
		-- Two samples across the active window catch targets that step in mid-swing.
		task.delay(melee.windup, sample, player, melee, hitSet)
		task.delay(melee.windup + melee.active, sample, player, melee, hitSet)
	end)
end

return Melee
