# Recipe: hitscan gun (client prediction, server raycast, ammo/reload, tracers)

Evidence: math CLI-EXECUTED (`examples/tests/combat.spec.luau`, 6 tests) · server/client TYPECHECKED · **not run
in Studio**. Side: server authority, client feedback. Needs: [health & damage](health-damage.md).
Chapter: [combat](../../handbook/roblox/15-combat.md) (lag compensation theory).

## Architecture
```text
Client: Activated → local gate (ammo attr, rpm) → aim: camera ray finds target point → origin = head,
        dir = (target - head).Unit → local raycast → tracer now → HitscanFire:FireServer(origin, dir)
Server: flood guard → equipped Hitscan tool → not reloading, rpm (15 % tolerance) → origin ≤ 8 studs from server
        head AND not through a wall → ammo (server attribute) → server raycast from origin → falloff × headshot
        → Damage.apply → HitConfirm to shooter · ShotFx (unreliable) to all for tracers
```
Why:
- **Fire from the head toward what the camera sees** — works in first and third person, and the server can check
  the origin against the head. Firing from the camera position fails server validation in third person.
- **Server raycast decides.** The client's raycast is only for the instant tracer; hit markers wait for
  `HitConfirm` (no fake hits).
- **Ammo lives in a server-owned Tool attribute** — replicated for UI, unforgeable.
- **Tracers for others via UnreliableRemoteEvent**: cosmetic, latest-wins, small payload.

## Code
Shared math (portable vectors, CLI-tested):
<!-- code: examples/combat/ReplicatedStorage/Combat/CombatMath.luau -->
```luau
-- file: examples/combat/ReplicatedStorage/Combat/CombatMath.luau
--!strict
-- Pure combat math shared by server validation and client prediction.
-- "Portable vectors": only operators and .X/.Y/.Z are used, so the same code runs on Roblox Vector3 values and on
-- the Luau CLI's native vectors (examples/tests/combat.spec.luau). Never constructs Vector3s itself.
-- Status: TYPECHECKED + CLI-EXECUTED.
local CombatMath = {}

function CombatMath.length(v: Vector3): number
	return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end

function CombatMath.dot(a: Vector3, b: Vector3): number
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

function CombatMath.finite(v: Vector3): boolean
	local s = v.X + v.Y + v.Z
	return s == s and s ~= math.huge and s ~= -math.huge
end

-- Target inside a horizontal cone in front of `origin` (melee). Height is checked separately by the caller's box.
function CombatMath.inCone(origin: Vector3, forward: Vector3, target: Vector3, reach: number, halfAngleDeg: number): boolean
	local dx, dz = target.X - origin.X, target.Z - origin.Z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist > reach then
		return false
	end
	if dist < 1e-3 then
		return true
	end
	local fl = math.sqrt(forward.X * forward.X + forward.Z * forward.Z)
	if fl < 1e-6 then
		return false
	end
	local cos = (forward.X * dx + forward.Z * dz) / (fl * dist)
	return cos >= math.cos(math.rad(halfAngleDeg))
end

-- Minimum seconds between shots for `rpm`, with a tolerance fraction for network jitter (0.1 = 10 % faster allowed).
function CombatMath.canFire(lastShot: number, now: number, rpm: number, tolerance: number): boolean
	return now - lastShot >= (60 / rpm) * (1 - tolerance)
end

-- Damage with linear falloff between falloffStart and range.
function CombatMath.falloff(damage: number, distance: number, falloffStart: number, range: number, minMult: number): number
	if distance <= falloffStart then
		return damage
	end
	local t = math.clamp((distance - falloffStart) / math.max(range - falloffStart, 1e-6), 0, 1)
	return damage * (1 + (minMult - 1) * t)
end

-- Kinematic projectile: position after t seconds (gravity is a downward acceleration vector).
function CombatMath.ballistic(origin: Vector3, velocity: Vector3, gravity: Vector3, t: number): Vector3
	return origin + velocity * t + gravity * (0.5 * t * t)
end

return table.freeze(CombatMath)
```
<!-- /code -->

