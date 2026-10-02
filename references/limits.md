# Engine and service limits (verified numbers, Sep–Oct 2026)

Numbers change — each row cites its source; re-check with `python tools/fetch_sources.py --latest` + the cited doc.
"≈" = documented as approximate.

| Area | Limit | Source |
|---|---|---|
| RemoteEvent + UnreliableRemoteEvent, client→server | ≈ 500 requests/s per client, shared by all remotes of the same type | cd:reference/engine/classes/RemoteEvent |
| UnreliableRemoteEvent payload | > 1000 bytes → dropped | cd:reference/engine/classes/UnreliableRemoteEvent |
| RemoteFunction callbacks | one `OnServerInvoke` per RemoteFunction (last assignment wins) | cd:scripting/events/remote |
| Deferred event re-entrancy depth | 10 | cd:scripting/events/deferred |
| DataStore value | 4,194,304 characters per key (JSON) | cd:cloud-services/data-stores/error-codes-and-limits |
| DataStore name / key / scope | 50 characters each | same |
| DataStore metadata | 300 characters total | same |
| DataStore server default rate (per min) | Standard read 60 + 40×players; write 60 + 40×players; list 5 + 2×players; remove 60 + 40×players; ordered write/remove 30 + 5×players (configurable: `SetRateLimitForRequestType`) | same |
| DataStore experience rate (per min) | read 300 + 40×CCU; write 300 + 20×CCU; list 300 + 2×CCU; remove 300 + 40×CCU (shared with Open Cloud) | same |
| DataStore per-key throughput | read 25 MB/min, write 4 MB/min (rounded up to KB per request) | same |
| DataStore queue | 30 requests per queue, then dropped (errors 301–306) | same |
| DataStore storage | 500 MB + 1 MB × lifetime users (compressed latest versions) | same |
| DataStore `GetAsync` cache | 4 s | cd:cloud-services/data-stores/versioning-listing-and-caching |
| `BindToClose` | ~30 s for all callbacks | cd:cloud-services/data-stores/player-data-purchasing |
| OrderedDataStore page size | 1–100 | cd:cloud-services/data-stores/error-codes-and-limits |
| MemoryStore memory quota | 64 KB + 1.2 KB × users (game-wide; decreases after 8 days) | cd:cloud-services/memory-stores/index |
| MemoryStore requests | 1000 + 120 × CCU request units/min | same |
| MemoryStore structure | sorted map/queue ≤ 1,000,000 items, ≤ 100 MB; one partition | same |
| MemoryStore partition throttling | ≈ 30,000 units/min per partition; hash-map key ≈ 5,000 write / 15,000 read units/min | same |
| MemoryStore TTL | default/max 45 days | cd:cloud-services/memory-stores/best-practices |
| MessagingService message size | 1 KB | cd:reference/engine/classes/MessagingService |
| MessagingService rates | send 600 + 240×players/min per server; receive per topic 40 + 80×servers/min; game-wide receive 400 + 200×servers/min; subscriptions 20 + 8×players per server; 240 subscribe requests/min | same |
| MessagingService topic | 1–80 characters | same |
| Attributes (server authority replication) | first 64 attributes per instance; name ≤ 50 chars; string value ≤ 50 chars | cd:projects/server-authority/index |
| Raycast length | 15,000 studs | cd:workspace/raycasting |
| Collision groups | 32 | cd:reference/engine/classes/PhysicsService |
| Local light range | clamped to 120 studs | cd:reference/engine/classes/Lighting |
| Highlights rendered | 255 simultaneous per client | cd:effects/highlighting |
| Camera FieldOfView | 1–120 (vertical), default 70 | cd:reference/engine/classes/Camera |
| Lighting ExposureCompensation | −5…5 | cd:reference/engine/classes/Lighting |
| Textures | up to 4096×4096 (PBR maps); guideline 256² per ~2×2×2 studs of object | cd:art/modeling/texture-specifications |
| Particle flipbook texture | must be 1024×1024 | api:ParticleEmitter (FlipbookIncompatible message) |
| Terrain voxel | 4×4×4 studs | cd:parts/terrain |
| `Humanoid:MoveTo` | times out after ~8 s unless re-issued | cd:reference/engine/classes/Humanoid |
| Native codegen | per-block 64K instructions; 32K blocks per function; 1M instructions per module; global size limit | cd:luau/native-code-gen |
| Script Sync | 10,000 scripts per synced root; 128 roots | cd:scripting/sync |
| Text-to-speech | 300 characters per request | cd:audio/objects |
| Studio multi-client test | up to 8 clients | cd:studio/testing-modes |
| `StudioTestService:ExecuteMultiplayerTestAsync` | 1–8 clients; one session per Studio; plugin security | cd:reference/engine/classes/StudioTestService |
| Studio MCP `script_search` / `script_grep` | ≤ 10 results / ≤ 50 matches | cd:studio/mcp |
| Open Cloud Luau Execution task | script ≤ 4 MB; runtime ≤ 5 min; return values ≤ 4 MB JSON; logs ≤ 450 KB kept; task info 24 h; ≤ 10 incomplete tasks per place (else HTTP 429) | cd:cloud/reference/openapi |
| `GlobalDataStore:BatchGetAsync` | ordered stores only; 1–100 keys (default max); N keys = N reads | cd:reference/engine/classes/GlobalDataStore |
| `OrderedDataStore:GetSortedAsync` page size | 1–100 | cd:cloud-services/data-stores/error-codes-and-limits |
| `TextChannel:SendAsync` metadata | ≤ 200 characters (longer → message not delivered) | cd:reference/engine/classes/TextChannel |
| Frustum streaming stream-out | `Opportunistic`: out-of-view instances outside radius/foci linger ~1.5 s | cd:workspace/streaming/frustum |
| Physics units | 1 stud = 0.28 m; 1 RMU = 21.952 kg; default gravity 196.2 studs/s² | cd:physics/units |
| Number precision | integers exact to 2^53 | luau:getting-started/syntax |

Sources: see the Source column (resolved by `tools/check_sources.py`).
