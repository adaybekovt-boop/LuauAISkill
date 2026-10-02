# Recipes index

End-to-end, copyable systems. Every recipe states its evidence level; nothing here was run in Roblox Studio unless it
says so. Code lives in `examples/<project>/` (Rojo-style service folders) and is embedded into the recipe; shared
helpers are in `examples/lib` (Cleanup, Binder, TokenBucket, Validate, Signal, Spring, Hash).
Evidence: TC = typechecked (luau-lsp strict, old + new solver, Roblox defs 0.741) · CLI = pure logic executed by
unit tests in `examples/tests/` · Studio = not run for any recipe.

## Gameplay (`recipes/gameplay/`)
| Recipe | Solves | Side | Evidence | Example project |
|---|---|---|---|---|
| [interaction-system](gameplay/interaction-system.md) | ProximityPrompt interactions with server validation + handler registry | S | TC | interaction |
| [door-system](gameplay/door-system.md) | doors: server state/collision, client animation, keys, auto-close | S+C | TC | interaction |
| [inventory](gameplay/inventory.md) | server-authoritative inventory, pickups, drops, hotbar | S+C | TC + CLI | interaction |
| [network-rate-limiter](gameplay/network-rate-limiter.md) | remotes with per-player limits, parsers, abuse counters | S+C | TC + CLI | net |
| [save-system](gameplay/save-system.md) | session-locked profiles, migrations, autosave, BindToClose, purchases | S | TC + CLI | data |
| [health-damage](gameplay/health-damage.md) | one damage entry point, teams, i-frames, kill credit | S | TC | combat |
| [melee-combat](gameplay/melee-combat.md) | server attack timeline, box + cone + LOS | S+C | TC + CLI | combat |
| [hitscan-gun](gameplay/hitscan-gun.md) | client prediction, server raycast, ammo, tracers, lag-comp plan | S+C | TC + CLI | combat |
| [projectile-weapon](gameplay/projectile-weapon.md) | server-simulated projectiles rendered by clients, splash | S+C | TC + CLI | combat |
| [ragdoll](gameplay/ragdoll.md) | reversible ragdoll for death and knock-down | S+C | TC | combat |
| [sprint-crouch-stamina](gameplay/sprint-crouch-stamina.md) | Input Action System movement, stamina authority, speed check | S+C | TC + CLI | movement |
| [footsteps](gameplay/footsteps.md) | stride-based material footsteps (Audio API) | C | TC | movement |
| [bodycam-camera](gameplay/bodycam-camera.md) | bodycam layer over the default camera, comfort-aware | C | TC | movement |
| [npc-patrol](gameplay/npc-patrol.md) | one budgeted NPC manager, LOD, non-blocking pathfinding | S | TC + CLI | npc |
| [npc-chase](gameplay/npc-chase.md) | vision/hearing, fair detection, search, hiding | S | TC + CLI | npc |
| [round-manager](gameplay/round-manager.md) | round state machine, maps, deadline replication | S+C | TC + CLI | rounds |
| [matchmaking-queue](gameplay/matchmaking-queue.md) | MemoryStore queue → reserved match servers | S | TC + CLI | rounds |
| [procedural-backrooms](gameplay/procedural-backrooms.md) | infinite deterministic connected chunks, budgeted building | S | TC + CLI | procgen |
| [settings-menu](gameplay/settings-menu.md) | schema-driven settings, server-sanitized, gamepad/touch UI | S+C | TC + CLI | settings |
| [object-pooling](gameplay/object-pooling.md) | when/how to pool client effects | C | TC | pooling |

## Graphics (`recipes/graphics/`)
| Recipe | Look / system | Evidence |
|---|---|---|
| [cinematic-horror-interior](graphics/cinematic-horror-interior.md) | dark house, practical lights, soundscape | TC (preset) |
| [backrooms-fluorescent-office](graphics/backrooms-fluorescent-office.md) | Level 0 fluorescent office | TC (preset) |
| [realistic-dark-corridor](graphics/realistic-dark-corridor.md) | pools of light | TC (preset) |
| [night-exterior](graphics/night-exterior.md) | moonlight | TC (preset) |
| [sunset](graphics/sunset.md) | golden hour | TC (preset) |
| [fog](graphics/fog.md) | overcast / horror fog, fog as a tool | TC (preset) |
| [industrial-warehouse](graphics/industrial-warehouse.md) | sun shafts, dust, metal | TC (preset) |
| [poolrooms](graphics/poolrooms.md) | tiled liminal pools | TC (preset) |
| [emergency-red-lighting](graphics/emergency-red-lighting.md) | power failure event | TC |
| [flickering-fluorescent](graphics/flickering-fluorescent.md) | client flicker, photosensitivity | TC |
| [realistic-flashlight](graphics/realistic-flashlight.md) | two-cone beam, replicated to others | TC |
| [camera-aesthetics](graphics/camera-aesthetics.md) | bodycam / CCTV / VHS looks, what's impossible | TC |
| [lighting-controller-presets](graphics/lighting-controller-presets.md) | zone-based preset blending | TC |
| [graphics-presets](graphics/graphics-presets.md) | Low/Medium/High/Ultra + adaptive Auto | TC |
| [heavy-scene-performance-pass](graphics/heavy-scene-performance-pass.md) | measure → fix → measure procedure | procedure |
"TC (preset)" = the preset's property names/types are validated; the visual result is art direction that must be judged
in Studio on target devices.

## Using a recipe in a project
1. Read the recipe's Architecture section and decide if it fits (each lists when NOT to use it).
2. Copy the files at the paths shown (`examples/<project>/<Service>/...` maps 1:1 to Studio services; Rojo users can
   point a project file at the folder) plus `examples/lib/ReplicatedStorage/Lib` → `ReplicatedStorage.Lib`.
3. Run the recipe's "How to test" table in Studio (Server & Clients for anything networked) and report results honestly.