Shared server helpers (remotes, equipped weapon, shot validation) — also used by melee and projectiles:
<!-- code: examples/combat/ServerScriptService/Combat/Common.luau -->
```luau
-- file: examples/combat/ServerScriptService/Combat/Common.luau
--!strict
-- Shared server helpers for weapons: remotes, equipped-weapon lookup, per-player state, flood guard, shot checks.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
local Validate = require(ReplicatedStorage.Lib.Validate)
local Weapons = require(ReplicatedStorage.Combat.Weapons)

local Common = {}

Common.MAX_ORIGIN_OFFSET = 8 -- studs between a claimed shot origin and the server-side head (latency + muzzle)
Common.FIRE_TOLERANCE = 0.15 -- accept shots up to 15 % faster than rpm (network jitter bunches packets)

export type State = { lastFire: number, busyUntil: number, reloadingUntil: number }
local states: { [Player]: State } = {}
local limiter = TokenBucket.new({ Combat = { capacity = 20, rate = 15 } }) -- coarse flood guard for all weapon remotes

local folder = ReplicatedStorage:FindFirstChild("CombatRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "CombatRemotes"
	folder.Parent = ReplicatedStorage
end

function Common.remote(name: string, unreliable: boolean?): Instance
	local r = Instance.new(if unreliable then "UnreliableRemoteEvent" else "RemoteEvent")
	r.Name = name
	r.Parent = folder
	return r
end

Common.hitConfirm = Common.remote("HitConfirm") :: RemoteEvent -- server → attacker: (amount, headshot)

function Common.allow(player: Player): boolean
	return limiter:allow(player, "Combat", os.clock())
end

function Common.state(player: Player): State
	local s = states[player]
	if not s then
		s = { lastFire = -math.huge, busyUntil = 0, reloadingUntil = 0 }
		states[player] = s
	end
	return s
end

function Common.forget(player: Player)
	states[player] = nil
	limiter:forget(player)
end

-- The weapon the SERVER sees equipped (Tool parented to the living character) and its config.
function Common.equipped(player: Player): (Model?, Humanoid?, Tool?, Weapons.Weapon?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil, nil, nil, nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("WeaponId")
	return character, humanoid, tool, if type(id) == "string" then Weapons[id] else nil
end

function Common.humanoidOf(inst: Instance): Humanoid?
	local model = inst:FindFirstAncestorOfClass("Model")
	while model do
		local h = model:FindFirstChildOfClass("Humanoid")
		if h then
			return h
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function Common.excludeParams(exclude: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.ExcludeInstances = exclude
	return params
end

-- World geometry between two points? (hits on characters don't count as blocking)
function Common.blocked(from: Vector3, to: Vector3, exclude: { Instance }): boolean
	local hit = Workspace:Raycast(from, to - from, Common.excludeParams(exclude))
	return hit ~= nil and Common.humanoidOf(hit.Instance) == nil
end

-- Validates a client-claimed shot (origin near the head, not through a wall; unit direction). nil = reject.
function Common.shot(character: Model, rawOrigin: unknown, rawDirection: unknown): (Vector3?, Vector3?)
	local origin = Validate.vector3(rawOrigin, 1e6)
	local direction = Validate.unitVector(rawDirection, 0.02)
	local head = character:FindFirstChild("Head")
	if not origin or not direction or not head or not head:IsA("BasePart") then
		return nil, nil
	end
	if (origin - head.Position).Magnitude > Common.MAX_ORIGIN_OFFSET
		or Common.blocked(head.Position, origin, { character }) then
		return nil, nil
	end
	return origin, direction
end

return Common
```
<!-- /code -->

Server hitscan:
<!-- code: examples/combat/ServerScriptService/Combat/Hitscan.luau -->
```luau
-- file: examples/combat/ServerScriptService/Combat/Hitscan.luau
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
```
<!-- /code -->

