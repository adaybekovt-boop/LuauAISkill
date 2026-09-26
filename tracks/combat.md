# Track: combat

Use for: damage, weapons, hit detection, lag compensation, ragdolls, knockback.
Load: [combat](../handbook/roblox/15-combat.md) → [security](../handbook/roblox/04-security.md) →
[physics § queries](../handbook/roblox/09-physics.md) → [animation](../handbook/roblox/16-animation.md) for feel.

Non-negotiables
- Server computes damage from server config; one damage entry point; one hit per target per attack.
- Validate shot origin vs server head (+ not through walls), direction unit/finite, rate = fire rate.
- No `Touched` bullets; kinematic projectiles with casts between frames.
- Player characters are client-owned: knockback via server-created constraints or owner-applied impulses.
- Lag compensation only with capped rewind; document the trade-off.

Recipes: [health-damage](../recipes/gameplay/health-damage.md), [melee-combat](../recipes/gameplay/melee-combat.md),
[hitscan-gun](../recipes/gameplay/hitscan-gun.md), [projectile-weapon](../recipes/gameplay/projectile-weapon.md),
[ragdoll](../recipes/gameplay/ragdoll.md). Evals: `evals/cases/combat.jsonl`.
