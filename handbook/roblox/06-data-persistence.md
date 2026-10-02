# Data persistence: DataStores, profiles, purchases

## TL;DR
- Choose persistent, ordered, or temporary storage by purpose.
- Model player profiles with explicit session ownership.
- Make updates and purchase grants idempotent.
- Respect budgets and bound retry/backoff behavior.
- Test contention, failed saves, reconnects, and shutdown paths.

Read when: saving anything across sessions (progress, inventory, currency, settings), developer products.
Related: [cross-server](07-cross-server.md) (MemoryStore/Messaging/Teleport), recipe
[save system](../../recipes/gameplay/save-system.md), [security](04-security.md).

## Three kinds of data — pick the right store
| Kind | Lifetime | Store | Examples |
|---|---|---|---|
| **Persistent** | forever (versioned) | `DataStoreService` (standard; ordered for leaderboards) | profiles, inventory, currency, unlocks, purchase ids |
| **Temporary distributed** | seconds–days (TTL ≤ <!-- fact-value: memorystore-max-expiration -->3888000<!-- /fact-value --> seconds) | `MemoryStoreService` (hash map, sorted map, queue) | matchmaking queues, global event counters, server browser, locks, caches | <!-- fact-refs: memorystore-max-expiration -->
| **Cross-server signals** | fire-and-forget | `MessagingService` | "refresh your cache", global announcements, party invites |
Never keep durable truth only in MemoryStore or Messaging.
Watch item (undocumented): an engine-managed player data API (`PlayerDataService`, `Player:GetData()`, `PlayerDataRecord`) exists in
the 0.740/0.741 API dumps but is undocumented — don't use it until creator-docs documents it (`tools/api.py` flags it).

## Limits that matter (creator-docs, Sep 2026)
<!-- facts-table: datastore-value-size, datastore-key-length, datastore-name-length, datastore-scope-length, datastore-metadata-total, datastore-standard-read-server-rate, datastore-standard-write-server-rate, datastore-standard-list-server-rate, datastore-ordered-write-server-rate, datastore-read-experience-rate, datastore-write-experience-rate, datastore-list-experience-rate, datastore-key-read-throughput, datastore-key-write-throughput, datastore-queue-size, datastore-queue-overflow-error-codes, datastore-storage, datastore-cache-duration, bind-to-close-deadline -->
| Fact ID / statement | Value | Unit / scope | Status |
|---|---|---|---|
| `datastore-value-size`: Maximum serialized data-store value size. | 4194304 | characters/key | documented |
| `datastore-key-length`: Maximum data-store key length. | 50 | characters | documented |
| `datastore-name-length`: Maximum data-store name length. | 50 | characters | documented |
| `datastore-scope-length`: Maximum data-store scope length. | 50 | characters | documented |
| `datastore-metadata-total`: Maximum total user-defined metadata size. | 300 | characters | documented |
| `datastore-standard-read-server-rate`: Standard data-store read default server rate; configurable through SetRateLimitForRequestType. | 60 + 40 * players | requests/minute/server | default |
| `datastore-standard-write-server-rate`: Standard data-store write default server rate; configurable through SetRateLimitForRequestType. | 60 + 40 * players | requests/minute/server | default |
| `datastore-standard-list-server-rate`: Standard data-store list default server rate; configurable through SetRateLimitForRequestType. | 5 + 2 * players | requests/minute/server | default |
| `datastore-ordered-write-server-rate`: Ordered data-store write default server rate; configurable through SetRateLimitForRequestType. | 30 + 5 * players | requests/minute/server | default |
| `datastore-read-experience-rate`: Read experience rate for each data-store type; game-server and Open Cloud usage share its budget. | 300 + 40 * concurrent_users | requests/minute/experience/data-store-type | documented |
| `datastore-write-experience-rate`: Write experience rate for each data-store type; game-server and Open Cloud usage share its budget. | 300 + 20 * concurrent_users | requests/minute/experience/data-store-type | documented |
| `datastore-list-experience-rate`: List experience rate for each data-store type; game-server and Open Cloud usage share its budget. | 300 + 2 * concurrent_users | requests/minute/experience/data-store-type | documented |
| `datastore-key-read-throughput`: Per-key read throughput; each request is rounded up to the next kilobyte. | 25 | MB/minute/key | documented |
| `datastore-key-write-throughput`: Per-key write throughput; each request is rounded up to the next kilobyte. | 4 | MB/minute/key | documented |
| `datastore-queue-size`: Requests beyond the per-queue limit are dropped. | 30 | requests/queue | documented |
| `datastore-queue-overflow-error-codes`: Error codes for entirely dropped requests when a throttling queue is full. | [301, 306] | inclusive error-code range | documented |
| `datastore-storage`: Storage allowance measured using compressed latest key versions. | 500 + 1 * lifetime_users | MB/experience | documented |
| `datastore-cache-duration`: Default GetAsync local-cache lifetime. | 4 | seconds | default |
| `bind-to-close-deadline`: BindToClose callbacks have this time to complete. | 30 | seconds | documented |
<!-- /facts-table -->

