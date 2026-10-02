# Track: world — streaming, terrain, procedural generation

Use for: large maps, StreamingEnabled issues, terrain, procedural levels.
Load: [streaming](../handbook/roblox/10-streaming.md) → [terrain](../handbook/roblox/11-terrain.md) →
[procedural generation](../handbook/roblox/12-procedural-generation.md).

Non-negotiables
- Client code never assumes an instance exists: binders, `WaitForChild` with timeouts, atomic models for scripted objects.
- `StreamingEnabled` and its modes are Studio settings (not script-writable).
- Procgen: data first, deterministic seeds (`Random.new(seed)`/hash), connectivity proven on data, budgets per frame.

Recipes: [procedural-backrooms](../recipes/gameplay/procedural-backrooms.md). Evals: `evals/cases/streaming.jsonl`.

Additional verified examples: [constraint-vehicle](../recipes/gameplay/constraint-vehicle.md).
