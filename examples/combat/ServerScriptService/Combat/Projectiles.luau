--!strict
-- Projectiles: server-simulated kinematic shots (no physics parts), one Heartbeat loop for all of them.
-- Clients get (id, origin, velocity, gravity, serverTime) and simulate the same curve for visuals.
-- Status: TYPECHECKED (ballistics CLI-EXECUTED). Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Combat.Weapons)
local CombatMath = require(ReplicatedStorage.Combat.CombatMath)
local Common = require(ServerScriptService.Combat.Common)
local Damage = require(ServerScriptService.Combat.Damage)

local Projectiles = {}

type Shot = {
	id: number,
	owner: Player,
	def: Weapons.Projectile,
	origin: Vector3,
	velocity: Vector3,
	gravity: Vector3,
	spawn: number, -- server os.clock()
	pos: Vector3,
	params: RaycastParams,
	exclude: { Instance },
}
local shots: { [number]: Shot } = {}
local nextId = 0
local hitRemote: RemoteEvent

local function explode(shot: Shot, at: Vector3)
	shots[shot.id] = nil
	hitRemote:FireAllClients(shot.id, at)
	local overlap = OverlapParams.new()
	overlap.ExcludeInstances = shot.exclude
	local done: { [Humanoid]: true } = {}
	for _, part in Workspace:GetPartBoundsInRadius(at, shot.def.splashRadius, overlap) do
		local target = Common.humanoidOf(part)
		local targetRoot = target and target.RootPart
		if not target or not targetRoot or done[target] then
			continue
		end
		done[target] = true
		if Common.blocked(at, targetRoot.Position, { target.Parent :: Instance }) then
			continue -- walls absorb splash
		end
		local distance = (targetRoot.Position - at).Magnitude
		local amount = shot.def.damage * (1 - 0.5 * math.clamp(distance / shot.def.splashRadius, 0, 1))
		if Damage.apply(target, amount, { attacker = shot.owner, weapon = "Projectile" }) then
			Common.hitConfirm:FireClient(shot.owner, amount, false)
		end
	end
end

local function step()
	local now = os.clock()
	for _, shot in shots do
		local t = math.min(now - shot.spawn, shot.def.lifetime)
		local nextPos = CombatMath.ballistic(shot.origin, shot.velocity, shot.gravity, t)
		local delta = nextPos - shot.pos
		if delta.Magnitude > 1e-4 then
			local hit = if shot.def.radius > 0
				then Workspace:Spherecast(shot.pos, shot.def.radius, delta, shot.params)
				else Workspace:Raycast(shot.pos, delta, shot.params)
			if hit then
				explode(shot, hit.Position)
				continue
			end
		end
		shot.pos = nextPos
		if t >= shot.def.lifetime then
			explode(shot, nextPos)
		end
	end
end

function Projectiles.start()
	local launch = Common.remote("ProjectileLaunch") :: RemoteEvent
	local spawnRemote = Common.remote("ProjectileSpawn") :: RemoteEvent
	hitRemote = Common.remote("ProjectileHit") :: RemoteEvent

	launch.OnServerEvent:Connect(function(player: Player, rawOrigin: unknown, rawDirection: unknown)
		if not Common.allow(player) then
			return
		end
		local character, _, _, def = Common.equipped(player)
		if not character or not def or def.kind ~= "Projectile" then
			return
		end
		local launcher = def :: Weapons.Projectile
		local s = Common.state(player)
		local now = os.clock()
		if not CombatMath.canFire(s.lastFire, now, launcher.rpm, Common.FIRE_TOLERANCE) then
			return
		end
		local origin, direction = Common.shot(character, rawOrigin, rawDirection)
		if not origin or not direction then
			return
		end
		s.lastFire = now
		nextId += 1
		local shot: Shot = {
			id = nextId,
			owner = player,
			def = launcher,
			origin = origin,
			velocity = direction * launcher.speed,
			gravity = Vector3.new(0, -launcher.gravity, 0),
			spawn = now,
			pos = origin,
			params = Common.excludeParams({ character }),
			exclude = { character },
		}
		shots[shot.id] = shot
		spawnRemote:FireAllClients(shot.id, origin, shot.velocity, launcher.gravity, Workspace:GetServerTimeNow())
	end)

	RunService.Heartbeat:Connect(step)
end

-- Remove a leaving player's shots (their character is gone; clients remove the visuals).
function Projectiles.forget(player: Player)
	for id, shot in shots do
		if shot.owner == player then
			shots[id] = nil
			hitRemote:FireAllClients(id, shot.pos)
		end
	end
end

return Projectiles
