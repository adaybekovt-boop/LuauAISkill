# Track: NPC / AI

Use for: enemies, monsters, patrols, pathfinding, many NPCs.
Load: [NPC/AI](../handbook/roblox/20-npc-ai.md) → [performance § humanoids](../handbook/roblox/08-performance.md) →
[physics § ownership](../handbook/roblox/09-physics.md).

Non-negotiables
- One manager loop with budgets + distance LOD; never a `while true` script per NPC.
- Pathfinding throttled and capped; no `MoveToFinished:Wait()` inside the manager; stuck detection; `Blocked` replans.
- Perception cheap → expensive (distance, cone, then raycast); hearing via gameplay noise events.
- Server owns NPC physics (`SetNetworkOwner(nil)`); fair detection (grace, last known position, search).

Recipes: [npc-patrol](../recipes/gameplay/npc-patrol.md), [npc-chase](../recipes/gameplay/npc-chase.md). Evals: `evals/cases/npc.jsonl`.

Additional verified examples: [parallel-npc-planning](../recipes/gameplay/parallel-npc-planning.md).
