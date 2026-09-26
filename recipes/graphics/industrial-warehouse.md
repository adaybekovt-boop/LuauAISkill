# Recipe: industrial warehouse (sun through high windows, dust, metal)

Evidence: preset TYPECHECKED/validated · look **not screenshot-verified**.
Chapters: [materials/PBR](../../handbook/graphics/04-materials-pbr.md), [lighting](../../handbook/graphics/01-lighting.md).

## Target look
Huge dim volume (20–40 studs high) crossed by bright sun shafts from skylights/high windows; concrete floor with
stains, steel columns and racking, a few sodium or LED high-bay fixtures; floating dust visible only in the shafts.

## Build
<!-- code: examples/lighting/ReplicatedStorage/LightingPresets.luau#IndustrialWarehouse -->
```luau
-- file: examples/lighting/ReplicatedStorage/LightingPresets.luau (region IndustrialWarehouse)
-- Afternoon sun through high windows/skylights, dust, cool metal and concrete.
Presets.IndustrialWarehouse = {
	lighting = {
		ClockTime = 15,
		GeographicLatitude = 40,
		Brightness = 2.5,
		Ambient = rgb(10, 10, 12),
		OutdoorAmbient = rgb(90, 95, 105),
		EnvironmentDiffuseScale = 0.5,
		EnvironmentSpecularScale = 0.6,
		ExposureCompensation = -0.1,
		ShadowSoftness = 0.2,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.3, Offset = 0.05, Color = rgb(170, 165, 150), Decay = rgb(90, 88, 80), Glare = 0.2, Haze = 1 },
	colorCorrection = { Brightness = 0, Contrast = 0.12, Saturation = -0.15, TintColor = rgb(250, 245, 235) },
	bloom = { Intensity = 0.35, Size = 24, Threshold = 1.8 },
	sunRays = { Intensity = 0.06, Spread = 0.5 },
}
```
<!-- /code -->
- **Sun shafts**: real sun through openings is the key light → `GlobalShadows` on, walls/roof thick and sealed except
  the windows; choose `ClockTime`/latitude so beams land on the play space. `SunRays` only helps when the sun disk
  is on screen.
- **Dust**: ParticleEmitters inside the beam volumes (tag `FX_Decor`), `LightInfluence` 1, tiny size, slow drift.
- **High-bay lights**: `SpotLight` down (Angle 100, Range 40–60, Brightness 1–2), shadows off except 1–2 hero lights.
- **Materials**: `Concrete` floor with a darker `MaterialVariant` for stains, `CorrodedMetal`/`DiamondPlate`/`Metal`
  for structure, `EnvironmentSpecularScale` ≥ 0.5 so metal looks metallic.
- **Scale cues**: pallets, forklifts, stairs — without them the space reads as a small room.

## Mistakes
Interior lit by high Ambient instead of sun shafts · metals as SmoothPlastic · no dark areas between shafts ·
dust everywhere (should only appear in light).

Sources: cd:environment/lighting, cd:art/modeling/material-reference, cd:parts/materials,
cd:reference/engine/classes/ParticleEmitter, cd:reference/engine/classes/SunRaysEffect.
