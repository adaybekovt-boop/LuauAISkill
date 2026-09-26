# Roblox / Luau anti-pattern database

Each row: BAD → why it hurts → GOOD. "Still relevant" was re-checked against the Sep 2026 API/docs; historical
myths that no longer apply are listed at the end. Deprecated-API migrations live in
[legacy-modernization/CATALOG.md](legacy-modernization/CATALOG.md).

## Scheduling & lifecycle
| BAD | Why | GOOD |
|---|---|---|
| `wait()`/`spawn()`/`delay()` | deprecated, throttled | `task.wait/defer/spawn/delay` |
| `while true do ... task.wait() end` per object | N threads × every frame; never stops | one manager loop with registry, or events; loops check an `alive` flag and exit |
| `repeat task.wait() until x` (busy wait) | wastes frames, races | signals (`BindableEvent`, `:Once`, `GetPropertyChangedSignal`) |
| `task.wait(2)` "to let things load" | arbitrary; fails on slow devices | wait on the actual condition (`WaitForChild` + timeout, `game.Loaded`, data ready signal) |
| `WaitForChild` without timeout on things that may never exist | infinite yield, silent hang | `WaitForChild(name, 10)` + nil handling; binders for streamed objects |
| Connecting in a loop without disconnecting (per respawn/open) | connection & memory leak, handlers run N times | cleanup bag per lifetime; `:Once` |
| Hundreds of `RenderStepped/PreRender` connections | per-frame callback overhead | one per system, iterate registries |
| Relying on handler order / immediate firing | breaks under Deferred signals | code tolerant to deferred execution |
| Storing character/humanoid references across respawns | stale objects → errors | re-fetch on `CharacterAdded` |
| Not iterating existing players after connecting `PlayerAdded` | misses early joiners | connect + loop `GetPlayers()` |

## Networking & security
| BAD | Why | GOOD |
|---|---|---|
| Client sends damage/currency/reward amounts | trivially exploited | client sends intent; server computes |
| Trusting remote arguments without type/range/NaN checks | crashes, NaN poisoning, exploits | validate `typeof`, finite, range, membership |
| No server rate limiting | spam → DoS/economy abuse | token bucket per player per action |
| Client-side cooldowns only | bypassed | server timestamps |
| `Touched`-only melee/pickup awarding | client-owned parts fake touches; unreliable | server distance/overlap checks |
| `RemoteFunction:InvokeClient` on server critical path | server thread hangs forever if client never answers | client pushes data; server never waits on clients |
| `RemoteFunction` for fire-and-forget actions | blocks caller, needless round trip | `RemoteEvent` |
| One "DoAnything(action, ...)" remote with string dispatch and no per-action validation | huge attack surface | one remote per message type or strict per-action validators |
| Untyped network contracts (magic strings, positional args drift) | client/server mismatch bugs | shared contract module with names + types + limits |
| Firing remotes every frame | ~500 req/s cap, bandwidth, CPU | on change; ≤ 10–20 Hz; unreliable for cosmetics |
| Sending whole inventories on every change | bandwidth | deltas/ids |
| Secrets/admin lists in ReplicatedStorage | decompiled by clients | ServerStorage/ServerScriptService/Secrets |
| Admin checks by player Name | names change, spoofable in payloads | `UserId` allowlist / group roles on server |
| `require(assetId)` third-party code | backdoors | own code, audited packages |
| Client-created remotes/instances expected on server | never replicate | server creates remotes |
| Server-side validation using client camera position | client-controlled | server character positions |

## Data
| BAD | Why | GOOD |
|---|---|---|
| `SetAsync` everywhere / per change | lost updates, budget exhaustion | in-memory profile + periodic `UpdateAsync` |
| Saving defaults after a failed load | wipes real data | errored profile never saves |
| No session locking | duplication via rejoin/teleport races | lock in the key (UpdateAsync) + expiry |
| Yielding inside `UpdateAsync` transform | errors / reruns | pure transform |
| Unordered retries per key | older write overwrites newer | per-key queue |
| Profile keys by player Name | names change | `User_<UserId>` |
| Storing Instances/Vector3/CFrame directly | not serializable (nil/error) | numbers/arrays/strings; buffer if needed |
| `ProcessReceipt` granting without durable record / returning Granted on failure | lost or duplicated purchases | record PurchaseId + save first |
| MemoryStore/Messaging as source of truth | TTL / best-effort delivery | DataStore is the truth |
| Testing on production data stores | corrupts real players | separate test universe / scopes |

