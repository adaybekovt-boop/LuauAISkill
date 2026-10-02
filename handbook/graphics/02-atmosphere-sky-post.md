# Atmosphere, sky, clouds, post-processing

## TL;DR
- Tune atmosphere for readable depth, not uniform fog.
- Keep sky and atmosphere consistent.
- Use post-processing sparingly and with a clear purpose.
- Parent per-player post effects to the camera.
- Treat weather presets as starting points that need visual checks.

Read when: mood, depth, weather, time of day, cinematic look. Prereq: [lighting](01-lighting.md).

## Atmosphere (`Atmosphere` in Lighting) — API defaults in brackets
| Property | Effect | Guidance |
|---|---|---|
| `Density` [<!-- fact-value: atmosphere-density-default -->0.395000011<!-- /fact-value -->] | amount of particles; obscures distant objects (and sky behind them) | clear day 0.25–0.35; hazy 0.4–0.5; fog 0.6–0.8 (combine with low Offset) | <!-- fact-examples: {"values": ["0.25", "0.35", "0.4", "0.5", "0.6", "0.8"], "reason": "Illustrative aesthetic/test/code values; not additional platform limits."} -->
| `Offset` [<!-- fact-value: atmosphere-offset-default -->0<!-- /fact-value -->] | light transmission camera↔sky: high = horizon silhouette, low = distant objects blend into sky | 0–0.25 for seamless open worlds; higher for crisp skylines | <!-- fact-examples: {"values": ["0.25", "0"], "reason": "Illustrative aesthetic/test/code values; not additional platform limits."} -->
| `Haze` [<!-- fact-value: atmosphere-haze-default -->0<!-- /fact-value -->] | haziness above horizon & into distance, tinted by `Color` | 0–2 typical; > 3 gets milky fast | <!-- fact-examples: {"values": ["2", "3", "0"], "reason": "Illustrative aesthetic/test/code values; not additional platform limits."} -->
| `Color` [<!-- fact-value: atmosphere-color-default -->0.7843, 0.6667, 0.4235<!-- /fact-value -->] | atmosphere hue (visible with Haze) | match sky/sun colour: warm for sunset, blue-grey for overcast, green-grey for toxic |
| `Glare` [<!-- fact-value: atmosphere-glare-default -->0<!-- /fact-value -->] | glow around the sun (needs Haze > 0) | 0–1 subtle; high for desert/sunset drama | <!-- fact-examples: {"values": ["1", "0"], "reason": "Illustrative aesthetic/test/code values; not additional platform limits."} -->
| `Decay` [<!-- fact-value: atmosphere-decay-default -->0.3608, 0.2353, 0.0549<!-- /fact-value -->] | hue away from the sun (needs Haze and Glare > 0) | darker/cooler than Color for gradient skies | <!-- fact-examples: {"values": ["0"], "reason": "Illustrative aesthetic/test/code values; not additional platform limits."} -->
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
| `BloomEffect` | Intensity <!-- fact-value: bloom-effect-intensity-default -->0.400000006<!-- /fact-value -->, Size <!-- fact-value: bloom-effect-size-default -->24<!-- /fact-value -->, Threshold <!-- fact-value: bloom-effect-threshold-default -->0.949999988<!-- /fact-value --> | Threshold 1.5–2.5, Intensity 0.2–0.6, Size 16–32 → only lamps/emissives/sun glint bloom | low threshold = everything glows (amateur look) | <!-- fact-examples: {"values": ["1.5", "2.5", "0.2", "0.6", "16", "32"], "reason": "Illustrative aesthetic/test/code values; not additional platform limits."} -->
| `ColorCorrectionEffect` | Brightness <!-- fact-value: color-correction-effect-brightness-default -->0<!-- /fact-value -->, Contrast <!-- fact-value: color-correction-effect-contrast-default -->0<!-- /fact-value -->, Saturation <!-- fact-value: color-correction-effect-saturation-default -->0<!-- /fact-value -->, TintColor white | Contrast 0.05–0.2, Saturation −0.2…0.05, TintColor very slight (e.g. 255,245,235 warm / 235,242,255 cool) | using Brightness for exposure (clips), strong tints | <!-- fact-examples: {"values": ["0.05", "0.2", "−0.2", "255,245,235", "235,242,255"], "reason": "Illustrative aesthetic/test/code values; not additional platform limits."} -->
| `ColorGradingEffect` | TonemapperPreset Default | `Default` = modern vivid/high contrast; `Retro` = older low-contrast look | not a LUT system; only presets |
| `DepthOfFieldEffect` | FarIntensity <!-- fact-value: dof-default-far-intensity -->0.75<!-- /fact-value -->, FocusDistance <!-- fact-value: dof-default-focus-distance -->0.05<!-- /fact-value -->, InFocusRadius <!-- fact-value: dof-default-in-focus-radius -->10<!-- /fact-value -->, NearIntensity <!-- fact-value: dof-default-near-intensity -->0.75<!-- /fact-value --> | cinematics, menus, photo mode; gameplay: FarIntensity ≤ 0.2 with large InFocusRadius | hides enemies/information; cost on mobile | <!-- fact-refs: dof-default-far-intensity, dof-default-focus-distance, dof-default-in-focus-radius, dof-default-near-intensity --> <!-- fact-examples: {"values": ["0.2"], "reason": "Illustrative aesthetic/test/code values; not additional platform limits."} -->
| `SunRaysEffect` | Intensity <!-- fact-value: sun-rays-effect-intensity-default -->0.25<!-- /fact-value -->, Spread <!-- fact-value: sun-rays-effect-spread-default -->1<!-- /fact-value --> | Intensity 0.02–0.1, Spread 0.2–0.6 for realism | default is strong; rays through every tree | <!-- fact-examples: {"values": ["0.02", "0.1", "0.2", "0.6"], "reason": "Illustrative aesthetic/test/code values; not additional platform limits."} -->
| `BlurEffect` | Size <!-- fact-value: blur-effect-size-default -->24<!-- /fact-value --> | menus/pauses (in Camera for local player) | leaving it on after closing menu |
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
api:Atmosphere (defaults from API dump 0.740.19; unchanged in 0.741.19).
