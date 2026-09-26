# Track: gameplay systems

Use for: interactions, doors, inventory, pickups, rounds, lobbies, settings, save integration.
Load: [architecture](../handbook/roblox/21-architecture.md) → [networking](../handbook/roblox/03-networking.md) →
[security](../handbook/roblox/04-security.md) → the recipe.

Recipes: [interaction-system](../recipes/gameplay/interaction-system.md), [door-system](../recipes/gameplay/door-system.md),
[inventory](../recipes/gameplay/inventory.md), [round-manager](../recipes/gameplay/round-manager.md),
[matchmaking-queue](../recipes/gameplay/matchmaking-queue.md), [settings-menu](../recipes/gameplay/settings-menu.md),
[save-system](../recipes/gameplay/save-system.md).

Non-negotiables
- Server-authoritative state; clients render replicated state; attributes as designer contracts (validated on read).
- Tag-based binders for world objects (streaming-safe cleanup).
- Deadlines replicated as server time, not ticking countdowns.
Evals: `evals/cases/architecture.jsonl`, `evals/cases/security.jsonl`.