Server budgets are configurable with `DataStoreService:SetRateLimitForRequestType()`; inspect `GetRequestBudgetForRequestType()` before spending them. Experience budgets are shared with Open Cloud. Use `DataStoreGetOptions.UseCache = false` for an uncached verification read.

Studio requires "Enable Studio Access to API Services", has separate static lower limits, and writes to real data; use a test universe.

## Session model (per player)
```text
PlayerAdded → load (UpdateAsync that also takes the session lock) ──fail→ mark profile "errored": play with
             defaults, NEVER save, block purchases/trades, tell the player, retry in background
          → ready: keep profile in server memory; gameplay mutates memory only
          → autosave every 60–300 s (jittered) → refreshes lock
          → purchases: grant in memory + record PurchaseId + save immediately
PlayerRemoving → final save + release lock (only if loaded successfully)
BindToClose → save all loaded profiles in parallel, wait for completion (≤ ~30 s)
```

## Core rules
1. **One key per player** (`User_<UserId>`) holding one table (+ `schemaVersion`). Split only for size/throughput.
2. **`UpdateAsync` for anything that depends on the current value** or may be written by multiple servers.
   The transform: pure, **no yields**, may run multiple times, return `nil` to abort. Return
   `keyInfo:GetUserIds()` / `keyInfo:GetMetadata()` if you don't intend to clear them.
3. **Failed load ≠ new player.** Distinguish "key absent" (`nil` value, success) from "request failed" (pcall
   false). Only the former gets default data that may be saved.
4. **Session locking** prevents two servers owning the same profile (rejoin/teleport races → item duplication).
   Store `{ lockId, lockTime }` in the value or metadata, acquire it inside the load `UpdateAsync`, refresh on
   every autosave, clear on release. Treat a lock older than the expiry (e.g. 5–15 min, longer than autosave) as
   stale. Before every save verify the lock is still yours.
5. **Retries**: exponential backoff + jitter, bounded attempts, **ordered per key** (a stale retried write must
   never land after a newer one). A failed write may still have succeeded on the backend.
6. **Autosave** staggered (random initial offset) — never every few seconds, never every change.
7. **No `SetAsync` for profiles** except creating a brand-new key or deliberate overwrite tooling.
8. Store ids and numbers; derive everything else from config on load (prices, stats can change).
9. **Migrations**: `schemaVersion` + ordered migration functions `v1→v2→v3` run on load; never delete old fields in
   the same release that migrates them; keep backups via versioning (`ListVersionsAsync`, `GetVersionAsync`,
   `GetVersionAtTimeAsync`).
10. **Right to be forgotten**: static key patterns (`User_{UserId}`) enable automated RTBF processing.

