# Local lights, practicals, fake bounce, emissives

## TL;DR
- Match each light type to the intended source.
- Build a hierarchy of key, fill, and accent lighting.
- Fake bounce selectively rather than filling every surface.
- Budget shadow-casting lights and measure overlap.
- Clean up animated lights and flashlight bindings.

Read when: interiors, night scenes, horror, flashlights, fluorescent/neon fixtures, emergency lighting.
Prereq: [lighting](01-lighting.md). Recipes: [flickering fluorescent](../../recipes/graphics/flickering-fluorescent.md),
[realistic flashlight](../../recipes/graphics/realistic-flashlight.md), [emergency red lighting](../../recipes/graphics/emergency-red-lighting.md).

## Light types
| Type | Shape | Parent | Use |
|---|---|---|---|
| `PointLight` | sphere, `Range` | Attachment (recommended) or BasePart | bulbs, torches, fire, fill |
| `SpotLight` | cone, `Angle` (≤<!-- fact-value: spotlight-angle-maximum -->180<!-- /fact-value -->), `Face`, `Range` | Attachment/BasePart | flashlights, street lamps, stage lights | <!-- fact-refs: spotlight-angle-maximum -->
| `SurfaceLight` | emits from a part face, `Angle`, `Face`, `Range` | BasePart | fluorescent panels, screens, windows (area-light look) |
Shared: `Color`, `Brightness` (intensity at center; does not extend range), `Range` (**max 120 studs**),
`Shadows` (expensive), `Enabled`. Studio setting "Show Light Guides" visualizes ranges.

## Practical lighting method
1. **Motivation**: every light has a visible source (fixture, window, screen, fire). Unmotivated light reads fake.
2. **Key / fill / rim**: one dominant source per space (key), weak non-shadowed fill to lift crushed blacks,
   optional rim/backlight to separate characters from background.
3. **Shadow budget**: only key lights cast shadows (`Shadows = true`); fills never. Target a handful of shadowed
   lights visible at once (mobile: fewer).
4. **Colour temperature**: pick a palette — warm tungsten (255,200,150) vs cool fluorescent (220,235,255) vs
   sodium-vapour orange (255,170,90) vs moonlight blue. Contrast warm vs cool areas; avoid rainbow lighting.
5. **Falloff**: smaller Range + higher Brightness = pools of light and darkness (moody); large Range + low Brightness
   = even wash (bright offices). Pools of light are the backbone of horror and liminal spaces.
6. **Fixtures glow**: the fixture surface itself uses `Neon` material or a SurfaceAppearance emissive mask
   (`EmissiveMaskContent`, `EmissiveStrength`, `EmissiveTint`) so bloom catches the source, not the wall.

## Faking bounce / global illumination (Roblox has no real-time GI for local lights)
- Place a low-Brightness, **non-shadowed**, large-Range `PointLight`/`SurfaceLight` where light would bounce (floor
  under a ceiling light, tinted by the floor colour; opposite wall of a window).
- Window light: `SurfaceLight` on the window pane pointing inward (Angle 90–120) + sun through the opening; a
  second weak fill near the floor for bounce.
- Keep `Ambient` very low and rely on fills: fills have direction and falloff, ambient doesn't.
- `EnvironmentDiffuseScale` gives sky-bounce outdoors and near openings for free.

## Light counts and performance
- Every light costs (light grid / shadow maps: `computeLightingPerform`, `ShadowMapSystem` in MicroProfiler).
  Shadowed lights cost most. Overlapping ranges multiply cost per pixel.
- For large repetitive ceilings (offices, Backrooms): every fixture emissive, but only every 2nd–4th has a real
  light; use SurfaceLights without shadows for the grid and a few shadowed ones near gameplay points.
- Disable lights far from the player on the client (room-based culling), or rely on streaming.
- Moving shadowed lights (flashlights, swinging lamps) are more expensive than static ones — keep one per player.

## Flicker and animated lights
Drive flicker on the **client** (each client runs its own cosmetic loop; no replication traffic), from a seeded
pattern per light so all clients look similar, or from a server-replicated state attribute (`On`, `Broken`) with
local cosmetic noise. Modulate `Brightness` (and the fixture's emissive/`Neon` colour together) with a buzzing
pattern: mostly on, short irregular drops, occasional longer outage. Sync a buzz/click sound. Respect
photosensitivity: avoid fast full-screen strobing (> 3 Hz) and offer a setting.

## Flashlight essentials
`SpotLight` on an Attachment in the camera-space viewmodel or the character's head/hand; `Angle` 40–60, `Range` 40–80,
`Brightness` 2–5, `Shadows = true` (the one shadowed light players carry); slight warm tint; smooth sway via springs;
optional wide low-brightness second SpotLight for soft spill. Other players see your flashlight only if it exists in
a replicated place (character) — attach to the character on the server or replicate a state and create it locally on
each client. Full recipe: [realistic flashlight](../../recipes/graphics/realistic-flashlight.md).

## Highlights and outlines
`Highlight` (FillColor/FillTransparency/OutlineColor/OutlineTransparency/`DepthMode` `AlwaysOnTop`|`Occluded`)
for interactable/selection feedback. Client renders at most **255** simultaneous Highlights (extra ones are silently
ignored; the old limit of 31 is outdated) — still reuse one Highlight and move its `Adornee` for hover/selection.

Sources: cd:effects/light-sources, cd:effects/highlighting, cd:reference/engine/classes/Light,
cd:reference/engine/classes/PointLight, cd:reference/engine/classes/SpotLight, cd:reference/engine/classes/SurfaceLight,
cd:reference/engine/classes/SurfaceAppearance, cd:reference/engine/classes/Lighting, cd:performance-optimization/improve.

## Verifying a lighting optimization
Capture `computeLightingPerform` before and after the proposed change under the same
camera route, graphics settings, device and visible scene. Report the captured cost,
not a guessed improvement from reducing the number of lights.
