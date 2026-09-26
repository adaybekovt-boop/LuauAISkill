# Atmosphere, sky, clouds, post-processing

Read when: mood, depth, weather, time of day, cinematic look. Prereq: [lighting](01-lighting.md).

## Atmosphere (`Atmosphere` in Lighting) — API defaults in brackets
| Property | Effect | Guidance |
|---|---|---|
| `Density` [0.395] | amount of particles; obscures distant objects (and sky behind them) | clear day 0.25–0.35; hazy 0.4–0.5; fog 0.6–0.8 (combine with low Offset) |
| `Offset` [0] | light transmission camera↔sky: high = horizon silhouette, low = distant objects blend into sky | 0–0.25 for seamless open worlds; higher for crisp skylines |
| `Haze` [0] | haziness above horizon & into distance, tinted by `Color` | 0–2 typical; > 3 gets milky fast |
| `Color` [200,170,108] | atmosphere hue (visible with Haze) | match sky/sun colour: warm for sunset, blue-grey for overcast, green-grey for toxic |
| `Glare` [0] | glow around the sun (needs Haze > 0) | 0–1 subtle; high for desert/sunset drama |
| `Decay` [92,60,14] | hue away from the sun (needs Haze and Glare > 0) | darker/cooler than Color for gradient skies |
Atmosphere replaces legacy fog. For **interiors**, Atmosphere still applies over distance — long corridors fade into
Atmosphere colour, which is great for liminal depth (dim warm haze) but set Density low if interiors are short.

## Sky (`Sky` in Lighting)
- Six skybox faces (`SkyboxBk/Dn/Ft/Lf/Rt/Up` or the `*Content` versions), `SkyboxOrientation`, `SunAngularSize`
  [21], `MoonAngularSize` [11], `StarCount` [3000], `CelestialBodiesShown`, `SunTextureId`/`MoonTextureId`.
- The sky drives **image-based lighting**: `EnvironmentDiffuseScale`/`EnvironmentSpecularScale` sample it. A bright
  blue daytime sky makes shadows blue-ish and reflections bright — that's realism. For an indoor-only game, a dark,
  neutral sky prevents bright sky reflections in closed rooms.
- Night: darker skybox + stars + moon; `Brightness` 0–0.3; `OutdoorAmbient` dark desaturated blue.

## Clouds (`Clouds` in Workspace.Terrain)
`Cover` [0.5] (0–1), `Density` [0.7], `Color`, `Enabled`. Volumetric clouds move with `Workspace.GlobalWind`.
Overcast: Cover 0.8–0.95, grey Color, Brightness 1–1.5, softer shadows (`ShadowSoftness` up). Clouds cost GPU — scale
with quality tiers if needed (toggle `Enabled` on low).

## Post-processing (in `Lighting` = everyone; in `Camera` = that player only)
| Effect | Defaults | Realistic guidance | Pitfalls |
|---|---|---|---|
| `BloomEffect` | Intensity 0.4, Size 24, Threshold 0.95 | Threshold 1.5–2.5, Intensity 0.2–0.6, Size 16–32 → only lamps/emissives/sun glint bloom | low threshold = everything glows (amateur look) |
| `ColorCorrectionEffect` | Brightness 0, Contrast 0, Saturation 0, TintColor white | Contrast 0.05–0.2, Saturation −0.2…0.05, TintColor very slight (e.g. 255,245,235 warm / 235,242,255 cool) | using Brightness for exposure (clips), strong tints |
| `ColorGradingEffect` | TonemapperPreset Default | `Default` = modern vivid/high contrast; `Retro` = pre-2019 low-contrast look | not a LUT system; only presets |
| `DepthOfFieldEffect` | Far 0.75, FocusDistance 0.05, InFocusRadius 10, Near 0.75 | cinematics, menus, photo mode; gameplay: FarIntensity ≤ 0.2 with large InFocusRadius | hides enemies/information; cost on mobile |
| `SunRaysEffect` | Intensity 0.25, Spread 1 | Intensity 0.02–0.1, Spread 0.2–0.6 for realism | default is strong; rays through every tree |
| `BlurEffect` | Size 24 | menus/pauses (in Camera for local player) | leaving it on after closing menu |
Stacking: one of each type is normal; multiple ColorCorrection effects multiply — keep one "base grade" in Lighting
and add temporary ones (damage flash, dream) in Camera on the client, tweened in/out and destroyed afterwards.

## Weather and time recipes (starting points)
| Look | Lighting | Atmosphere | Post |
|---|---|---|---|
| Clear midday | ClockTime 12–13, Brightness 2.5–3, OutdoorAmbient 110, EnvDiffuse 1, EnvSpec 1 | Density 0.3, Offset 0.1, Haze 0.5 | CC Contrast 0.08, Bloom thr 2 |
| Golden hour / sunset | ClockTime 17.5–18.2, Brightness 2, ColorShift_Top warm (255,200,150) subtle | Density 0.35, Haze 1.5–2.5, Glare 0.5–1, Color warm orange, Decay dark purple | CC TintColor slight warm, SunRays 0.05 |
| Overcast / rain | ClockTime 13, Brightness 1–1.3, ShadowSoftness 0.6+ | Density 0.45, Haze 2–3, Color grey-blue | CC Saturation −0.15, Contrast 0.05; rain particles + wet materials (lower roughness) |
| Fog / mist | Brightness 1, low sun | Density 0.6–0.8, Offset 0–0.1, Haze 2 | keep exposure moderate; add ground fog cards sparingly |
| Moonlit night | ClockTime 0–2, Brightness 0.15–0.3, OutdoorAmbient (25,30,45), Ambient ~(5,5,8) | Density 0.35, Color cool, Haze 0.5 | CC Saturation −0.2, cool tint; warm practicals for contrast |
Test each on low graphics (no shadows, reduced effects) to ensure readability.

## Per-player effects pattern (client)
```luau
--!strict
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local camera = workspace.CurrentCamera

-- Low-health vignette/desaturation: lives in Camera so only this player sees it.
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "LowHealthGrade"
cc.Parent = camera

local function setDanger(amount: number) -- 0..1
	TweenService:Create(cc, TweenInfo.new(0.25), {
		Saturation = -0.6 * amount,
		TintColor = Color3.new(1, 1 - 0.3 * amount, 1 - 0.3 * amount),
	}):Play()
end
setDanger(0.5)
print(Lighting.ClockTime)
```

Sources: cd:environment/atmosphere, cd:environment/skybox, cd:environment/clouds, cd:environment/post-processing-effects,
cd:environment/global-wind, cd:reference/engine/classes/Atmosphere, cd:reference/engine/classes/Sky,
cd:reference/engine/classes/Clouds, cd:reference/engine/classes/BloomEffect, cd:reference/engine/classes/ColorGradingEffect,
api:Atmosphere (defaults from API dump 0.740.19).
