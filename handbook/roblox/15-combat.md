# Combat: melee, hitscan, projectiles, lag compensation, reactions, ragdoll

## TL;DR
- Let clients predict presentation and servers decide damage.
- Model combat phases and valid transitions explicitly.
- Choose hit detection for the weapon and latency model.
- Validate timing, range, resources, and team rules.
- Test respawn, interruption, duplicate requests, and death cleanup.

Read when: any damage-dealing system, PvP, PvE, weapons, abilities.
Related: [security](04-security.md), [networking](03-networking.md), [physics queries](09-physics.md#spatial-queries),
[animation](16-animation.md), recipes: [melee combat](../../recipes/gameplay/melee-combat.md),
[hitscan gun](../../recipes/gameplay/hitscan-gun.md), [projectile weapon](../../recipes/gameplay/projectile-weapon.md),
[health/damage](../../recipes/gameplay/health-damage.md), [ragdoll](../../recipes/gameplay/ragdoll.md).

## The split
| Client (responsiveness) | Server (authority) |
|---|---|
| input, animation start, muzzle flash, tracer, sound, hit marker **prediction**, camera recoil | weapon state (equipped, ammo, cooldown, reload), combat state machine (idle/windup/active/recovery/stunned/dead), hit validation, damage, knockback, death, rewards |
| sends intent: `Attack(comboIndex, aimDir, clientTime)`, `Fire(origin, dir, shotId)` | computes outcome, replicates results (health changes replicate automatically; hit events to attacker/victim) |
Never accept damage numbers, hit confirmations without validation, "I killed X", or cooldown state from the client.

## Combat state machine (server; mirrored on client for feel)
```text
Idle → (attack input, not on cooldown, has stamina) → Windup (telegraph, cancellable?) → Active (hit window)
     → Recovery → Idle
Any → Stunned (on hit/parry) → Idle        Any → Dead
Block: Idle ↔ Blocking (stamina drain; damage reduction)   Parry: first N ms of Blocking = parry window
Dodge: short state with i-frames (server ignores hits), cooldown
```
Store per-character server state `{ state, stateEnds, attackId, comboIndex, lastHitIds }`. One damage per target per
attack id (dedupe set). Durations are data (config per weapon), not magic numbers in handlers.

## Melee hit detection (choose one)
| Method | How | Trade-off |
|---|---|---|
| **Server-side sweep (recommended baseline)** | during Active, every server step: `Blockcast`/`Spherecast`/`GetPartBoundsInBox` from weapon position last step → this step, using server-side character pose | authoritative, no trust; slight latency mismatch with what attacker saw |
| Client-detected + server validation | client does the sweep (matches animation), sends `hits = {targetModel...}` with attackId; server checks: attack active, target within reach (+latency slack), in front cone, LOS, not already hit, alive, not same team | responsive; must validate carefully |
| `Touched` on weapon | fires on the simulating machine; misses fast swings; client-owned tools can fake | avoid as sole method |
Hitboxes: use simple invisible parts or math (distance + angle cone) around the character root rather than precise
mesh limbs. Keep server hit logic independent of client-owned limb presence.

```luau
--!strict
-- Server: cone + reach check (cheap) before any raycast.
local function inMeleeRange(attackerRoot: BasePart, targetRoot: BasePart, reach: number, halfAngleDeg: number): boolean
	local offset = targetRoot.Position - attackerRoot.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local dist = flat.Magnitude
	if dist > reach or dist < 1e-3 then return dist <= reach end
	local look = attackerRoot.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z).Unit
	return flatLook:Dot(flat / dist) >= math.cos(math.rad(halfAngleDeg))
end
print(inMeleeRange)
```

## Hitscan
Client: raycast from camera/muzzle for instant tracer + predicted hit marker; send `Fire(origin, direction, shotId)`
(optionally claimed target). Server validation:
1. rate: time since last shot ≥ weapon interval (with small tolerance); ammo > 0; not reloading; alive.
2. origin within ~4–8 studs of the server-side character head/root (latency slack).
3. direction finite, unit-ish; spread within weapon spread (+tolerance).
4. server raycast (optionally lag-compensated) from origin along direction up to weapon range; excluding shooter.
5. hit must be an enemy character part, alive, not same team; static geometry between origin and hit → reject.
6. apply damage (headshot multiplier from server-side part name/type), notify attacker & victim.

## Lag compensation (hitscan PvP)
- Server keeps a ring buffer of each character's root CFrame (and hitbox) for the last ~1 s at 20–60 Hz.
- On a shot, estimate the shooter's view time: `now - (ping / 2) - interpolationDelay` (`player:GetNetworkPing()`
  returns round-trip seconds; clamp rewind to ≤ 250–300 ms). Test hits against rewound hitboxes (math on stored
  CFrames, or temporarily placed hitbox parts in a separate WorldModel/folder with `CanQuery`).
