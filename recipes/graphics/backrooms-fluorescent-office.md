# Recipe: Backrooms fluorescent office (Level 0 look)

## When NOT to use
Do not copy this visual preset unchanged into an unrelated scene or treat it as a measured performance budget.

## Architecture
Establish the scene and lighting intent first; apply the bounded presentation settings below, then verify the result on target devices. Keep visual effects separate from authoritative gameplay.

Evidence: preset TYPECHECKED/validated · look **not screenshot-verified**. Layout generator:
[procedural Backrooms](../gameplay/procedural-backrooms.md). Chapter: [environment art → liminal spaces](../../handbook/graphics/05-environment-art.md#liminal-spaces-backrooms-poolrooms-empty-offices-malls-at-night).

## Target look
Endless mono-yellow rooms, damp carpet, a ceiling grid of humming fluorescent panels; bright but oppressive;
**flatter than any other scene here** (the light really comes from everywhere above), slightly overexposed, low
contrast, faint haze in the distance, camcorder feel. Wrongness comes from repetition with small errors (a dead
panel, a stain, a doorway to nowhere), not from darkness.

## Build
- **Scale**: cells 10–14 studs, ceiling ~10 (a bit low), walls 1 stud thick; long sightlines through openings.
- **Materials**: walls `Plaster` or a wallpaper MaterialVariant in (196, 181, 122); carpet `Carpet`/`Fabric` in
  (150, 128, 82); ceiling tiles light cream; panels `Neon` (255, 244, 214) — dead panels `SmoothPlastic` grey.
- **Lighting**:
<!-- code: examples/lighting/ReplicatedStorage/LightingPresets.luau#BackroomsOffice -->
```luau
-- file: examples/lighting/ReplicatedStorage/LightingPresets.luau (region BackroomsOffice)
-- Sealed fluorescent office: the one mood where fairly flat, warm fill is correct (motivated by a ceiling full of
-- panels); slight overexposure and low contrast sell the camcorder look.
Presets.BackroomsOffice = {
	lighting = {
		ClockTime = 12,
		Brightness = 0, -- no sun reaches inside; also prevents leaks through gaps
		Ambient = rgb(66, 58, 38),
		OutdoorAmbient = rgb(66, 58, 38),
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0.1,
		ExposureCompensation = 0.3,
		ShadowSoftness = 0.7,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.25, Offset = 0, Color = rgb(200, 190, 150), Decay = rgb(160, 150, 110), Glare = 0, Haze = 1.5 },
	colorCorrection = { Brightness = 0, Contrast = -0.05, Saturation = -0.15, TintColor = rgb(255, 246, 214) },
	bloom = { Intensity = 0.6, Size = 30, Threshold = 1.2 },
}
```
<!-- /code -->
- **Local lights**: every panel emissive; `SurfaceLight` (Face Bottom, Angle 120, Range ~22, Brightness ~1.4,
  **Shadows off**) on every other lit panel — the grid produces the even wash; shadows would cost a lot and add
  little in this look. Flickering panels tagged `FlickerLight` ([flickering fluorescent](flickering-fluorescent.md)).
- **Distance**: Atmosphere haze hides the streaming edge; keep `Density` ≈ 0.25 so rooms 150+ studs away fade.
- **Post**: slight overexposure (+0.3), low contrast, warm tint; optional [camera look](camera-aesthetics.md) VHS/
  Bodycam overlay.
- **Sound**: constant fluorescent buzz bed (not spatialized) + a few spatial panel buzzes near flickering lights;
  carpet footsteps; very rare distant noises.

## Performance
Hundreds of panels: neon parts are cheap; real lights are not — keep ≤ ~16 SurfaceLights per 96×96-stud chunk and
rely on streaming to drop far chunks. Measure with the [heavy scene pass](heavy-scene-performance-pass.md).

## Common mistakes
| Mistake | Fix |
|---|---|
| Too dark / horror-house lighting | this look is bright and flat by design; keep fill from the ceiling grid |
| Saturated yellow | desaturate walls/carpet; tint comes from light + grade |
| Perfectly identical rooms | vary via hash: stains, dead panels, pillars, occasional wall gaps |
| Shadows on every panel light | Shadows off on the grid |

Sources: cd:environment/lighting, cd:reference/engine/classes/SurfaceLight, cd:reference/engine/classes/Atmosphere,
cd:performance-optimization/improve.
