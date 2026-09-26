# Recipe: projectile weapon (server-simulated, client-rendered, splash damage)

Evidence: ballistics CLI-EXECUTED (`examples/tests/combat.spec.luau`) · server TYPECHECKED · **not run in Studio**.
Needs: [health & damage](health-damage.md), shared `Common`/`CombatMath`/client (embedded in [hitscan](hitscan-gun.md)).

## Architecture
```text
Client: Activated → aim (camera target, head origin) → ProjectileLaunch:FireServer(origin, dir)
Server: validate like hitscan (rpm, origin near head, not through wall) → Shot{origin, velocity, gravity, spawn}
        → ProjectileSpawn:FireAllClients(id, origin, velocity, gravity, serverTime)
        Heartbeat (ONE loop for all shots): p(t) = origin + v·t + ½g·t² ; cast from last p to new p
        (Spherecast if radius > 0) → hit or lifetime → explode: GetPartBoundsInRadius → LOS → falloff damage
        → ProjectileHit:FireAllClients(id, position)
Clients: simulate the same p(t) from serverTime each frame → visuals line up with the server without replicating parts
```
Why:
- **No physics parts**: unanchored projectiles get network ownership, jitter, `Touched` tunnelling and exploits.
  Kinematic math is deterministic on server and clients.
- **Casting between frames** (`prev → next`) can't tunnel through thin walls at any speed.
- **Closed-form position** (not incremental Euler) — server and clients agree regardless of frame rate.
- **Walls absorb splash**: LOS from the explosion to each target root.

## Code
<!-- code: examples/combat/ServerScriptService/Combat/Projectiles.luau -->
```luau
-- file: examples/combat/ServerScriptService/Combat/Projectiles.luau
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
```
<!-- /code -->
Client rendering is in `WeaponClient.client.luau` (`projectileSpawn` / `projectileHit` / `PreRender` loop).

## Latency notes
- The shooter sees their projectile appear after one round trip. To hide it, spawn a local predicted visual
  immediately and replace/merge it when `ProjectileSpawn` arrives (match by a client shot id you send along).
- Server authority mode (beta) offers predicted instance creation for projectiles — see
  [server authority](../../handbook/roblox/05-server-authority.md) before building your own prediction.

## How to test
- Fire at a wall 2 studs thick at high speed (`speed = 600`): always explodes at the wall (no tunnelling).
- Splash behind cover: player behind a wall inside `splashRadius` takes no damage; in the open takes 50–100 %.
- Two clients: projectile arcs identical on both; explosion position matches the server.
- 30 projectiles in flight: server Heartbeat cost stays small (MicroProfiler: one `Heartbeat` script entry).
- Exploit: `ProjectileLaunch` spam → rpm check; far origin → rejected.

## Pitfalls
- `Workspace:Spherecast` with a zero-length direction errors/does nothing — the code skips tiny deltas.
- Spawn/hit remotes are reliable (they must arrive once); don't send per-frame positions.
- Clean up per-player shots on leave (done in `Projectiles.forget`) and keep a client-side timeout so lost hit
  messages don't leak visuals.

Sources: cd:workspace/raycasting, cd:reference/engine/classes/WorldRoot, cd:reference/engine/classes/Workspace,
cd:physics/network-ownership, cd:projects/server-authority/techniques.
