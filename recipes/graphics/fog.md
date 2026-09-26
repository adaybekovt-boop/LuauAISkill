# Recipe: fog scenes (overcast fog, horror fog, fog as a streaming/draw-distance tool)

Evidence: preset TYPECHECKED/validated · look **not screenshot-verified**.
Chapter: [atmosphere/sky/post](../../handbook/graphics/02-atmosphere-sky-post.md).

## Facts that decide the approach
- `Atmosphere` is the fog system; when an Atmosphere exists, legacy `Lighting.FogStart/FogEnd/FogColor` are ignored.
- `Density` = how thick; `Offset` = how much the horizon/sky shows through; `Color` = the fog colour lit by the sun;
  `Decay` = colour of light far away/away from the sun; `Haze` = extra haze toward the horizon; `Glare` = sun glow.
- Fog changes **what players can see** → keep it identical across graphics tiers and on all clients (gameplay
  fairness). Change it on the server if it's a gameplay event (it replicates), on a client only for cosmetic zones.

## Overcast day fog
<!-- code: examples/lighting/ReplicatedStorage/LightingPresets.luau#FogDay -->
```luau
-- file: examples/lighting/ReplicatedStorage/LightingPresets.luau (region FogDay)
-- Overcast, thick fog: soft shadows, grey-white distance, silhouettes.
Presets.FogDay = {
	lighting = {
		ClockTime = 10,
		Brightness = 1.2,
		Ambient = rgb(40, 42, 45),
		OutdoorAmbient = rgb(120, 124, 128),
		EnvironmentDiffuseScale = 1,
		EnvironmentSpecularScale = 0.6,
		ExposureCompensation = 0.1,
		ShadowSoftness = 0.8,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.55, Offset = 0, Color = rgb(185, 190, 195), Decay = rgb(150, 155, 160), Glare = 0, Haze = 3 },
	colorCorrection = { Brightness = 0, Contrast = 0.02, Saturation = -0.2, TintColor = rgb(245, 248, 255) },
	bloom = { Intensity = 0.25, Size = 24, Threshold = 2 },
}
```
<!-- /code -->
Soft shadows (`ShadowSoftness` 0.8), grey-white distance, silhouettes at 60–120 studs.

## Horror fog (night)
Start from [NightExterior](night-exterior.md) and raise `Atmosphere.Density` to 0.5–0.65 with a dark `Color`
(40, 45, 55) and `Decay` (15, 18, 22); `Offset` 0 so nothing shows on the horizon. Local lights inside fog get a halo
from bloom (Threshold 1.4–1.6) — the classic street-lamp-in-fog look.

## Fog as a performance tool
Dense fog lets you lower `StreamingTargetRadius` and cull decoration beyond the visible distance. It does not reduce
rendering cost by itself for content that is still loaded — pair it with streaming/LOD.

## Mistakes
Milky, grey image with no contrast (lower Haze, add Contrast 0.05–0.15) · fog that differs between players ·
using Blur for fog (blurs UI-less world uniformly, not by distance).

Sources: cd:environment/atmosphere, cd:reference/engine/classes/Atmosphere, cd:reference/engine/classes/Lighting,
cd:workspace/streaming/index.
