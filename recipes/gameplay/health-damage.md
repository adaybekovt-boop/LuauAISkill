# Recipe: health & damage (single server entry point, kill credit, i-frames, spawn protection)

## When NOT to use
Do not layer this over an existing authoritative damage service without choosing one state owner.

Evidence: TYPECHECKED · **not run in Studio**. Side: server. Part of the combat example
(`examples/combat`), used by [melee](melee-combat.md), [hitscan](hitscan-gun.md), [projectile](projectile-weapon.md),
[ragdoll](ragdoll.md). Chapter: [combat](../../handbook/roblox/15-combat.md).

## Architecture
```text
Any weapon/hazard (server) ──► Damage.apply(humanoid, amount, {attacker, weapon, headshot})
   checks: amount finite > 0 · target alive · not self · not teammate (unless FRIENDLY_FIRE) · not invulnerable
   → round once → remember last hit (kill credit) → Humanoid:TakeDamage (respects ForceField) → damaged signal
Humanoid.Died ──► killed(victim, killer-if-hit-within-10s, weapon) → rewards, kill feed, stats
```
Why one entry point:
- Every rule (teams, i-frames, spawn protection, damage multipliers, logging) lives in one place; weapons can't
  forget a check.
- Kill credit survives indirect deaths (knocked off a ledge within `CREDIT_WINDOW`).
- `amount` always comes from server config; the function never takes numbers from remotes.

## Code
<!-- code: examples/combat/ServerScriptService/Combat/Damage.luau -->
```luau
-- file: examples/combat/ServerScriptService/Combat/Damage.luau
--!strict
-- Damage: the single server entry point for hurting anything. Handles alive/team/invulnerability checks,
-- ForceField (via Humanoid:TakeDamage), kill credit and a `killed` signal for rewards/kill feed.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Lib.Signal)

export type Source = { attacker: Player?, weapon: string, headshot: boolean? }

local CREDIT_WINDOW = 10 -- seconds: a fall/reset shortly after being hit still credits the attacker
local FRIENDLY_FIRE = false

local Damage = {}
-- killed(victimHumanoid, killer: Player?, weapon)
Damage.killed = Signal.new() :: Signal.Signal<Humanoid, Player?, string>
-- damaged(victimHumanoid, amount, source) — for hit markers/indicators (server → client notification is up to you)
Damage.damaged = Signal.new() :: Signal.Signal<Humanoid, number, Source>

type Record = { attacker: Player?, weapon: string, time: number, diedConn: RBXScriptConnection }
local lastHit: { [Humanoid]: Record } = {}

local function sameTeam(a: Player, b: Player): boolean
	return not a.Neutral and not b.Neutral and a.Team == b.Team -- Neutral players have no team
end

local function track(humanoid: Humanoid, source: Source)
	local record = lastHit[humanoid]
	if record then
		record.attacker, record.weapon, record.time = source.attacker, source.weapon, os.clock()
		return
	end
	local conn: RBXScriptConnection
	conn = humanoid.Died:Connect(function()
		conn:Disconnect()
		local r = lastHit[humanoid]
		lastHit[humanoid] = nil
		local credited = r and os.clock() - r.time <= CREDIT_WINDOW
		Damage.killed:fire(humanoid, if credited and r then r.attacker else nil, if r then r.weapon else "Unknown")
	end)
	lastHit[humanoid] = { attacker = source.attacker, weapon = source.weapon, time = os.clock(), diedConn = conn }
	humanoid.Destroying:Once(function()
		local r = lastHit[humanoid]
		if r then
			r.diedConn:Disconnect()
			lastHit[humanoid] = nil
		end
	end)
end

-- Returns true if damage was applied. `amount` is computed by the SERVER (weapon config), never by a client.
function Damage.apply(target: Humanoid, amount: number, source: Source): boolean
	if amount ~= amount or amount <= 0 or target.Health <= 0 then
		return false
	end
	local model = target.Parent
	if not model or not model:IsA("Model") then
		return false
	end
	local victimPlayer = Players:GetPlayerFromCharacter(model)
	local attacker = source.attacker
	if attacker and victimPlayer then
		if attacker == victimPlayer then
			return false
		end
		if not FRIENDLY_FIRE and sameTeam(attacker, victimPlayer) then
			return false
		end
	end
	local invulnerableUntil = model:GetAttribute("InvulnerableUntil")
	if type(invulnerableUntil) == "number" and os.clock() < invulnerableUntil then
		return false -- i-frames (dodge, spawn protection) set by server code only
	end
	amount = math.floor(amount + 0.5) -- round once, here
	track(target, source)
	target:TakeDamage(amount) -- respects ForceField; set Health directly for custom rules
	Damage.damaged:fire(target, amount, source)
	return true
end

return Damage
```
<!-- /code -->

