# Networking: remotes, replication, payloads, rate limits

## TL;DR
- Choose remotes by delivery and response requirements.
- Treat every client payload as untrusted.
- Validate cheap shape checks before expensive world checks.
- Rate-limit before granting authoritative effects.
- Send only the state each recipient is allowed to see.

Read when: any client↔server communication. Always also read [security](04-security.md).
Related: [runtime](01-runtime-architecture.md), [server authority mode](05-server-authority.md),
recipes: [network rate limiter](../../recipes/gameplay/network-rate-limiter.md), [interaction](../../recipes/gameplay/interaction-system.md).

## Primitive semantics (verified: RemoteEvent/UnreliableRemoteEvent/RemoteFunction docs, Sep 2026)
| Primitive | Direction | Delivery | Yields caller | Limits / notes |
|---|---|---|---|---|
| Property/attribute replication | server → clients | reliable, eventual; per-type ordered; **not ordered relative to remotes** | no | automatic; subject to streaming |
| `RemoteEvent` | C→S `FireServer`, S→C `FireClient`/`FireAllClients` | reliable, ordered (per remote) | no | client→server ≈<!-- fact-value: remote-client-send-rate -->500<!-- /fact-value --> req/s per client **shared by all RemoteEvents**; handler on server gets `player` first | <!-- fact-refs: remote-client-send-rate -->
| `UnreliableRemoteEvent` | same API | may drop, may reorder | no | payload > **<!-- fact-value: unreliable-remote-payload -->1000<!-- /fact-value --> bytes is dropped**; shares its own ≈<!-- fact-value: remote-client-send-rate -->500<!-- /fact-value --> req/s budget; for continuous cosmetic data | <!-- fact-refs: unreliable-remote-payload, remote-client-send-rate -->
| `RemoteFunction` | C→S `InvokeServer` (OK), S→C `InvokeClient` (**avoid**) | reliable request/response | **yes** | only one `OnServerInvoke` callback (last assigned wins); client can delay/never answer |
| `BindableEvent/Function` | same side only | local | Function yields | tables copied like remotes |

## Decision tree: which primitive?
```text
Is the data state that clients should always converge to (door open, NPC state, score)?
 ├─ yes → set it on a server-owned Instance (property/attribute/ValueObject). Done. (+ optional RemoteEvent for one-shot FX)
 └─ no, it's a message →
    Who sends?
    ├─ server → client(s)
    │   ├─ must arrive (kill feed, UI result, round start)  → RemoteEvent (FireClient / FireAllClients)
    │   └─ continuous, latest-wins (NPC aim, cosmetic positions) → UnreliableRemoteEvent (≤1000 bytes)
    └─ client → server (always untrusted INTENT, never outcomes)
        ├─ discrete action (use item, interact, attack start) → RemoteEvent
        ├─ client needs an answer to continue UI (buy button result, fetch shop page) →
        │     RemoteFunction:InvokeServer is acceptable IF the server handler never yields long and
        │     the client UI handles failure/timeouts; or RemoteEvent request + RemoteEvent reply with requestId
        └─ continuous input (look direction for cosmetics) → UnreliableRemoteEvent at a capped rate (10–20 Hz)
Server needs data from a client? → don't ask (InvokeClient). Have the client push it with rate limits,
or compute it on the server.
```
Never use `RemoteFunction:InvokeClient` on a critical path: if the client errors, disconnects, or never returns,
the server thread errors or **yields forever**.

## Payload design
- Send **intent + identifiers**, never results: `UseItem(slotIndex)`, `Interact(target: Instance)`,
  `Fire(origin, direction, clientShotId)`. Never `AddCoins(100)`, `DealDamage(target, 50)`, `SetWalkSpeed(40)`.
- Keep args flat and typed: numbers, strings, booleans, Vector3/CFrame, Instances, small arrays. Avoid nested
  tables (validation cost, depth attacks).
- Instances in payloads arrive as references **only if the receiver can see them** (not streamed out, not in
  ServerStorage, not client-created) → otherwise `nil`. Always nil-check.
- Tables are copied: metatables stripped, functions become nil, non-string keys become strings, mixed tables break,
  `nil` holes truncate arrays.
- Prefer small enums (`"Light"|"Heavy"` validated against a set, or numbers) over free-form strings.
- Precision: Vector3 components are 32-bit floats on the wire in many paths; don't expect bit-exact doubles.
- `buffer` payloads are compact and compressed automatically; use for high-frequency packed data (but validate
  `buffer.len` before reading).

