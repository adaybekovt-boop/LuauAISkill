# Recipe: realistic dark corridor

## When NOT to use
Do not copy this visual preset unchanged into an unrelated scene or treat it as a measured performance budget.

## Architecture
Establish the scene and lighting intent first; apply the bounded presentation settings below, then verify the result on target devices. Keep visual effects separate from authoritative gameplay.

Evidence: preset TYPECHECKED/validated · look **not screenshot-verified**.
Chapters: [local lights](../../handbook/graphics/03-local-lights.md), [lighting](../../handbook/graphics/01-lighting.md).

## Target look
Long corridor where darkness separates **pools of light**: a working ceiling lamp every 12–20 studs (some dead), light
spilling from a half-open door, an exit sign glow. The eye travels from pool to pool; the space between is black but
not empty (silhouettes, reflections on a wet floor).

## Build
- 6–8 studs wide, 10 high; strong perspective (length ≥ 60 studs); side doors every 10–15 studs; pipes/cable trays on
  the ceiling for silhouettes; floor with some roughness variation (concrete + polished patches) so lights reflect.
- **Lighting**:
<!-- code: examples/lighting/ReplicatedStorage/LightingPresets.luau#DarkCorridor -->
```luau
-- file: examples/lighting/ReplicatedStorage/LightingPresets.luau (region DarkCorridor)
-- Realistic dark corridor: pools of practical light separated by true darkness.
Presets.DarkCorridor = {
	lighting = {
		ClockTime = 0,
		Brightness = 0,
		Ambient = rgb(3, 3, 4),
		OutdoorAmbient = rgb(0, 0, 0),
		EnvironmentDiffuseScale = 0,
		EnvironmentSpecularScale = 0.2,
		ExposureCompensation = 0.3, -- lift the lit pools, keep the blacks
		ShadowSoftness = 0.3,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.35, Offset = 0, Color = rgb(30, 30, 34), Decay = rgb(10, 10, 12), Glare = 0, Haze = 0.8 },
	colorCorrection = { Brightness = 0, Contrast = 0.2, Saturation = -0.2, TintColor = rgb(230, 236, 255) },
	bloom = { Intensity = 0.3, Size = 20, Threshold = 2 },
}
```
<!-- /code -->
- **Pools**: `SpotLight` pointing down from each fixture (Angle 70–90, Range 14–18, Brightness 2–3) → hard-edged
  pools; every other one `Shadows = true`. Fixture `Neon` so bloom catches it.
- **Door spill**: `SurfaceLight` on the door gap, narrow, warm; the only warm light in a cool corridor.
- **Exit sign**: small green/red `Neon` part + tiny `PointLight` (Range 6, Brightness 0.5).
- **Floor reflections**: `EnvironmentSpecularScale` stays low (0.2) so the sky doesn't reflect indoors; local lights
  still create specular highlights on smooth materials.

## Mistakes
Uniform light every 5 studs (reads like an office) · Ambient > 10 (pools disappear) · all lights with shadows ·
no fixture glow (light from nowhere).

Sources: cd:effects/light-sources, cd:reference/engine/classes/SpotLight, cd:reference/engine/classes/Lighting.