Client (all three weapon kinds + projectile visuals):
<!-- code: examples/combat/StarterPlayer/StarterPlayerScripts/WeaponClient.client.luau -->
```luau
-- file: examples/combat/StarterPlayer/StarterPlayerScripts/WeaponClient.client.luau
--!strict
-- Client weapons: input → local feedback (tracer, sound/anim hooks) → intent to the server. Renders other players'
-- tracers and every projectile from server messages. Never decides hits or damage.
-- Status: TYPECHECKED. Not run in Studio.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Combat.Weapons)
local CombatMath = require(ReplicatedStorage.Combat.CombatMath)

local player = Players.LocalPlayer :: Player
local remotes = ReplicatedStorage:WaitForChild("CombatRemotes", 30)
assert(remotes, "CombatRemotes missing (is WeaponServer running?)")
local function get(name: string): any
	return remotes:WaitForChild(name, 30)
end
local meleeSwing: RemoteEvent = get("MeleeSwing")
local hitscanFire: RemoteEvent = get("HitscanFire")
local projectileLaunch: RemoteEvent = get("ProjectileLaunch")
local reload: RemoteEvent = get("Reload")
local shotFx: UnreliableRemoteEvent = get("ShotFx")
local projectileSpawn: RemoteEvent = get("ProjectileSpawn")
local projectileHit: RemoteEvent = get("ProjectileHit")
local hitConfirm: RemoteEvent = get("HitConfirm")

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalCombatFx" -- client-only instances, never replicated
fxFolder.Parent = Workspace

local function fxPart(size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false -- our own raycasts must not hit visuals
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	return p
end

local function tracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local p = fxPart(Vector3.new(0.06, 0.06, length), Color3.fromRGB(255, 225, 160))
	p.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	p.Parent = fxFolder
	task.delay(0.05, p.Destroy, p)
end

-- Aim: find what the camera looks at, then fire from the head toward that point (works in 1st and 3rd person).
local function aim(range: number): (Vector3?, Vector3?)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local camera = Workspace.CurrentCamera
	if not character or not head or not head:IsA("BasePart") or not camera then
		return nil, nil
	end
	local params = RaycastParams.new()
	params.ExcludeInstances = { character, fxFolder }
	local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * range, params)
	local target = if hit then hit.Position else ray.Origin + ray.Direction * range
	local origin = head.Position
	local dir = target - origin
	if dir.Magnitude < 1e-3 then
		return nil, nil
	end
	return origin, dir.Unit
end

local function equippedWeapon(): (Tool?, Weapons.Weapon?)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("WeaponId")
	return tool, if type(id) == "string" then Weapons[id] else nil
end

local lastLocalFire = -math.huge
local function onActivated()
	local tool, def = equippedWeapon()
	if not tool or not def then
		return
	end
	local now = os.clock()
	if def.kind == "Hitscan" then
		local gun = def :: Weapons.Hitscan
		local ammo = tool:GetAttribute("Ammo")
		if (type(ammo) == "number" and ammo <= 0) or not CombatMath.canFire(lastLocalFire, now, gun.rpm, 0) then
			return -- client-side gating mirrors the server so honest players never get rejected shots
		end
		local origin, direction = aim(gun.range)
		if origin and direction then
			lastLocalFire = now
			local params = RaycastParams.new()
			params.ExcludeInstances = { player.Character :: Model, fxFolder }
			local predicted = Workspace:Raycast(origin, direction * gun.range, params)
			tracer(origin, if predicted then predicted.Position else origin + direction * gun.range)
			hitscanFire:FireServer(origin, direction)
		end
	elseif def.kind == "Melee" then
		meleeSwing:FireServer() -- play the swing animation here (Animator on the character) for instant feedback
	elseif def.kind == "Projectile" then
		local launcher = def :: Weapons.Projectile
		if not CombatMath.canFire(lastLocalFire, now, launcher.rpm, 0) then
			return
		end
		local origin, direction = aim(500)
		if origin and direction then
			lastLocalFire = now
			projectileLaunch:FireServer(origin, direction)
		end
	end
end

-- Bind Activated for whichever weapon Tool gets equipped.
local toolConn: RBXScriptConnection? = nil
local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and child:GetAttribute("WeaponId") ~= nil then
			if toolConn then
				toolConn:Disconnect()
			end
			toolConn = child.Activated:Connect(onActivated)
		end
	end)
	character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") and toolConn then
			toolConn:Disconnect()
			toolConn = nil
		end
	end)
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end

ContextActionService:BindAction("Reload", function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		reload:FireServer()
	end
	return Enum.ContextActionResult.Pass
end, true, Enum.KeyCode.R, Enum.KeyCode.ButtonX)

-- Other players' tracers (own shots were already drawn locally).
shotFx.OnClientEvent:Connect(function(shooterId: number, from: Vector3, to: Vector3)
	if shooterId ~= player.UserId then
		tracer(from, to)
	end
end)

hitConfirm.OnClientEvent:Connect(function(amount: number, headshot: boolean)
	-- Hit marker / sound hook. Server-confirmed, so it never lies about hits.
	print(`hit {math.floor(amount)}{if headshot then " (head)" else ""}`)
end)

-- Projectile visuals: every client simulates the server's curve from the spawn time.
type Visual = { part: Part, origin: Vector3, velocity: Vector3, gravity: Vector3, spawnTime: number }
local visuals: { [number]: Visual } = {}

projectileSpawn.OnClientEvent:Connect(function(id: number, origin: Vector3, velocity: Vector3, gravity: number,
	serverTime: number)
	local part = fxPart(Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(255, 90, 50))
	part.Shape = Enum.PartType.Ball
	part.Parent = fxFolder
	visuals[id] = {
		part = part,
		origin = origin,
		velocity = velocity,
		gravity = Vector3.new(0, -gravity, 0),
		spawnTime = serverTime,
	}
end)

projectileHit.OnClientEvent:Connect(function(id: number, _at: Vector3)
	local v = visuals[id]
	if v then
		visuals[id] = nil
		v.part:Destroy() -- spawn an explosion effect at `_at` here
	end
end)

RunService.PreRender:Connect(function()
	local now = Workspace:GetServerTimeNow()
	for id, v in visuals do
		local t = now - v.spawnTime
		if t > 10 then -- hit message lost or never sent: don't leak
			visuals[id] = nil
			v.part:Destroy()
			continue
		end
		v.part.Position = CombatMath.ballistic(v.origin, v.velocity, v.gravity, t)
	end
end)
```
<!-- /code -->

