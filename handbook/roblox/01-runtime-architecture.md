# Roblox runtime architecture: client, server, shared

Read when: placing scripts/assets, deciding who owns logic, starting a project, debugging "script doesn't run".
Related: [lifecycle](02-lifecycle-events.md), [networking](03-networking.md), [security](04-security.md),
[architecture patterns](21-architecture.md), service cheat sheet: [references/service-map](../../references/service-map.md).

## The one rule
The **server is authoritative**. Each client is a remote, untrusted, possibly modified program. The client owns
presentation (camera, UI, local VFX/SFX, input capture, prediction); the server owns truth (health, currency,
inventory, progression, damage, match state, persistence, spawning, permissions). Physics of a client-owned assembly
(its own character by default) is the one area where the client writes state that replicates — treat it as
untrusted input ([security](04-security.md#movement-and-physics-ownership)).

## Replication in one table
| Container | Server sees | Clients see | Scripts that run there |
|---|---|---|---|
| `Workspace` | all | streamed subset (if StreamingEnabled) | Server `Script` (Legacy/Server RunContext); client scripts only inside a player's character |
| `ReplicatedStorage` | all | all (not streamed) | `Script` with `RunContext = Client` (recommended client entrypoint); modules required from either side |
| `ReplicatedFirst` | all | replicated **first**, before the rest | client loading screen scripts |
| `ServerScriptService` | all | nothing | server `Script`s + server-only modules |
| `ServerStorage` | all | nothing | none run automatically (store server-only assets/modules) |
| `StarterPlayer.StarterPlayerScripts` | template | copied to `Player.PlayerScripts` once per join | `LocalScript` |
| `StarterPlayer.StarterCharacterScripts` | template | copied into each new character | `LocalScript` (and server `Script`) |
| `StarterGui` | template | copied to `PlayerGui` (per spawn if `ResetOnSpawn`) | `LocalScript` inside ScreenGuis |
| `StarterPack` | template | copied to `Backpack` on spawn | Tools' scripts |
| `Lighting`, `SoundService`, `Teams`, `Players` | all | all (replicated properties) | — |
| `Player.PlayerGui`, `Player.Backpack` | server can see/write | owning client | — |

Client-side changes to replicated Instances **do not replicate** to the server or other clients (except physics of
owned assemblies, some character/humanoid state, and `Animator` tracks on a client-owned character). Server-side
changes replicate to clients (subject to streaming).

## Script types and RunContext
| Type | Runs on | Where it runs | Notes |
|---|---|---|---|
| `Script` + `RunContext.Legacy` (default) | server | `ServerScriptService`, `Workspace` | classic server script |
| `Script` + `RunContext.Server` | server | regardless of container (docs); keep it in `ServerScriptService` — in `ReplicatedStorage` its source replicates to clients | |
| `Script` + `RunContext.Client` | client | any client-visible container (`ReplicatedStorage`, `ReplicatedFirst`, `Workspace`…); in starter containers it **runs twice** (original + clone) | recommended single client entrypoint in `ReplicatedStorage` |
| `LocalScript` | client | `StarterPlayerScripts`, `StarterCharacterScripts`, `StarterGui`, `StarterPack`, `ReplicatedFirst`, character, `PlayerGui`, `Backpack` | does **not** run in `ReplicatedStorage`/`Workspace` (outside the character) |
| `ModuleScript` | whoever requires it | anywhere reachable | runs once per VM; server and client get separate copies |

`RunContext` is set in Studio (write security PluginSecurity); changing it restarts the script.

Recommended layout (official guidance): one server entry `Script` in `ServerScriptService`, one client entry
`Script` (RunContext Client) in `ReplicatedStorage` or a `LocalScript` in `StarterPlayerScripts`, everything else as
ModuleScripts with `start()` functions. Tag world objects and handle them from modules (`CollectionService`)
instead of dropping scripts into every model.

```text
ReplicatedStorage/
  Shared/            -- types, constants, pure logic, network contract definitions (client-visible!)
  Client/            -- client modules (controllers, UI, camera, VFX)
  ClientMain         -- Script, RunContext = Client: requires Client modules, calls start()
  Remotes/           -- RemoteEvents (or created by server at startup)
ServerScriptService/
  ServerMain         -- Script: requires Server modules, calls start()
  Server/            -- server modules (services: data, combat, economy, rounds)
ServerStorage/
  Assets/            -- server-only templates (weapons, NPCs, maps) cloned into Workspace on demand
ReplicatedFirst/
  Loading            -- minimal loading screen client script
```
Never put secrets, admin lists, server-only validation constants you want hidden, or API keys in
`ReplicatedStorage`/`ReplicatedFirst`/`Workspace`/`StarterGui` — clients can read all of it (and decompile
client-visible scripts). Secrets → `HttpService:GetSecret` (server) or ServerStorage/ServerScriptService.

## Client / server / shared checklist for any feature
1. **State**: what is the authoritative state and where does it live? (server tables, attributes on server-owned
   Instances, DataStore)
2. **Intent**: what does the client ask for? (small, validated request: "interact with target X", not "set my coins")
3. **Validation**: what can the server check cheaply? (type, range, rate, distance, ownership, cooldown, state)
4. **Replication**: how do clients learn the result? (property/attribute replication, remote event, both)
5. **Presentation**: what can the client show immediately (prediction) and how does it reconcile if the server says
   no?
6. **Lifetime**: what happens on respawn, leave, stream-out, server shutdown?

## Where each common thing belongs
| Thing | Side | Mechanism |
|---|---|---|
| Health/damage | server | `Humanoid.Health` or attribute; client shows hit markers |
| Currency, inventory, XP | server | server tables + DataStore; replicate a read-only view (attributes/remote) |
| Input, camera, UI, SFX/VFX | client | local scripts; server only sends events |
| Character movement | client-owned physics (default) | server validates (speed/teleport checks) or uses server authority mode |
| NPC AI | server (logic) + client (cosmetics) | server moves NPCs; clients animate/effects |
| Doors/interactables state | server | attribute `Open`; clients tween visuals on `GetAttributeChangedSignal` |
| Round/match flow | server | state machine; replicate phase via attribute on a folder/ReplicatedStorage value |
| Projectiles | server decides hits; client renders | see [combat](15-combat.md) |
| Leaderboards | server | `leaderstats` folder or custom UI fed by server |
| Settings (graphics, sensitivity) | client | local; optionally persisted through a server remote |

## Execution order at join (client)
`ReplicatedFirst` loads → its client scripts run → rest of the game loads → `game.Loaded` fires /
`game:IsLoaded()` → `PlayerScripts` and client Scripts in `ReplicatedStorage` run (ReplicatedStorage contents are
available) → character spawns → `StarterCharacterScripts` copies run. Workspace contents may still be streaming.
Replication order between different change types (property vs remote) is **not guaranteed**; same-type changes
(two attribute changes) generally arrive in order.

## Server authority model (opt-in engine mode)
Roblox also offers an engine-level server authority mode (`Workspace.AuthorityMode = Server`) with client
prediction, rollback and `RunService:BindToSimulation`. It changes how you write core gameplay. Read
[05-server-authority](05-server-authority.md) before choosing it; this chapter describes the classic model.

Sources: cd:scripting/locations, cd:projects/client-server, cd:scripting/attributes, cd:projects/data-model,
cd:scripting/security/client-server-boundary, cd:cloud-services/secrets, cd:scripting/services.