## Server handler template (validate cheap → expensive, then act)
```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local remote = Instance.new("RemoteEvent")
remote.Name = "UseItem"
remote.Parent = ReplicatedStorage

local MAX_SLOT = 10
local lastUse: { [Player]: number } = {}

remote.OnServerEvent:Connect(function(player: Player, slot: unknown)
	-- 1. rate limit first (cheapest, stops floods before any work)
	local now = os.clock()
	if now - (lastUse[player] or 0) < 0.2 then return end
	lastUse[player] = now
	-- 2. type + range (NaN fails every comparison, so check integers explicitly)
	if typeof(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > MAX_SLOT then return end
	-- 3. state (alive, has item, not stunned) — read from SERVER state only
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	-- 4. act, then tell clients the outcome
	print(player.Name, "uses slot", slot)
end)

Players.PlayerRemoving:Connect(function(player: Player) lastUse[player] = nil end)
```
Silently dropping invalid requests is usually right (don't give exploiters an oracle); log aggregated counters for
monitoring.

## Intent-specific validation
Apply the security chapter's validation catalog to the complete operation, not only its first argument:
- A purchase handler looks up `itemId` in a server-owned catalog and obtains the price there. Rate-limit the
  request, check the server balance, then debit and grant together without yielding in the in-memory commit.
  Reject unknown item IDs and duplicate request IDs before repeating an economic effect.
- A blink handler first validates that the requested position is a Vector3 with finite components (reject NaN
  and infinity), enforces a server cooldown, and limits displacement from the server-observed character
  position. Validate the destination's collision clearance and the required line of sight before moving.
- A chest handler checks `typeof(target) == "Instance"`, its expected class with `IsA`, and containment with
  `IsDescendantOf` against the server-owned chest container. Check server-side player distance and current chest
  state; an already-open, disabled, or unavailable chest must not grant again.

These are validation design patterns, not proof that the client's replicated position itself is trustworthy.
Movement validation and server-authority decisions remain separate responsibilities.

## Rate limiting
- Per player, per action. Token bucket (burst + sustained rate) is the standard: see
  `examples/lib/ReplicatedStorage/Lib/TokenBucket.luau`. Clear state on `PlayerRemoving`.
- Never create per-player keys from client-supplied strings (memory attack): key by a fixed set of action names.
- Budget the total: ≈500 req/s per client is the engine cap across all RemoteEvents — design for ≤ 20–30 msgs/s per
  client in normal play.
- Server → client: don't `FireAllClients` every Heartbeat for 50 objects. Batch into one message per tick
  (array of updates) at 10–20 Hz, or replicate via properties.

## Batching / snapshot pattern (server → clients, cosmetic)
```luau
--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local snapshot = Instance.new("UnreliableRemoteEvent")
snapshot.Name = "NpcSnapshot"
snapshot.Parent = ReplicatedStorage

local SEND_HZ = 15
local accumulator = 0
local npcs: { Model } = {}

RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	if accumulator < 1 / SEND_HZ then return end
	accumulator = 0
	-- 12 bytes per NPC (3×f32) + header; ~70 NPCs fit in 1000 bytes. Chunk if more.
	local count = math.min(#npcs, 70)
	local b = buffer.create(2 + count * 12)
	buffer.writeu16(b, 0, count)
	for i = 1, count do
		local p = npcs[i]:GetPivot().Position
		local o = 2 + (i - 1) * 12
		buffer.writef32(b, o, p.X)
		buffer.writef32(b, o + 4, p.Y)
		buffer.writef32(b, o + 8, p.Z)
	end
	snapshot:FireAllClients(b)
end)
```
Usually unnecessary: NPC `Model`s already replicate physics positions. Use snapshots only for data that doesn't
replicate on its own or when you move visuals client-side.

## Ordering and consistency
- A property change and a remote fired right after may arrive in **either order**. If a remote references an
  Instance that was just created, the client may receive `nil` or the Instance before its children exist →
  send ids/data, or have the client react to the Instance appearing (`ChildAdded`, tags).
- Two changes of the same kind (e.g. two attribute changes) generally arrive in order.
- For request/response over events: include a `requestId`, keep a bounded pending map with timeouts, and ignore
  late/duplicate replies.

## Remote organisation
For a multiplexed command remote, dispatch through an explicit handler table keyed by a fixed validated action
set, not `_G` or a client-chosen global function name.

- Create remotes on the **server** at startup (or in Studio) under one folder (`ReplicatedStorage.Remotes`);
  clients `WaitForChild` them with a timeout. Never let clients create remotes (client-created Instances don't
  replicate).
- One remote per logical message type is easier to validate and profile than one "Network" remote with a string
  command argument. Either is OK if every message type has its own validator.
- Define the contract in a shared module: names, argument types, limits. Validation lives on the server.

## Replicating player data to clients
- Public stats → attributes on `Player` or a `leaderstats` folder (visible to all clients!).
- Private data (inventory, currency details) → `FireClient` to that player on change (send diffs or full small
  snapshots), not attributes on shared objects.

## Anti-patterns
| BAD | Why | GOOD |
|---|---|---|
| `remote.OnServerEvent:Connect(function(p, dmg) hum:TakeDamage(dmg) end)` | client picks damage | server computes damage from server weapon stats |
| `InvokeClient` to ask client for its mouse position | server hangs if client never answers | client pushes aim with rate limit, or server-side raycast |
| `FireServer` every `RenderStepped` | hits <!-- fact-value: remote-client-send-rate -->500<!-- /fact-value -->/s cap with other traffic; wasted bandwidth | send on change; choose and profile a cosmetic update frequency, unreliable | <!-- fact-refs: remote-client-send-rate -->
| One remote per player created at runtime | clutter, race conditions | fixed set of remotes, player is the implicit first arg |
| Trusting `player` passed in payload | spoofable | only the engine-provided first argument is the sender |
| Payload `{[inst]=true}` | keys become strings | array of instances |

Sources: cd:scripting/events/remote, cd:reference/engine/classes/RemoteEvent, cd:reference/engine/classes/UnreliableRemoteEvent,
cd:reference/engine/classes/RemoteFunction, cd:scripting/attributes, cd:scripting/security/client-server-boundary,
cd:performance-optimization/microprofiler/network, cd:projects/client-server.
