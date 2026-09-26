# Track: characters, camera, input, animation

Use for: movement abilities, first/third person, bodycam, camera shake/recoil, input bindings, animations, footsteps.
Load: [character controllers](../handbook/roblox/13-character-controllers.md) → [camera](../handbook/roblox/14-camera.md) →
[input](../handbook/roblox/19-input.md) → [animation](../handbook/roblox/16-animation.md).

Non-negotiables
- Movement feel on the owning client; server validates (stamina authority, displacement checks, no auto-punish).
- One camera owner; layered offsets built fresh each frame; springs/noise, no naive `sin(time)` bob; Reduced Motion.
- Input Action System for new bindings (stable), ContextActionService fine; always handle Cancel/End; touch + gamepad.
- Animations: `Animator:LoadAnimation` (not `Humanoid:LoadAnimation`), owner plays its own character's animations.
- `PreRender`/`PreSimulation` for new per-frame code (not `RenderStepped`/`Stepped`).

Recipes: [sprint-crouch-stamina](../recipes/gameplay/sprint-crouch-stamina.md), [bodycam-camera](../recipes/gameplay/bodycam-camera.md),
[footsteps](../recipes/gameplay/footsteps.md). Evals: `evals/cases/animation.jsonl`, `evals/cases/ui.jsonl`.
