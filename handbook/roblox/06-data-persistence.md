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
| **Temporary distributed** | seconds–days (TTL ≤ 45 days) | `MemoryStoreService` (hash map, sorted map, queue) | matchmaking queues, global event counters, server browser, locks, caches |
| **Cross-server signals** | fire-and-forget | `MessagingService` | "refresh your cache", global announcements, party invites |
Never keep durable truth only in MemoryStore or Messaging.
Watch item (undocumented): an engine-managed player data API (`PlayerDataService`, `Player:GetData()`, `PlayerDataRecord`) exists in
the 0.740/0.741 API dumps but is undocumented — don't use it until creator-docs documents it (`tools/api.py` flags it).

## Limits that matter (creator-docs, Sep 2026)
| Item | Limit |
|---|---|
| Value size per key | 4,194,304 characters (JSON-serialized length) |
| Key / data store name / scope | 50 characters each |
| Metadata | 300 characters total |
| Server default rate (per minute) | Standard read and write: `60 + 40 × players` each; list `5 + 2 × players`; ordered write `30 + 5 × players` — configurable with `DataStoreService:SetRateLimitForRequestType()`; check `GetRequestBudgetForRequestType()` |
| Experience-wide rate (per minute) | read `300 + 40 × CCU`, write `300 + 20 × CCU`, list `300 + 2 × CCU` (shared with Open Cloud) |
| Per-key throughput | read 25 MB/min, write 4 MB/min (rounded up per KB per request) |
| Queue | 30 requests per queue; beyond → dropped with errors 301–306 |
| Storage | 500 MB + 1 MB × lifetime users (compressed latest versions) |
| `GetAsync` cache | 4 s local cache; `DataStoreGetOptions.UseCache = false` to bypass for verification |
| Studio | needs "Enable Studio Access to API Services"; separate static lower limits; writes hit real data (use a test universe) |
| `BindToClose` | ~30 s for all callbacks at shutdown |
Supported values: nil, boolean, finite number, UTF-8 string, table of these, `buffer`. No Vector3/CFrame/Instance;
no NaN/inf; mixed or sparse tables serialize badly.

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
- Set the callback **once**, in one server Script. Return `Enum.ProductPurchaseDecision.PurchaseGranted` only
  after the grant **and** the `PurchaseId` are saved durably with the profile; otherwise return `NotProcessedYet`.
- Idempotency: keep processed `PurchaseId`s in the profile (bounded list, e.g. last 100–1000) and check before
  granting. The callback can run on two servers simultaneously (player rejoins) — session locking + id check make
  that safe.
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