## Performance
| BAD | Why | GOOD |
|---|---|---|
| `workspace:GetDescendants()` / `GetTagged` every frame | huge allocations | registries via events/tags |
| `FindFirstChild` chains every frame | string scans | cache references |
| Creating a new Tween every frame | allocation + fighting tweens | one tween per transition; springs for continuous motion |
| Tweening replicated parts on the server | replicates every frame, jitter | tween on clients |
| Each NPC its own Heartbeat script | scales linearly with N | NPC manager with LOD tick rates |
| Pathfinding recompute every frame | worker saturation | re-path on events / ≥ 0.5–1 s with target-moved threshold |
| Unanchored decorative parts | physics + ownership churn | anchor |
| Precise collision on every mesh | physics memory/CPU | Box/Hull; invisible simple colliders |
| Shadows on every light | lighting cost | shadows only on key lights |
| Unique mesh/texture uploads of identical assets | breaks instancing, memory | upload once, duplicate in Studio |
| 4K textures on small props | GPU memory | 256–512² for props |
| Stacked transparent layers / huge particles | overdraw (mobile killer) | fewer, smaller, opaque where possible |
| `print` spam in loops | Output/console cost | throttled logging, debug flags |
| Optimizing without profiling | wrong target | MicroProfiler first |
| `--!native` on every script | startup/memory cost, code-size limit | only hot numeric modules, measured |

## Architecture & code quality
| BAD | Why | GOOD |
|---|---|---|
| Giant god module (2,000+ lines, everything) | unreviewable | split by responsibility |
| Enterprise framework for a small game | overhead, AI/humans lose the plot | simplest structure that fits ([architecture](../handbook/roblox/21-architecture.md)) |
| Copy-pasted scripts inside every model | updates drift | tags + one binder module |
| Magic strings for remotes/tags/attributes everywhere | typos fail silently | central constants/contract module |
| `_G`/`shared` globals | untyped, order-dependent | modules |
| `:: any` to silence the typechecker | hides bugs | refine types |
| `pcall` around everything, ignoring errors | silent failures | pcall only fallible I/O; handle results |
| Mutating shared default tables | cross-instance contamination | clone defaults |
| Random free-model architecture (mixed styles, hidden scripts) | security + maintenance | audited, owned modules |

## Graphics / UX
| BAD | Why | GOOD |
|---|---|---|
| High `Ambient` for "visibility" | flat, cheap look | low ambient + motivated lights |
| Bloom threshold low / intensity high | everything glows | threshold ≥ ~1.5 |
| Neon parts as paint | glowing everywhere | real materials; Neon only for emissive fixtures |
| Saturated primary colours | toy look | desaturated palette, material albedo ranges |
| Default `sin(time)` head bob, strong shake | motion sickness | stride-phase bob, springs, settings toggle |
| UI in offset pixels only | breaks on phones/4K | scale + constraints + UIScale |
| Ignoring safe areas | UI under notches/topbar | `ScreenInsets` |
| `MouseButton1Click` only | no touch/gamepad | `Activated` |
| `TextScaled` everywhere without constraints | inconsistent text sizes | fixed sizes per style or `UITextSizeConstraint` |
| Showing unfiltered player text | ToS violation | TextService filtering |

## Myths (no longer true / never true)
| Myth | Reality (Sep 2026) |
|---|---|
| "Turn off FilteringEnabled to make it work" | FE can't be disabled; design client/server properly |
| "Only 31 Highlights" | client renders up to 255 |
| "Light range max 60" | clamped at 120 studs |
| "DataStore: 6 s cooldown per key; 60 + 10×players/min" | per-key throughput limits; server default 60 + 40×players/min read & write |
| "Scripts can set Lighting.Technology/LightingStyle at runtime" | no — Studio/plugin only |
| "SurfaceAppearance textures can be swapped by script" | no — maps are PluginSecurity; tint/emissive only |
| "RaycastFilterType.Blacklist" | removed; `Exclude`/`Include` or `ExcludeInstances` |
| "Roblox supports custom shaders" | no user shaders; use materials, post effects, EditableImage/EditableMesh (CPU-side) |
| "task.spawn makes code run on another CPU core" | no — same thread; use Actors for parallelism |
| "`--!strict` validates remote data" | types are compile-time only |

Sources: cd:performance-optimization/improve, cd:scripting/security/security-tactics, cd:scripting/security/client-server-boundary,
cd:cloud-services/data-stores/best-practices, cd:cloud-services/data-stores/error-codes-and-limits, cd:effects/highlighting,
cd:scripting/events/deferred, cd:scripting/multithreading, cd:art/modeling/surface-appearance.
