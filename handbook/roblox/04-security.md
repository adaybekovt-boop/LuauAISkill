# Security and anti-exploit (practical, not paranoid)

Read when: any remote handler, economy, combat, movement, inventory, purchases, teleports, admin tools.
Related: [networking](03-networking.md), [server authority mode](05-server-authority.md), [data](06-data-persistence.md),
[combat](15-combat.md), [anti-patterns](../../references/anti-patterns.md).

## What an exploiter can do (official threat model)
- Read everything replicated: all client-visible Instances, attributes, and **decompile any LocalScript or
  ModuleScript in replicated containers** (even ones that never run on the client).
- Fire/invoke any remote at any rate with any arguments (except the engine-supplied `player`).
- Change anything in their local DataModel without firing events; alter local code.
- Control physics of assemblies they own: their character (teleport, fly, speed, noclip, NaN/inf CFrames) and any
  unanchored part the server lets them own.
- Trigger `Touched`, `ProximityPrompt`, `ClickDetector`, `Tool.Activated` at any range/frequency.
- Play arbitrary animations on their character (replicates), change their local Humanoid properties
  (`WalkSpeed` edits are local but the resulting movement replicates).
What they **cannot** do: change server-side values directly, run code on the server, see ServerStorage /
ServerScriptService, forge the `player` argument, or change other players' server state except through your
remotes and physics you let them own.

## Principles
1. **Server decides.** Client sends intent; server validates, executes, replicates result.
2. **Validate at the boundary**, in order: rate → type/shape → value range/finite → permission/ownership → state →
   spatial (distance/LOS) → commit. Cheap checks first so floods cost nothing.
3. **Prevent harm first, punish rarely.** Clamp, reject, rubber-band. Consequence ladder: silent log → quiet
   mitigation → temporary restriction → kick/ban (`Players:BanAsync`). Delay visible consequences. Prefer reversible.
4. **Design removes attack surface.** A remote that doesn't exist can't be abused. Don't expose "set X" remotes.
5. **Budget validation cost.** Sanity checks are O(1) arithmetic; raycasts and history rewinds only for
   high-value actions (hits, pickups), not every frame for every player.

