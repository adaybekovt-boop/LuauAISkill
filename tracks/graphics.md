# Track: graphics & lighting

Use for: scene mood, lighting setup, "looks cheap/washed out/flat", atmosphere/fog/sky, post-processing, graphics settings.
Load: [lighting](../handbook/graphics/01-lighting.md) → [atmosphere/sky/post](../handbook/graphics/02-atmosphere-sky-post.md) →
[local lights](../handbook/graphics/03-local-lights.md) → then the matching scene recipe in [recipes/graphics](../recipes/INDEX.md#graphics-recipesgraphics).

Non-negotiables
- `LightingStyle`/`PrioritizeLightingQuality` are Studio-only writes; `Technology` is not scriptable. Never "set" them in scripts.
- No custom shaders, ray tracing toggles, GI toggles or lens distortion exist — don't promise them.
- Motivated light, low Ambient for interiors, few shadowed lights, bloom threshold high, exposure last.
- One owner per Lighting property (server-wide events vs client moods); post effects in Camera = per player.
- Tiers scale your content, never gameplay visibility; the engine's quality level is not readable.
- Values are starting points: judge on target devices; state that visuals were not screenshot-verified if not.

Evals: `evals/cases/graphics.jsonl`, `evals/cases/lighting.jsonl`.
