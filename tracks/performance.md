# Track: performance

Use for: FPS drops, server lag, memory growth, mobile budgets, "optimize this".
Load: [performance](../handbook/roblox/08-performance.md) → [Luau performance](../handbook/luau/06-performance-memory.md) →
[quality tiers](../handbook/graphics/07-quality-tiers.md) → [debugging playbook § performance](../references/debugging-playbook.md#performance--memory).

Non-negotiables
- Measure → change one thing → measure again (same shots/route/device). No invented numbers.
- Identify the bound first (render / lighting / script / physics / network / memory) with the MicroProfiler.
- One loop per system with budgets and LOD, not one loop per object; event-driven over polling.
- Don't micro-optimize Luau before the capture says Luau is the problem; `--!native` only for measured hot spots.

Recipes: [heavy-scene-performance-pass](../recipes/graphics/heavy-scene-performance-pass.md), [npc-patrol](../recipes/gameplay/npc-patrol.md),
[object-pooling](../recipes/gameplay/object-pooling.md), [graphics-presets](../recipes/graphics/graphics-presets.md).
Evals: `evals/cases/performance.jsonl`.
