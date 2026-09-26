# Track: materials, environment art, VFX

Use for: materials/PBR, SurfaceAppearance, MaterialVariants, modular kits, liminal/horror spaces, particles, terrain look.
Load: [materials & PBR](../handbook/graphics/04-materials-pbr.md) → [environment art](../handbook/graphics/05-environment-art.md) →
[VFX & particles](../handbook/graphics/06-vfx-particles.md) → [terrain](../handbook/roblox/11-terrain.md) when relevant.

Non-negotiables
- Scale from the character (doors 4–5 × 8–9, corridors 6–12, ceilings 10–14); thick walls (no light leaks).
- SurfaceAppearance maps are not script-writable at runtime; MeshId is not writable; CollisionFidelity is Studio-only.
- Real materials/variants with roughness variation; desaturated base colours.
- Break repetition deliberately (decals, props, damage, variation by seed).
- Particles: few, purposeful, LightInfluence set, tagged for quality tiers.

Recipes: graphics scene recipes ([index](../recipes/INDEX.md#graphics-recipesgraphics)).
Evals: `evals/cases/graphics.jsonl`.
