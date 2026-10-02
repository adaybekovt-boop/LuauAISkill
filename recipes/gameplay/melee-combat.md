# Recipe: melee combat (server attack timeline, box + cone + LOS hits)

## When NOT to use
Do not use client-reported hit lists as damage authority; competitive rollback requires additional design.

Evidence: cone math CLI-EXECUTED (`examples/tests/combat.spec.luau`) · server/client TYPECHECKED · **not run in
Studio**. Side: server authority, client feedback. Needs: [health & damage](health-damage.md), shared helpers
`examples/combat/ServerScriptService/Combat/Common.luau` and `CombatMath` (embedded in [hitscan](hitscan-gun.md)).
Chapter: [combat](../../handbook/roblox/15-combat.md).

## Architecture
```text
Client: Tool.Activated → play swing animation locally (instant feel) → MeleeSwing:FireServer()   (no arguments!)
Server: flood guard → equipped Tool has WeaponId of kind "Melee" → not busy (windup+active+recovery)
        → t = windup: sample 1 · t = windup+active: sample 2
        sample: GetPartBoundsInBox in front of the SERVER root → unique Humanoids → horizontal cone → LOS → Damage
```
Why:
- **The client sends no targets, positions or damage** — nothing to spoof. It only says "I swung".
- **The server owns the timeline**, so animation-cancel exploits or spam can't create extra hit windows.
- **Box query + cone** is cheap, predictable and independent of limb collision; two samples cover targets
  walking into the swing.
- **Trade-off**: the server sees positions ~ping/2 old for the attacker and the victim → at high ping hits feel
  slightly late. If your game needs frame-exact melee, switch to client-detected hits + server validation (reach,
  cone, LOS, attack active, not already hit) — see the chapter's table.

## Code
Weapon configs (shared):
<!-- code: examples/combat/ReplicatedStorage/Combat/Weapons.luau -->
```luau
-- file: examples/combat/ReplicatedStorage/Combat/Weapons.luau
--!strict
-- Weapon definitions (shared). Clients read them for prediction/visuals; the server uses the same numbers
-- as the authority. A Tool's "WeaponId" attribute selects the entry.
export type Hitscan = {
	kind: "Hitscan",
	damage: number,
	headMultiplier: number,
	range: number,
	falloffStart: number, -- studs; damage lerps to damage * minFalloff at `range`
	minFalloff: number,
	rpm: number,
	magazine: number,
	reloadTime: number,
}
export type Melee = {
	kind: "Melee",
	damage: number,
	reach: number, -- studs in front of the root
	halfAngle: number, -- degrees of the hit cone
	windup: number, -- seconds before the hit window (telegraph)
	active: number, -- hit window length
	recovery: number, -- after the window, before the next attack
}
export type Projectile = {
	kind: "Projectile",
	damage: number,
	speed: number,
	gravity: number, -- studs/s² downward (workspace default is 196.2)
	radius: number, -- 0 = raycast, > 0 = spherecast
	lifetime: number,
	splashRadius: number,
	rpm: number,
}
export type Weapon = Hitscan | Melee | Projectile

local Weapons: { [string]: Weapon } = {
	Pistol = {
		kind = "Hitscan",
		damage = 22,
		headMultiplier = 2,
		range = 300,
		falloffStart = 60,
		minFalloff = 0.5,
		rpm = 300,
		magazine = 12,
		reloadTime = 1.6,
	},
	Pipe = { kind = "Melee", damage = 30, reach = 6, halfAngle = 55, windup = 0.25, active = 0.15, recovery = 0.45 },
	FlareGun = {
		kind = "Projectile",
		damage = 45,
		speed = 120,
		gravity = 60,
		radius = 0.4,
		lifetime = 4,
		splashRadius = 8,
		rpm = 40,
	},
}

return table.freeze(Weapons)
```
<!-- /code -->

Server melee:
<!-- code: examples/combat/ServerScriptService/Combat/Melee.luau -->
```luau
-- file: examples/combat/ServerScriptService/Combat/Melee.luau
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
```
<!-- /code -->
Client side: `WeaponClient.client.luau` (embedded in [hitscan](hitscan-gun.md)) fires `MeleeSwing` on `Activated`.

## Setup
A `Tool` with a `Handle`, attribute `WeaponId = "Pipe"`, in `StarterPack`. Add an `Animation` and play it from the
client on activation (Animator on the local character — the owner's animations replicate).

## Tuning
| Value | Effect | Typical |
|---|---|---|
| `windup` | telegraph time; longer = readable, dodgeable | 0.15–0.4 s |
| `active` | hit window | 0.1–0.2 s |
| `recovery` | punish whiffs; sets attack rate | 0.3–0.6 s |
| `reach` | studs from root centre | 5–7 (R15 arm ≈ 3) |
| `halfAngle` | forgiveness | 45–70° |

## How to test
- Two players, Network simulator 150 ms: hits register when visually close; no hits through walls (`blocked`).
- Spam click: at most one swing per `windup+active+recovery`.
- Temporary client script firing `MeleeSwing` 100× per second → flood guard + busy check; one hit per target per swing.
- Unequip mid-swing → no hit (weapon identity re-checked at each sample).

## Extensions
- Combos: server keeps `comboIndex` + window after recovery; configs per index (damage, reach, timing).
- Block/parry: server state `Blocking` with start time; parry if hit resolves within `parryWindow + ping/2`.
- Knockback: short `LinearVelocity` on the victim root created by the server (owner simulates it), 0.2–0.4 s.
- Hitstop: attacker client freezes its animation 50 ms on `HitConfirm`.

Sources: cd:reference/engine/classes/WorldRoot, cd:workspace/collisions, cd:reference/engine/classes/Tool,
cd:animation/using, cd:scripting/security/security-tactics.
