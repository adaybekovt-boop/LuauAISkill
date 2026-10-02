# Tracks: task → what to load

Pick the track(s) for the task, then load only the listed files in order. Every track assumes the workflow and hard
rules in [SKILL.md](../SKILL.md). Cross-cutting: [AI failure modes](../references/ai-failure-modes.md) before
submitting any code, [legacy catalog](../references/legacy-modernization/CATALOG.md) when touching old code.

| Task mentions… | Track |
|---|---|
| types, syntax, tables, strings, coroutines, `task`, Luau performance, "is this valid Luau" | [luau](luau.md) |
| new project, folder structure, modules, lifecycle, refactor, code review, code quality, Rojo/Wally/Selene, Knit/Fusion/React/ECS/Blink/Zap projects | [architecture](architecture.md) |
| RemoteEvent/Function, replication, exploits, validation, anti-cheat, rate limits, server authority | [networking-security](networking-security.md) |
| saving, DataStore, profiles, purchases, developer products, passes, subscriptions, loot boxes, leaderboards, MemoryStore, MessagingService, teleport, matchmaking | [data](data.md) |
| lag, FPS, memory, MicroProfiler, many NPCs/parts, mobile performance | [performance](performance.md) |
| lighting, atmosphere, fog, sky, post-processing, "looks cheap/washed out", horror/liminal/sunset mood, graphics settings | [graphics](graphics.md) |
| materials, PBR, SurfaceAppearance, environment art, VFX, particles, terrain look | [environment-art](environment-art.md) |
| interaction, doors, inventory, pickups, rounds, lobby, settings menu | [gameplay](gameplay.md) |
| weapons, damage, hitboxes, melee, guns, projectiles, ragdoll | [combat](combat.md) |
| movement, sprint/crouch, camera, first person, bodycam, input bindings, animation, footsteps | [character-camera](character-camera.md) |
| enemies, pathfinding, monster AI, crowds | [npc](npc.md) |
| UI, HUD, menus, mobile/gamepad UI, accessibility, chat, chat commands | [ui](ui.md) |
| sound, music, ambience | [audio](audio.md) |
| big maps, StreamingEnabled, terrain, procedural generation | [world](world.md) |
| "doesn't work", errors, weird behaviour, desync | [debugging](debugging.md) |
| old code, deprecated APIs, "modernize", migration | [legacy](legacy.md) |
| tests, CI, linting, typechecking, verification, playtest, Studio MCP, Open Cloud | [testing](testing.md) |
