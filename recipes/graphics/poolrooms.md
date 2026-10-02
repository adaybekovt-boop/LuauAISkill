# Recipe: poolrooms (tiled liminal pools)

## When NOT to use
Do not copy this visual preset unchanged into an unrelated scene or treat it as a measured performance budget.

## Architecture
Establish the scene and lighting intent first; apply the bounded presentation settings below, then verify the result on target devices. Keep visual effects separate from authoritative gameplay.

Evidence: preset TYPECHECKED/validated · look **not screenshot-verified**.
Chapter: [environment art → liminal spaces](../../handbook/graphics/05-environment-art.md#liminal-spaces-backrooms-poolrooms-empty-offices-malls-at-night).

## Target look
White/pale-cyan tiled rooms and pools, soft daylight from skylights, strong reflections, humid haze, gentle water
caustic feel, echoing sound. Bright, clean, unsettling.

## Build
<!-- code: examples/lighting/ReplicatedStorage/LightingPresets.luau#Poolrooms -->
```luau
-- file: examples/lighting/ReplicatedStorage/LightingPresets.luau (region Poolrooms)
-- Tiled, humid, bright and soft: skylight-lit, strong reflections, pale cyan haze.
Presets.Poolrooms = {
	lighting = {
		ClockTime = 13,
		Brightness = 1.5,
		Ambient = rgb(60, 70, 75),
		OutdoorAmbient = rgb(140, 160, 170),
		EnvironmentDiffuseScale = 0.8,
		EnvironmentSpecularScale = 1, -- wet tiles must reflect
		ExposureCompensation = 0.35,
		ShadowSoftness = 0.6,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.35, Offset = 0, Color = rgb(200, 230, 235), Decay = rgb(160, 200, 205), Glare = 0, Haze = 2 },
	colorCorrection = { Brightness = 0, Contrast = -0.05, Saturation = -0.05, TintColor = rgb(240, 252, 255) },
	bloom = { Intensity = 0.7, Size = 32, Threshold = 1.2 },
}
```
<!-- /code -->
- **Tiles**: a `MaterialVariant` (base `Tile` or `Marble`) with small square pattern, low roughness; slight colour
  variation between rooms. Grout lines must be visible at play distance or the space reads as plastic.
- **Water**: Terrain water (set `Terrain.WaterColor`, `WaterTransparency` high, `WaterReflectance` moderate,
  `WaterWaveSize` small) for real refraction/waves; or `Glass` parts with high transparency for shallow sheets.
- **Skylights**: sun through ceiling openings (`GlobalShadows` on) + `SurfaceLight`s under skylights for soft fill.
- **Caustic hint**: a slowly scrolling `Texture` (your uploaded caustic image) on pool floors (client-side
  `OffsetStudsU/V` animation) — cosmetic, optional.
- **Sound**: long reverb (AudioReverb or `SoundService.AmbientReverb` for legacy sounds), dripping, distant splashes.

## Mistakes
Saturated turquoise (keep Saturation ≈ 0 and colours pale) · no reflections (EnvironmentSpecularScale 1) · flat
lighting with no skylight direction · opaque water.

Sources: cd:parts/terrain, cd:reference/engine/classes/Terrain, cd:art/modeling/material-reference,
cd:reference/engine/classes/Texture, cd:audio/effects.
