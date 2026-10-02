# Debugging playbook: symptom → likely causes → how to check → fix

Work top-down: reproduce reliably → check Output (both client and server views) → narrow with prints/breakpoints →
verify the hypothesis → fix → re-test in the same conditions (Server & Clients when networking is involved).

## Scripts & lifecycle
| Symptom | Likely causes | Check | Fix |
|---|---|---|---|
| Script does nothing, no errors | wrong container for script type (LocalScript in Workspace/ReplicatedStorage), `Disabled`/`Enabled=false`, RunContext mismatch, infinite `WaitForChild` before your code | Output "Infinite yield possible" warning; print at top of script; check Explorer location + RunContext | move to correct container; add timeouts ([runtime](../handbook/roblox/01-runtime-architecture.md)) |
| Code runs twice | client Script (RunContext Client) in a Starter container (original + clone); two entrypoints requiring same module and both calling `start()`; connecting twice | print with `script:GetFullName()` | single entrypoint; LocalScript in starter containers |
| Works in Play Solo, fails in Server & Clients | client-only assumptions on server (LocalPlayer), replication order, client-created instances | test in Server & Clients; check both Output views | server authority, WaitForChild, remotes |
| Works first life, breaks after respawn | stale character/humanoid references; ResetOnSpawn UI | print identity of humanoid used | rebind on `CharacterAdded` |
| "attempt to index nil with 'X'" | FindFirstChild returned nil (streaming, not yet replicated, renamed), stale ref, wrong side | print the parent's children at that moment | nil checks, WaitForChild w/ timeout, binders |
| "Requested module experienced an error while loading" | the ModuleScript errored at require time | scroll up for the original error | fix module; avoid side effects at require |
| Handler runs "late" / order weird | Deferred signal behaviour | check `Workspace.SignalBehavior` | don't depend on immediate handler execution |

## Networking
| Symptom | Likely causes | Check | Fix |
|---|---|---|---|
| RemoteEvent does nothing | handler on wrong side (OnServerEvent in LocalScript), remote created on client, different remote instance (duplicate names), handler connected after event fired, handler errors silently in pcall | print in both sender and receiver; Explorer during play on both views; "Remote event invocation discarded" in log | create remotes on server; connect before firing; one remote per name |
| Server receives wrong/shifted arguments | client passed `player` explicitly | print args with `typeof` | remove player from FireServer |
| Instance argument arrives as nil | not replicated to receiver (ServerStorage, client-created, streamed out) | check the instance's location/streaming | send ids or data instead |
| Table arrives modified | metatables stripped, mixed keys, non-string keys converted, nil holes | print received table | plain arrays/dictionaries |
| Actions throttled/delayed under load | > ~500 req/s per client across remotes, big payloads | Developer Console Network tab, MicroProfiler `ProcessPackets` | batch, lower frequency, unreliable for cosmetics |
| UnreliableRemoteEvent messages missing | payload > 1000 bytes (dropped) or packet loss by design | Studio Output shows oversize warnings | shrink payload or use RemoteEvent |
| Server hangs | `InvokeClient` waiting on a client | server script stack in debugger | remove InvokeClient from critical paths |

## Security incidents
| Symptom | Likely causes | Check | Fix |
|---|---|---|---|
| Players deal damage through walls | client-reported hits accepted; no LOS check; lag-comp without cap | review remote handler | server raycast LOS against static geometry, range/angle, rate ([combat](../handbook/roblox/15-combat.md)) |
| Infinite money/items | client-trusted amounts, missing ownership checks, duplicate via rejoin (no session lock), receipts granted twice | audit handlers; DataStore history | server authority; session locking; PurchaseId dedupe |
| Speed/fly/teleport hacks | client-owned character physics | server position sampling | movement validator / server authority mode |
| Players interact from across the map | prompt/remote without server distance check | log distances | server distance + state checks |
| Unknown scripts appear / weird behaviour after inserting a model | backdoor (`require(id)`, obfuscated code) in free model | search all scripts for `require(`, `getfenv`, `loadstring`, long strings | remove, audit, prefer own assets |

## Data
| Symptom | Likely causes | Check | Fix |
|---|---|---|---|
| Data sometimes lost | saving defaults after failed load; overwrite by stale server (no lock); save on leave only + crash; BindToClose not waiting; throttled saves dropped | DataStore version history (`ListVersionsAsync`), logs of load/save results | errored profiles never save, session lock, autosave, BindToClose waits |
| Items duplicated | two servers owning a profile; trade not atomic; receipts reprocessed | versions + lock ids | lock + atomic single-key trades or escrow design |
| "DataStore request was added to queue" warnings | exceeding per-server budget | `GetRequestBudgetForRequestType` | fewer requests, batching, autosave interval |
| Works in game, errors in Studio | Studio API access disabled; separate limits | Game Settings → Security | enable for a test universe |
| Stale reads right after write | 4 s GetAsync cache | — | `UseCache = false` for verification reads |

