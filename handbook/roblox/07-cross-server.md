# Cross-server systems: MemoryStore, MessagingService, TeleportService, matchmaking

## TL;DR
- Use temporary shared storage only for temporary state.
- Treat messaging as notifications rather than durable truth.
- Make cross-server operations idempotent.
- Handle teleport and matchmaking failures explicitly.
- Account for server shutdown and stale shared entries.

Read when: lobbies, queues, parties, global events, server browsers, multi-place games.
Related: [data persistence](06-data-persistence.md), recipes [matchmaking](../../recipes/gameplay/matchmaking-queue.md),
[round manager](../../recipes/gameplay/round-manager.md).

## MemoryStoreService (temporary, fast, shared by all servers)
| Structure | API | Use |
|---|---|---|
| Hash map | `GetHashMap(name)` → `SetAsync/GetAsync/UpdateAsync/RemoveAsync/ListItemsAsync` | keyed state spread over partitions (best default): server browser entries, party state, locks |
| Sorted map | `GetSortedMap(name)` → `SetAsync(key, value, ttl, sortKey?)`, `GetRangeAsync`, `UpdateAsync` | ordered data: skill-rated queues, live leaderboards |
| Queue | `GetQueue(name, invisibilityTimeout)` → `AddAsync(value, ttl, priority?)`, `ReadAsync(count, allOrNothing, waitTimeout)`, `RemoveAsync(id)` | at-least-once work queues, matchmaking queue |
Limits (Sep 2026): memory quota `64 KB + 1.2 KB × users` (game-wide; drops only after 8 days); request units
`1000 + 120 × CCU` per minute (range reads cost per item; queue reads cost extra while waiting; hash-map
`UpdateAsync` ≥ 2 units); a single sorted map/queue ≤ 1,000,000 items / 100 MB and lives on **one partition**
(throttling starts ~30k units/min per partition; hash-map key ~5k writes / 15k reads per minute); max TTL 45 days.
Rules:
- Always pass the **shortest TTL** that works; delete explicitly when done. When quota is full, all growing
  writes fail game-wide.
- `UpdateAsync` transforms (like DataStore) must not yield and may re-run.
- Queue items read but not removed reappear after the invisibility timeout → consumers must be idempotent.
- Shard hot structures (`Queue_1..N`) when one partition is hot.
- Studio uses a separate MemoryStore namespace from production.

## MessagingService (pub/sub, best effort)
- `SubscribeAsync(topic, fn)` → connection; `PublishAsync(topic, data)`. Topic 1–80 chars; message ≤ 1 KB.
- Limits: publish `600 + 240 × players` per server per minute; receive per topic `40 + 80 × servers`/min;
  subscriptions per server `20 + 8 × players`; 240 subscribe requests/min.
- Delivery is **not guaranteed** and not ordered; messages can be dropped under load. Use it to say "something
  changed, re-read the source of truth" — never as the transaction itself.
- Wrap both calls in `pcall`, subscribe once per server (not per player), validate payloads (another server of
  an *older version* may send an older schema — include `v`).

## TeleportService (moving players between places/servers)
- **Server only**: `TeleportService:TeleportAsync(placeId, players, teleportOptions?)`. Client
  `TeleportService:Teleport()` is deprecated; `TeleportPartyAsync`, `TeleportToPrivateServer`,
  `TeleportToPlaceInstance`, `TeleportToSpawnByName` are deprecated in favour of `TeleportAsync` +
  `TeleportOptions` (`ServerInstanceId`, `ReservedServerAccessCode`, `ShouldReserveServer`,
  `SetTeleportData`). `ReserveServer` → `ReserveServerAsync`.
- Doesn't work in Studio playtests — test in a published game.
- Handle failure: `TeleportService.TeleportInitFailed` (server) → retry with backoff (bounded), restore UI.
- Teleport data (`TeleportOptions:SetTeleportData`) is **client-visible and unencrypted**; read with
  `player:GetJoinData().TeleportData` on arrival. Never put currency/permissions in it; re-load from DataStore.
- Save the profile (release session lock) **before** teleport or accept that the destination waits on the lock.
- Access control (Creator Dashboard): "Secure within universe only" blocks client-initiated joins to subplaces;
  destination servers must still verify eligibility (group/progression) and default-deny.
- Custom loading screen: client `TeleportService:SetTeleportGui(screenGui)` (its scripts don't run) and
  `ReplicatedFirst` on arrival.

## Matchmaking
- **Default matchmaking** (join-time server selection) is configurable: `MatchmakingService:SetServerAttribute()`
  + custom signals/scoring in Creator Dashboard (`InitializeServerAttributesForStudio` for tests).
- **Lobby → match** flow (common pattern): lobby server adds players to a MemoryStore queue/sorted map → a single
  elected server (or each server with locking) pops N compatible players → `TeleportAsync` with
  `ShouldReserveServer = true` → match server reads its expected roster from MemoryStore (keyed by
  `game.PrivateServerId`) and kicks strays.
- Parties: `Player.PartyId` + `SocialService:GetPlayersByPartyId()` to keep groups together.

## Server identity and lifetime
`game.JobId` (unique server id), `game.PrivateServerId` / `game.PrivateServerOwnerId` (reserved/private servers),
`game.PlaceId`, `game.PlaceVersion`. On shutdown, `game:BindToClose(fn)`: save, deregister from server browser,
~30 s total.

Sources: cd:cloud-services/memory-stores/index, cd:cloud-services/memory-stores/best-practices,
cd:cloud-services/memory-stores/per-partition-limits, cd:cloud-services/memory-stores/queue,
cd:cloud-services/memory-stores/sorted-map, cd:cloud-services/memory-stores/hash-map,
cd:cloud-services/cross-server-messaging, cd:reference/engine/classes/MessagingService, cd:projects/teleport,
cd:scripting/security/access-control, cd:matchmaking/index, cd:reference/engine/classes/TeleportService.
