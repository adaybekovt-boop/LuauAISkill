# Recipe: night exterior (moonlight)

## When NOT to use
Do not copy this visual preset unchanged into an unrelated scene or treat it as a measured performance budget.

## Architecture
Establish the scene and lighting intent first; apply the bounded presentation settings below, then verify the result on target devices. Keep visual effects separate from authoritative gameplay.

Evidence: preset TYPECHECKED/validated · look **not screenshot-verified**.
Chapters: [lighting](../../handbook/graphics/01-lighting.md), [atmosphere/sky](../../handbook/graphics/02-atmosphere-sky-post.md).

## Target look
Cool, dim moon key with real shadow direction; dark (not blue-flat) ambient; warm practicals (street lamps, windows)
as contrast islands; horizon slightly lighter than the ground so silhouettes read.

## Build
<!-- code: examples/lighting/ReplicatedStorage/LightingPresets.luau#NightExterior -->
```luau
-- file: examples/lighting/ReplicatedStorage/LightingPresets.luau (region NightExterior)
-- Moonlit exterior: one cool key (moon), dark ambient, warm practicals for contrast.
Presets.NightExterior = {
	lighting = {
		ClockTime = 1,
		GeographicLatitude = 35,
		Brightness = 0.35,
		Ambient = rgb(6, 7, 10),
		OutdoorAmbient = rgb(32, 38, 56),
		EnvironmentDiffuseScale = 0.35,
		EnvironmentSpecularScale = 0.6,
		ExposureCompensation = 0.4,
		ShadowSoftness = 0.25,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.33, Offset = 0.15, Color = rgb(60, 70, 95), Decay = rgb(25, 30, 45), Glare = 0, Haze = 1.4 },
	colorCorrection = { Brightness = 0, Contrast = 0.1, Saturation = -0.25, TintColor = rgb(225, 232, 255) },
	bloom = { Intensity = 0.4, Size = 24, Threshold = 1.8 },
}
```
<!-- /code -->
- **Moon**: `ClockTime` 1 with latitude 35 puts the moon high enough for readable shadows; `Brightness` 0.3–0.4.
  `Sky` with a moon texture/size you like (`MoonAngularSize`), stars on (`StarCount`).
- **Practicals**: street lamps `SpotLight` down (Angle 90, Range 30–40, Brightness 2–3, sodium (255, 170, 90) or LED
  (230, 240, 255)), shadows on the few near the path; windows `SurfaceLight` outward (warm, Range 12).
- **Clouds** (`Clouds` in Terrain): Cover 0.4–0.6, Density low; darker `Color` at night.
- **Distance**: Atmosphere Offset 0.15 keeps a faint horizon line; Density ~0.33 hides the map edge.

## Mistakes
Blue OutdoorAmbient 100+ (flat blue soup) · no key direction · pure-black shadows everywhere (raise exposure, not
ambient) · saturated moonlight.

Sources: cd:environment/lighting, cd:environment/skybox, cd:environment/atmosphere, cd:environment/clouds,
cd:reference/engine/classes/Sky.
