# Recipe: cinematic horror interior (dark house at night)

Evidence: preset values TYPECHECKED and validated against the API index · look **not screenshot-verified** — tune
on your devices. Chapters: [lighting](../../handbook/graphics/01-lighting.md), [local lights](../../handbook/graphics/03-local-lights.md),
[environment art](../../handbook/graphics/05-environment-art.md#horror-environments), [audio](../../handbook/roblox/17-audio.md).

## Target look
Mostly darkness with **readable pools of motivated light**; cold moonlight through windows vs warm lamps; deep blacks
that still show silhouettes; dust in light shafts; sound doing half the work. Never evenly lit, never pitch-black
everywhere (players must read the space).

## Build order
1. **Space**: rooms 10–12 studs high, corridors 6–8 wide in first person (tight), doors 4–5 × 8–9, thick walls
   (≥ 0.5) and a sealed ceiling (no light leaks). Sightlines with occluders: doorframes, furniture, corners.
2. **Materials**: wood floors (`WoodPlanks` or MaterialVariant), plaster walls (`Plaster`), fabric, rust on metal;
   desaturated base colours (≤ 60 % saturation); roughness variety so the flashlight shows specular on varnish/metal.
3. **Global lighting** (Studio: `LightingStyle = Realistic`, `PrioritizeLightingQuality = true`), then this preset:
<!-- code: examples/lighting/ReplicatedStorage/LightingPresets.luau#HorrorInterior -->
```luau
-- file: examples/lighting/ReplicatedStorage/LightingPresets.luau (region HorrorInterior)
-- Dark house at night: moonlight through windows as the only sky light, practical lamps do the work.
Presets.HorrorInterior = {
	lighting = {
		ClockTime = 0,
		Brightness = 0.3, -- moon
		Ambient = rgb(6, 6, 8), -- near-black: light must come from sources
		OutdoorAmbient = rgb(24, 27, 36),
		EnvironmentDiffuseScale = 0.15,
		EnvironmentSpecularScale = 0.3,
		ExposureCompensation = 0,
		ShadowSoftness = 0.4,
		GlobalShadows = true,
	},
	atmosphere = { Density = 0.25, Offset = 0.1, Color = rgb(40, 44, 52), Decay = rgb(20, 22, 28), Glare = 0, Haze = 1 },
	colorCorrection = { Brightness = 0, Contrast = 0.15, Saturation = -0.3, TintColor = rgb(235, 240, 255) },
	bloom = { Intensity = 0.4, Size = 24, Threshold = 1.8 },
}
```
<!-- /code -->
4. **Local lights** (plan, per room):
| Light | Type | Brightness / Range | Shadows | Colour |
|---|---|---|---|---|
| Table lamp (key) | PointLight in shade | 1.2–2 / 12–16 | yes | warm (255, 190, 130) |
| Window moonlight | SurfaceLight on pane, inward, Angle 100 | 0.4–0.8 / 20 | yes (one per room) | cool (170, 190, 255) |
| Bounce fill under lamp | PointLight near floor | 0.15–0.3 / 14 | no | lamp colour, dimmer |
| Hallway bulb (practical) | PointLight | 1–1.5 / 14 | yes if on the play path | warm, slightly green |
| TV / monitor glow | SurfaceLight on screen | 0.5 / 10 | no | cool, animated on client |
Budget: ≤ 3–4 shadowed lights visible at once (mobile ≤ 2); the player's flashlight is always one of them
([realistic flashlight](realistic-flashlight.md)).
5. **Atmosphere & effects**: dust `ParticleEmitter` in light shafts (tag `FX_Decor`, low rate, Size 0.05–0.1, slow
   drift, LightInfluence 1 so it only shows in light); no `SunRays` indoors.
6. **Exposure pass**: adjust `ExposureCompensation` last so the lamp-lit wall reads mid-grey and corners stay black.

## Sound
Layers (Audio API or `Sound`, client-side, see the [audio chapter](../../handbook/roblox/17-audio.md)):
1. Room tone bed per room (very quiet low hum/wind), crossfaded by zone.
2. Spot emitters: clock tick, fridge hum, rain on windows — short attenuation, randomized start offsets.
3. Stingers: creaks, distant thuds, 30–90 s apart with cooldowns, placed behind/around the player.
4. Footsteps on wood with occasional creak variants ([footsteps](../gameplay/footsteps.md)).
5. Silence before scares; duck ambience under stingers.
Accessibility: captions for threat sounds (subtitles setting), visual cues for important audio.

## Common mistakes → fixes
| Mistake | Fix |
|---|---|
| Ambient 60–128 "so players can see" | keep Ambient near black; add motivated fills and a flashlight |
| Pitch black everywhere | pools of light + moon fill through windows; exposure +0.2…+0.4 |
| Bloom halos on every surface | Threshold ≥ 1.6; only fixtures (Neon/emissive) exceed it |
| Blue-tinted everything | cool only for moonlit areas; warm practicals for contrast |
| 20 shadowed lamps | shadows on key lights near the path only |

## Test shots (fixed cameras, low/medium/high graphics, a phone)
Doorway looking into a lamp-lit room · dark corridor toward a window · close-up of a face lit by flashlight ·
the darkest corner (must still show silhouettes at quality level 1).

Sources: cd:environment/lighting, cd:effects/light-sources, cd:reference/engine/classes/Lighting,
cd:reference/engine/classes/Atmosphere, cd:reference/engine/classes/SurfaceLight, cd:audio/index,
cd:tutorials/use-case-tutorials/lighting/enhance-indoor-environments.