## Animation / character
| Symptom | Likely causes | Check | Fix |
|---|---|---|---|
| Animation doesn't play | asset permission (not owned/shared), R6 vs R15 mismatch, priority too low, track not loaded, played on wrong Animator | Output warnings "Failed to load animation"; check rig type | share/upload under same owner; correct rig; Action priority |
| Only visible to one player | played client-side on a rig the client doesn't own | who calls Play | owner plays (client for own character, server for NPC) |
| Character jitters/rubber-bands | two systems setting CFrame; network ownership flipping; server moving a client-owned root; heavy server lag | MicroProfiler server; ownership debug (Studio: Network Owners visualization) | single writer; SetNetworkOwner; reduce server load |
| NPC stuck / slides | pathfinding not re-planned, MoveTo 8 s timeout, HipHeight wrong, anchored parts | draw waypoints; watch MoveToFinished(false) | stuck detection + replan |
| NPCs lag the server | per-NPC loops, pathfinding every frame, Humanoids for static NPCs, server animation for 100 NPCs | MicroProfiler `stepHumanoid`, `stepAnimation`, scripts | NPC manager, LOD, client animation |

## Performance & memory
| Symptom | Likely causes | Check | Fix |
|---|---|---|---|
| FPS drops looking at an area | draw calls/density, shadowed lights, transparency, particles | MicroProfiler blue/red frames, Render Stats | instancing, fewer shadow lights, LOD/SLIM, cull |
| FPS drops with many lights | shadowed local lights overlapping | `computeLightingPerform`/`ShadowMapSystem` | disable shadows on fills, reduce ranges, room culling |
| Periodic hitches | GC spikes (allocation bursts), big synchronous work, autosave serialization | MicroProfiler `GC`, your labels | reduce allocations, chunk work |
| Memory grows over time | connections not disconnected, per-player tables not cleared, instances parented to nil but referenced, caches without eviction | Developer Console LuaHeap/InstanceCount over time; Luau heap snapshots | cleanup patterns; `PlayerCharacterDestroyBehavior` |
| Mobile crashes | memory (textures, audio, big maps without streaming) | test on device; memory tab | streaming, smaller textures, fewer unique assets |
| Server heartbeat low | server scripts per frame, physics of many unanchored parts, AI | server MicroProfiler (Developer Console) | budgets, anchoring, LOD |

## Streaming
| Symptom | Likely causes | Check | Fix |
|---|---|---|---|
| LocalScript errors on distant objects | object not streamed in | streaming debug overlay (Shift+Ctrl+F3, Shift+1 → Streaming) | binders, WaitForChild with timeout, `RequestStreamAroundAsync` |
| Door/model half loaded | Nonatomic model | `ModelStreamingMode` | Atomic for scripted models |
| Player falls through floor after teleport | area not streamed | — | `RequestStreamAroundAsync` before `PivotTo`; `StreamingIntegrityMode` |

## UI
| Symptom | Likely causes | Check | Fix |
|---|---|---|---|
| UI looks different on phone | offset sizing, no aspect constraints, ignoring safe areas, TextScaled inconsistencies | Device Emulator | scale + constraints + ScreenInsets |
| Buttons don't work on touch/gamepad | `MouseButton1Click` only; not Selectable | test with emulators | `Activated`, Selectable, SelectedObject |
| UI resets after death | `ResetOnSpawn = true` | ScreenGui property | set false |
| Text overlapping in other languages | fixed widths | test locales | AutomaticSize, wrapping, extra width |

## Graphics
| Symptom | Likely causes | Check | Fix |
|---|---|---|---|
| Scene looks flat/"Roblox-y" | high Ambient, SmoothPlastic, no key light, noon sun | graphics/01 diagnosis table | lower ambient, materials, motivated lights |
| Washed out / milky | Atmosphere haze/density, exposure, CC brightness | toggle effects one by one | tune down |
| Light leaks through walls | thin walls, `CastShadow` off, missing ceiling | wireframe/Explorer | thicker geometry |
| Z-fighting flicker | coplanar faces | move camera close | offset 0.01–0.05 studs or merge |
| Lighting script "doesn't apply" | writing Studio-only properties (`LightingStyle`, `Technology`) | Output errors; `tools/api.py` | set in Studio |

Sources: cd:studio/output, cd:studio/debugging, cd:studio/developer-console, cd:studio/testing-modes,
cd:performance-optimization/microprofiler/use-microprofiler, cd:workspace/streaming/index, cd:scripting/events/remote,
cd:cloud-services/data-stores/error-codes-and-limits, cd:animation/using.

## Evidence-first diagnosis when execution is unavailable
State observed facts separately from hypotheses; without logs or a reproducible run, do not claim a root cause
or a verified fix. Ask for the smallest paired scripts, exact instance paths, execution side, reproduction steps
and original client/server Output around the failure. Mark unexecuted checks NOT RUN and name the next check.
For intermittent saves, first test failed-load handling and fast rejoin while the old server still owns the lock.

The engine automatically prepends the sending Player to OnServerEvent arguments. The client sends
`remote:FireServer(data)`; the server handler receives `(player, data)`. Log payload types on both sides,
connection timing and the full remote path before changing an argument list.

For an infinite WaitForChild, inspect spelling and the full parent path, the server/client side where the
instance exists, whether streaming removed it, and whether another script creates it later. Use a timeout;
if it expires, log the expected path, execution side and current children instead of indexing nil or waiting forever.