## Validation catalog
| Domain | Check on server | Tolerance / notes |
|---|---|---|
| **Types** | `typeof(x) == "number"/"Vector3"/"Instance"`, `IsA` | reject everything else |
| **Numbers** | `x == x` (NaN), `math.isfinite`, integer `x % 1 == 0`, range | NaN passes `<`/`>` checks silently — test explicitly |
| **Strings** | length cap before any processing, allowed set for enums, `utf8.len` not nil | filter user-visible text with TextService ([ui](18-ui-ux.md#text)) |
| **Instances** | not nil, `IsDescendantOf(expected root)`, has tag/attribute you set, class | client can pass any Instance it can see; never `Destroy`/`require` a client-supplied Instance |
| **Tables** | shape: exact keys, max length, max depth 1–2 | reject unknown keys |
| **Interaction** | distance from server-side character root to target ≤ range + latency slack (2–4 studs), target enabled, cooldown | use target's pivot/closest point for big objects |
| **Line of sight** | raycast from character head/root to target, exclude character | only for walls-matter actions |
| **Cooldowns** | server timestamps per player per action | client cooldown is UX only |
| **Damage** | server computes from server weapon stats; attacker alive, weapon equipped, in range, rate ≤ weapon fire rate | client never sends damage numbers |
| **Hits (ranged)** | origin near server character position; hit point near target; no static geometry between; fire rate; ammo | allow latency slack; see [combat](15-combat.md) |
| **Inventory** | item exists in *server* inventory, count ≥ requested, slot bounds | never accept item definitions from client |
| **Economy** | price from server config; balance ≥ price; atomic debit+grant in same code path without yields | log transactions |
| **Purchases (Robux)** | only `MarketplaceService.ProcessReceipt` (dev products) / `UserOwnsGamePassAsync` (passes) on server | never trust a client "I bought" remote |
| **Replay/duplication** | per-action sequence or id; reject ids already processed; idempotent grants keyed by `PurchaseId` | bounded set with expiry |
| **Impossible state** | dead players acting, actions during stun/loading, two items in one hand | state machine on server |
| **Teleport (places)** | destination server re-validates access (group/role/progression/badge); default-deny | clients can teleport to any subplace in the universe |
| **Admin commands** | `player.UserId` in server-side allowlist, or `player:IsInGroupAsync(groupId)` / `GroupService:GetRolesInGroupAsync(userId, groupId)` | never check names; never client-side admin |

## Movement and physics ownership
- Characters are client-owned: the server can't prevent a client from moving its character anywhere; it can only
  detect and correct. Official guidance: no universal solution; engine server authority mode (released 2026-07) is the real
  fix ([05](05-server-authority.md)).
- Practical detection: sample root position on the server at 2–10 Hz; compare horizontal (XZ) displacement vs max
  legal speed × dt with a **leaky bucket** so lag bursts don't trigger; exempt legit teleports (set a server flag
  when *you* teleport them) and vehicles/knockback. On violation: move them back to last valid position
  (`PivotTo`), escalate only on repeated violations.
- Vertical: track airborne time vs. jump arc; flying = sustained airborne without falling.
- Noclip: occasional raycast between last valid and current position against static collision geometry.
- Unanchored game objects near players get auto-assigned ownership to a nearby client → that client can move them.
  For gameplay-critical physics (balls, carts, doors with hinges), `part:SetNetworkOwner(nil)` (server) and accept
  latency, or keep client ownership and validate outcomes. Don't auto-own projectiles that deal damage.
- `BasePart.CanSetNetworkOwnership()` tells you whether you may set ownership (anchored/welded assemblies can't).

## Touched and client-triggered events
- `Touched` fires on the machine that simulates the part; client-owned parts can generate Touched events at will.
  Don't award items/damage on `Touched` alone: re-check distance and state on the server.
- `ProximityPrompt.Triggered` (server) → still check distance from the server-side character and prompt enabled
  state; exploiters can trigger prompts at any range.

## Rate limiting (token bucket)
```luau
--!strict
-- Per player, per action. capacity = burst, rate = sustained tokens/second.
type Bucket = { tokens: number, last: number }
local buckets: { [Player]: { [string]: Bucket } } = {}
local LIMITS: { [string]: { capacity: number, rate: number } } = {
	Interact = { capacity = 5, rate = 2 },
	Fire = { capacity = 12, rate = 10 },
}

local function allow(player: Player, action: string, now: number): boolean
	local limit = LIMITS[action]
	if not limit then return false end              -- unknown action names never allocate memory
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local b = perPlayer[action]
	if not b then
		b = { tokens = limit.capacity, last = now }
		perPlayer[action] = b
	end
	b.tokens = math.min(limit.capacity, b.tokens + (now - b.last) * limit.rate)
	b.last = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

game:GetService("Players").PlayerRemoving:Connect(function(p: Player) buckets[p] = nil end)
print(allow)
```

## Secrets and code confidentiality
- Anything replicated is public, including ModuleScripts in ReplicatedStorage that only the server requires.
  Server-only logic → ServerScriptService/ServerStorage.
- API keys: `HttpService:GetSecret("name")` (Secrets store, server only) — never string literals.
- Unreleased content: keep in private test universes; don't ship hidden in production places.
- Third-party models: audit for `require(assetId)`, `getfenv`, `loadstring`, obfuscated strings, hidden scripts
  in meshes/folders; prefer packages you control.

## Humanoid / tool abuse
- `Humanoid.WalkSpeed`/`JumpPower` set on the server replicates to the owner, but the owner can locally override;
  the server sees only resulting movement → validate movement, not properties.
- Client can equip/unequip tools arbitrarily, fire `Tool.Activated`; server tracks equipped weapon and cooldown.
- Client can delete parts of its own character locally (e.g., remove head for "headless" hit-reg abuse): server
  hit validation should use server-side hitboxes and not depend on client-owned part presence alone.
- Client-created Instances never replicate; a client cannot create a remote or part the server sees. Server must
  never read client state from Instances only the client modified.

## Balance: performance vs paranoia
| Check | Cost | Apply to |
|---|---|---|
| type/range/rate | ~0 | every remote call |
| distance | ~0 | every interaction/attack |
| single raycast | low | hits, interactions through walls matter |
| position history rewind (lag compensation) | medium | hitscan PvP only |
| per-frame movement validation of all players | medium–high | competitive games; sample 2–10 Hz, not 60 |
| full server-side simulation | high | server authority mode / critical physics objects only |

## Logging and monitoring
Count rejections by reason per player (`rejected.Fire.range += 1`); log summaries, not every packet (log spam is
itself a DoS vector). Use AnalyticsService/custom telemetry for trends.

Sources: cd:scripting/security/security-tactics, cd:scripting/security/client-server-boundary,
cd:scripting/security/network-ownership, cd:scripting/security/server-side-detection, cd:scripting/security/access-control,
cd:scripting/security/defensive-design, cd:scripting/security/third-party-vulnerabilities, cd:physics/network-ownership,
cd:cloud-services/secrets, cd:reference/engine/classes/Players.