## Load with session lock (core of a profile system)
```luau
--!strict
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local STORE = DataStoreService:GetDataStore("PlayerData_v1")
local SERVER_LOCK = HttpService:GenerateGUID(false)
local LOCK_EXPIRY = 30 * 60 -- seconds; must exceed autosave interval with margin

export type Profile = { schemaVersion: number, coins: number, items: { [string]: number }, purchases: { string } }
type Stored = { data: Profile, lockId: string?, lockTime: number? }

local function defaultProfile(): Profile
	return { schemaVersion = 1, coins = 0, items = {}, purchases = {} }
end

-- Returns (status, profile). status: "ok" | "locked" | "error". Never yields inside the transform.
local function loadAndLock(userId: number): (string, Profile?)
	local lockedByOther = false
	local ok, result = pcall(function()
		return STORE:UpdateAsync("User_" .. userId, function(old: Stored?, keyInfo: DataStoreKeyInfo?)
			local now = os.time()
			local stored: Stored = old or { data = defaultProfile() }
			if stored.lockId and stored.lockId ~= SERVER_LOCK and now - (stored.lockTime or 0) < LOCK_EXPIRY then
				lockedByOther = true
				return nil -- abort write; another live server owns this profile
			end
			lockedByOther = false -- the transform may re-run; reset flags each run
			stored.lockId = SERVER_LOCK
			stored.lockTime = now
			local userIds = if keyInfo then keyInfo:GetUserIds() else nil
			return stored, userIds or { userId }
		end)
	end)
	if not ok then return "error", nil end
	if lockedByOther then return "locked", nil end
	local stored = result :: Stored
	return "ok", stored.data
end

print(loadAndLock)
```
Callers: on `"locked"` wait/retry a few times (the previous server may still be saving), then kick with a message
or play in read-only mode; on `"error"` use defaults marked non-saveable. The full system (autosave, release,
BindToClose, migrations, purchases, per-key queue) is in the recipe [save-system](../../recipes/gameplay/save-system.md).

## Developer products (`MarketplaceService.ProcessReceipt`)
If the player/profile is unavailable or loading failed, return `NotProcessedYet` without granting. Remove any
developer-product grant from `PromptProductPurchaseFinished`; a prompt closing is not a durable receipt.

- Set the callback **once**, in one server Script. Return `Enum.ProductPurchaseDecision.PurchaseGranted` only
  after the grant **and** the `PurchaseId` are saved durably with the profile; otherwise return `NotProcessedYet`.
- Idempotency: persist processed `PurchaseId`s with the grant and check them before granting. Do not prune receipt
  IDs merely because the ledger reaches a count: a replay of an evicted receipt can grant twice. Keep durable
  replay protection and plan storage capacity/migration before the profile reaches its storage budget. A
  capacity failure must leave the receipt unacknowledged for a safe retry, not silently discard deduplication
  history. The callback can run on two servers simultaneously (player rejoins); session ownership plus the
  atomic durable ID check and grant protect that race.
- The player must be in the server for the callback to fire; it is retried when they rejoin or buy again (no timer
  retries). If no callback is set, receipts are auto-acknowledged (and you lose the chance to grant).
- Game passes: check ownership on the server with `MarketplaceService:UserOwnsGamePassAsync(userId, passId)` on join
  and on `PromptGamePassPurchaseFinished` (then re-verify on the server — the event is a hint, not proof).
- `GetProductInfo` is deprecated → `GetProductInfoAsync`; `PlayerOwnsAsset` → `PlayerOwnsAssetAsync`.
- Newer receipt API `MarketplaceService:BindReceiptHandler` (returns `Enum.ReceiptDecision`), Robux transfers,
  subscriptions, paid random items and `PolicyService`: [monetization](25-monetization.md).

## OrderedDataStore (leaderboards)
Integer values only, `GetSortedAsync(ascending, pageSize ≤ 100)`. Write on meaningful changes (session end),
not every kill. Cache pages for 60 s+ server-side.

## Testing data code
Shutdown finalization must be idempotent: skip errored profiles that were never safely loaded, and skip a
profile whose final save and release already completed. Serialize concurrent finalization attempts so
PlayerRemoving and BindToClose cannot produce a stale duplicate save.

- Pure logic (migrations, merge, validation) → unit tests with the Luau CLI.
- Studio: separate test universe or scoped store names (`PlayerData_v1_TEST`); simulate failures by injecting a
  fake store object with the same methods (dependency injection).
- Scenarios: first join, rejoin within seconds on another server (lock), load failure (errored profile never
  saves), shutdown with 20 players, purchase during load, purchase while save fails, schema v1 data loaded by v2.

Sources: cd:cloud-services/data-stores/index, cd:cloud-services/data-stores/error-codes-and-limits,
cd:cloud-services/data-stores/best-practices, cd:cloud-services/data-stores/player-data-purchasing,
cd:cloud-services/data-stores/versioning-listing-and-caching, cd:cloud-services/data-stores/right-to-be-forgotten,
cd:reference/engine/classes/GlobalDataStore, cd:reference/engine/classes/MarketplaceService,
cd:production/monetization/developer-products, cd:cloud-services/data-stores-vs-memory-stores.
