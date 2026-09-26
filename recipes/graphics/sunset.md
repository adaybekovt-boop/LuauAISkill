# Recipe: sunset / golden hour

Evidence: preset TYPECHECKED/validated · look **not screenshot-verified**.
Chapters: [lighting](../../handbook/graphics/01-lighting.md), [atmosphere/sky](../../handbook/graphics/02-atmosphere-sky-post.md).

## Target look
Low warm sun, long shadows, glowing orange-pink horizon, cool shadow side, rim light on silhouettes.

## Build
<!-- code: examples/lighting/ReplicatedStorage/LightingPresets.luau#Sunset -->
```luau
-- file: examples/lighting/ReplicatedStorage/LightingPresets.luau (region Sunset)
-- Low warm sun, long shadows, glowing horizon.
Presets.Sunset = {
	lighting = {
		ClockTime = 18.1,
		GeographicLatitude = 30,
		Brightness = 2.2,
		Ambient = rgb(20, 16, 18),
		OutdoorAmbient = rgb(110, 90, 90),
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 1,
		ExposureCompensation = 0,
		ShadowSoftness = 0.15,
		ColorShift_Top = rgb(60, 30, 10), -- subtle warm tint on sun-facing surfaces
		ColorShift_Bottom = rgb(0, 0, 0),
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.3, Offset = 0.25, Color = rgb(255, 190, 150), Decay = rgb(130, 90, 110), Glare = 0.6, Haze = 1.8 },
	colorCorrection = { Brightness = 0, Contrast = 0.08, Saturation = 0.05, TintColor = rgb(255, 244, 235) },
	bloom = { Intensity = 0.5, Size = 28, Threshold = 1.6 },
	sunRays = { Intensity = 0.08, Spread = 0.8 },
}
```
<!-- /code -->
- **Sun angle**: the exact `ClockTime` for "just above the horizon" depends on `GeographicLatitude`; start at 18.1
  with latitude 30 and nudge in 0.05 steps until shadows are ~4–6× object height.
- **Atmosphere** does the sky colour: warm `Color`, purple-ish `Decay`, `Glare` 0.5–0.8 for the sun bloom, `Haze`
  1.5–2 for depth; `Offset` 0.2–0.3 to keep distant mountains as silhouettes.
- **SunRays** only when the sun is visible through gaps (trees, windows): Intensity ≤ 0.1.
- **Materials**: water and wet surfaces sell sunsets (Terrain water, `EnvironmentSpecularScale` 1).
- **Composition**: shoot toward the sun for silhouettes, away from it for warm-lit fronts.
- **Animated time of day**: tween `ClockTime` slowly on the **server** (replicates to all) or on clients from a
  server start time; don't mix both.

## Mistakes
Orange everything (tint only the sun side via light colour/ColorShift_Top) · Brightness 3+ blowing out the sky ·
Saturation +0.3 (candy) · forgetting that noon values of OutdoorAmbient look grey at sunset.

Sources: cd:environment/lighting, cd:environment/atmosphere, cd:reference/engine/classes/SunRaysEffect,
cd:reference/engine/classes/Lighting.