Entry script (starts weapon modules, spawn protection, ragdoll on death, cleanup):
<!-- code: examples/combat/ServerScriptService/WeaponServer.server.luau -->
```luau
-- file: examples/combat/ServerScriptService/WeaponServer.server.luau
--!strict
-- Entry point for the combat example: starts the weapon modules and owns character lifecycle
-- (ragdoll on death, spawn protection) and cleanup. Clients send intent only; see Combat/*.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Combat = ServerScriptService.Combat
local Common = require(Combat.Common)
local Damage = require(Combat.Damage)
local Ragdoll = require(Combat.Ragdoll)
local Melee = require(Combat.Melee)
local Hitscan = require(Combat.Hitscan)
local Projectiles = require(Combat.Projectiles)

Melee.start()
Hitscan.start()
Projectiles.start()

local SPAWN_PROTECTION = 3

local function onCharacter(character: Model)
	Ragdoll.prepare(character)
	character:SetAttribute("InvulnerableUntil", os.clock() + SPAWN_PROTECTION) -- read by Damage (server clock)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Once(function()
			Ragdoll.enable(character)
		end)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	Common.forget(player)
	Projectiles.forget(player)
end)

Damage.killed:connect(function(victim: Humanoid, killer: Player?, weapon: string)
	print(`[Combat] {victim.Parent} killed by {if killer then killer.Name else "world"} ({weapon})`)
end)
```
<!-- /code -->

## Health rules you may want
| Need | How |
|---|---|
| No regeneration / custom regen | put a `Script` named `Health` in `StarterCharacterScripts` (replaces the default regen script); implement regen on the server with a delay after last damage |
| Non-Humanoid targets (crates, doors, bosses without Humanoid) | attribute `Health` on the model, server-only writes; extend `Damage.apply` with a branch for models without a Humanoid |
| Armor / resistances | multiply in `Damage.apply` from server-side attributes/config before rounding |
| Damage numbers / hit markers | attacker: server `HitConfirm` remote (already in the combat example); victim: vignette on the client when `Health` decreases (`HealthChanged`) |
| Kill feed | `Damage.killed` → `FireAllClients("KillFeed", killerName, victimName, weapon)` (reliable) |
| Fall damage | server: on `Humanoid.StateChanged` to `Landed`, read the root's downward velocity, apply `Damage.apply` with `weapon = "Fall"` beyond a threshold |

## How to test (Server & Clients, 2 players + Teams)
- Same team, `FRIENDLY_FIRE=false`: no damage; switch teams → damage.
- Hit someone, then they jump off a cliff within 10 s → kill credited to you; after 10 s → "world".
- Right after spawning (3 s) nobody can hurt you; `ForceField` also blocks `TakeDamage`.
- A client script setting its own `Humanoid.Health = 100` after damage: only changes its local view; the server
  value and other clients are unaffected (verify in the server view).

## Pitfalls
- `Humanoid.Health` changes made by the owning client do not replicate, but the owning client can still set its own
  health locally to hide damage UI — the server value is what counts for death.
- Don't `Destroy` a character to kill it; set health to 0 so `Died` fires and credit works.
- `os.clock()` attributes (`InvulnerableUntil`) are server-clock values; clients must not interpret them.

Sources: cd:reference/engine/classes/Humanoid, cd:reference/engine/classes/ForceField, cd:reference/engine/classes/Team,
cd:characters/index, cd:scripting/security/client-server-boundary.