## Setup
`Tool` in `StarterPack` with `Handle`, attribute `WeaponId = "Pistol"`. For a real muzzle origin, keep the server
check against the head (the muzzle is within `MAX_ORIGIN_OFFSET`). Replace the neon-part tracer with a `Beam` or a
pooled part ([object pooling](object-pooling.md)) for high fire rates.

## Lag compensation (not implemented here — add when PvP at 100+ ms feels unfair)
1. Server records every character's root CFrame at 20–30 Hz in a ring buffer (last ~1 s).
2. On a shot: `rewind = math.min(player:GetNetworkPing() / 2 + interpolationDelay, 0.3)` — measure your
   interpolation delay; don't guess it in code comments.
3. Test the ray against hitboxes reconstructed at `now - rewind` (math: ray vs oriented boxes, or temporary
   CanQuery parts in a separate folder), then still require LOS against static geometry **now**.
4. Cap rewind; reject targets that moved implausibly. Victims at high ping will sometimes be "shot behind walls" —
   that's the trade-off; document it.

## How to test
| Case | Expected |
|---|---|
| Normal shooting, 2 players | tracer instantly; damage applied; hit marker only on confirmed hits |
| Headshot | ×2 damage (`headMultiplier`) |
| 200+ studs | falloff to 50 % at `range` |
| Empty magazine | no shots client-side; server rejects forced shots; R reloads after 1.6 s |
| Exploit: `HitscanFire:FireServer(Vector3.new(0, 1000, 0), dir)` | origin too far from head → rejected |
| Exploit: origin 6 studs ahead through a thin wall | `blocked(head, origin)` → rejected |
| Exploit: 50 shots/s | rpm check (+15 %) and flood guard |
| Exploit: `dir` with NaN or length 5 | `Validate.unitVector` → rejected |
| Network simulator 250 ms | shots still register on slow targets; moving targets need lag compensation |

## Pitfalls
- `workspace:Raycast(origin, dir)` with a unit vector is a 1-stud ray — multiply by range.
- Exclude the shooter's character, and never let visual parts be hit (`CanQuery = false`).
- Accessories/hats: `humanoidOf` walks up to the character model, so hat hits count as body hits; decide whether
  accessory handles should count as headshots (`result.Instance.Parent:IsA("Accessory")`).
- Don't `FireAllClients` per bullet at 1000 rpm with big payloads — batch or drop tracers for distant shooters.

Sources: cd:workspace/raycasting, cd:reference/engine/classes/WorldRoot, cd:reference/engine/classes/Player,
cd:reference/engine/classes/UnreliableRemoteEvent, cd:reference/engine/classes/Camera,
cd:scripting/security/security-tactics, cd:studio/network-simulator.
