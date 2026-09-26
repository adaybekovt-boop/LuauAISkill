# Device scalability: Low / Medium / High / Ultra tiers

Read when: shipping to phones + PCs + consoles, graphics settings menu, adaptive quality, heavy scenes.
Related: [performance](../roblox/08-performance.md), recipes [graphics presets & settings](../../recipes/graphics/graphics-presets.md),
[settings menu](../../recipes/gameplay/settings-menu.md).

## What you can and can't control
- The **engine** already scales rendering with the user's graphics quality (1–10 or Automatic): draw distance,
  shadows (off below level 4), texture quality, effects. Game scripts **cannot** read the current engine quality
  (`UserGameSettings.GraphicsQualityLevel` is RobloxScriptSecurity) and must not fight it. The user's saved choice
  (`UserSettings():GetService("UserGameSettings").SavedQualityLevel`, often `Automatic`) is readable — use only as a
  hint.
- **You** control your content cost: particle rates, number of active lights/shadows, post effects, decoration
  density, animated props, NPC animation LOD, AI tick rates, UI effects, render distance of your own LOD systems.
- `Lighting.LightingStyle`/`PrioritizeLightingQuality` are Studio-time choices, not runtime tiers.
- Accessibility signals: `GuiService.ReducedMotionEnabled`, `GuiService.PreferredTransparency`,
  `GuiService.PreferredTextSize` (read-only) — respect them.

## Tier table (starting point)
| Knob | Low | Medium | High | Ultra |
|---|---|---|---|---|
| Particle `Rate` multiplier | 0.25 | 0.5 | 1 | 1.25 |
| Decorative emitters (dust, ambient) | off | near only | on | on |
| Shadowed local lights (your content) | 0–1 (flashlight only) | 2 | 4 | 6+ |
| Non-shadow fill lights | minimal | half | all | all |
| Bloom | off | on (low) | on | on |
| DepthOfField / SunRays | off | off | on (subtle) | on |
| ColorCorrection | on (cheap) | on | on | on |
| Clouds | off | on | on | on |
| Decoration density (grass cards, clutter props) | 25 % | 50 % | 100 % | 100 % |
| Your LOD swap distance | ×0.5 | ×0.75 | ×1 | ×1.5 |
| NPC animation distance (client) | 40 | 80 | 150 | 250 studs |
| Cosmetic physics (debris) | off | few | on | on |
| UI blur/CanvasGroup effects | off | minimal | on | on |
Gameplay-relevant visuals (enemy visibility, interactables, readable darkness) must be **identical** across tiers —
tiers never create competitive advantages (e.g. fog off on low letting players see farther).

## Choosing a tier
1. Default by device class: `UserInputService.TouchEnabled and not KeyboardEnabled` → start Medium/Low; desktop →
   High; consoles → High. Treat as heuristics.
2. Adaptive: measure frame time on the client (EMA of `RunService.PreRender` dt, or p95 over 10 s); if p95 > budget
   (e.g. 33 ms target on mobile, 16.7 ms desktop) for N seconds, step down one tier; step up only after a long stable
   period (hysteresis, e.g. 60 s) and never while the player is in a heavy moment. Never oscillate.
3. Player override in a settings menu (persist via server DataStore or local-only); the override wins over adaptive.

## Server-side scalability (CPU)
- AI tick rates by distance/tier of player density; pathfinding job caps.
- Simulation LOD for NPCs far from all players (freeze/anchor).
- Replication: fewer, batched updates when player count is high.
- Heartbeat budget monitoring: log when server frame time exceeds budget and degrade optional systems.

## Implementation notes
- Tag effect instances (`FX_Decor`, `FX_Critical`, `Light_Fill`, `Light_Shadow`) at build time; the client tier
  controller toggles by tag (binder pattern handles streaming).
- Apply tier changes gradually (spread over frames) to avoid a hitch when switching.
- Keep a single `QualityTier` value (client-side) that other client systems read or subscribe to.

Sources: cd:performance-optimization/improve, cd:performance-optimization/design, cd:performance-optimization/test-on-hardware,
cd:reference/engine/classes/UserGameSettings, cd:reference/engine/classes/GuiService, cd:production/publishing/accessibility,
cd:projects/cross-platform.
