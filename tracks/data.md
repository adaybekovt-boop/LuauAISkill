# Track: data, persistence, cross-server

Use for: saving, profiles, purchases, leaderboards, MemoryStore, MessagingService, teleports, matchmaking.
Load: [data persistence](../handbook/roblox/06-data-persistence.md) → [cross-server](../handbook/roblox/07-cross-server.md) →
[limits](../references/limits.md).

Non-negotiables
- Failed load ≠ new player; errored profiles never save.
- `UpdateAsync` with pure, non-yielding transforms; session locking; ordered per-key writes; bounded retries.
- `ProcessReceipt`: grant + record PurchaseId + save, then `PurchaseGranted`; set the callback once.
- BindToClose ~30 s: parallel releases. Studio writes real data → test universe.
- MemoryStore: TTLs always, temporary data only; Messaging: best effort, ≤ 1 KB.
- Undocumented `PlayerDataService`/`Player:GetData()` exist in the dump — don't use until documented.

Recipes: [save-system](../recipes/gameplay/save-system.md), [matchmaking-queue](../recipes/gameplay/matchmaking-queue.md).
Evals: `evals/cases/datastores.jsonl`.