- Trade-off: "shot behind a wall" complaints from victims at high ping. Cap rewind; reject if target moved
  implausibly.
- Without lag compensation, use generous server hitboxes and client-claimed targets validated by distance.

## Projectiles
| Approach | Use |
|---|---|
| Server-simulated kinematic projectile (no physics): position/velocity/gravity advanced each Heartbeat, raycast from previous to next position | rockets, arrows, grenades that matter; authoritative |
| Client-rendered visuals: server sends `(origin, velocity, spawnTime, id)`, every client simulates the same math locally for visuals | smooth visuals without replicating parts |
| Physics parts (unanchored) | only for cosmetic debris; network ownership makes them exploitable and jittery |
- Thick projectiles: `Spherecast` per step. Don't use `Touched` for bullets (tunneling, ownership).
- Server authority mode offers predictive instance creation ("stitching") for projectiles
  ([05](05-server-authority.md)).

## Damage, health, death
- Server: `humanoid:TakeDamage(n)` respects `ForceField`; or set `Health` directly for custom rules. Clamp, round
  once, log source (`attacker`, weapon, attackId) in a server-side "last damage" record for kill credit.
- Custom health (non-Humanoid NPCs): attribute `Health` on the model, server-only writes.
- Death: `Humanoid.Died` (server) → credit kill, drop loot, start respawn timer; client plays effects.
- Regeneration: default `Health` script in characters regenerates; remove/replace it for custom rules (add your own
  `Health` Script to `StarterCharacterScripts` to override the default).

## Knockback and stun on player characters
- Players own their character physics; setting `AssemblyLinearVelocity` from the server on another player's root
  is unreliable. Reliable options: (a) server creates a short-lived `LinearVelocity`/`VectorForce` constraint on
  the victim root (constraints replicate; the owning client simulates it), destroyed after 0.2–0.4 s; (b)
  `FireClient(victim, "Knockback", impulse)` and the victim applies `ApplyImpulse` locally — exploitable (victim can
  ignore), fine for PvE.
- Stun: server state + `FireClient` to lock victim input locally; server rejects victim actions while stunned.

## Blocking, parry, dodge
Timing windows are server-evaluated with latency tolerance: parry succeeds if the server receives `BlockStart` ≤
`parryWindow + ping/2` before the hit resolves. Keep windows generous (150–250 ms) for playability. I-frames:
server ignores hits while `state == Dodge`.

## Hit reactions and feedback
Victim: flinch animation (Action priority, short), hit sound, screen vignette/shake small; attacker: hit marker,
hitstop (freeze-frame 30–80 ms on the attacker's client only), sound. Reactions are cosmetic and client-side; the
server decides whether they happen.

## Ragdoll (on death or knock-down)
Server: set `Humanoid.BreakJointsOnDeath = false`; on death replace each `Motor6D` with a `BallSocketConstraint`
between the same attachments (limits enabled), add `NoCollisionConstraint`s between adjacent limbs, enable limb
collisions; owning client sets `Humanoid:ChangeState(Enum.HumanoidStateType.Physics)` (or Ragdoll) so the Humanoid
stops fighting physics. For NPCs the server owns them: do both on the server. Full code:
[ragdoll recipe](../../recipes/gameplay/ragdoll.md).

## Checklist
- [ ] Server state machine; one damage per target per attack id.
- [ ] Rate limits = weapon fire rate; ammo/cooldowns on server.
- [ ] Range, cone, LOS, team, alive checks on server.
- [ ] Latency tolerance documented (numbers) and tested with Studio network simulator (100–250 ms).
- [ ] Hit feedback predicted on client, corrected by server result.
- [ ] Death/respawn resets combat state; connections cleaned.

Sources: cd:scripting/security/client-server-boundary, cd:scripting/security/security-tactics, cd:workspace/raycasting,
cd:reference/engine/classes/WorldRoot, cd:reference/engine/classes/Player, cd:reference/engine/classes/Humanoid,
cd:physics/mover-constraints, cd:physics/constraints/ball-socket, cd:projects/server-authority/techniques,
cd:scripting/multithreading, cd:studio/network-simulator.
