# Global lighting: how the Lighting properties actually work together

Read when: any scene's mood/lighting. Next: [atmosphere, sky, post](02-atmosphere-sky-post.md), [local lights](03-local-lights.md),
[materials](04-materials-pbr.md), scene recipes in [recipes/graphics](../../recipes/graphics/).

## Hard facts first (verified Sep 2026)
- `Lighting.Technology` is **not** available to scripts (RobloxScriptSecurity) and deprecated. Its successors:
  `Lighting.LightingStyle` (`Realistic` | `Soft`) and `Lighting.PrioritizeLightingQuality` (bool). Both are
  **Studio/plugin-only writes** (PluginOrOpenCloud capability; docs: "modifiable only in the Properties window").
  Game scripts can read them. So: pick the lighting style in Studio; runtime "graphics presets" change other things.
- `Realistic` = most advanced lighting + shadows (the old "Future" look: per-pixel local-light shadows, specular,
  PBR response). `Soft` = flat, retro Roblox look; with `PrioritizeLightingQuality = true`, Soft uses shadow maps
  instead of voxel lighting. `ShadowSoftness` (0 hard – 1 soft) applies with Realistic.
- `PrioritizeLightingQuality = true` keeps shadows/high-quality shading near the camera when the device lowers
  quality (at the cost of view distance); `false` keeps view distance. For moody interiors/horror: true.
- Engine disables shadows below graphics quality level 4 automatically. Design scenes that still read without
  shadows (low-end phones).
- Old look: `Technology.Compatibility` is deprecated; to imitate it use Voxel-style lighting + `ColorGradingEffect`
  with `TonemapperPreset.Retro` and light brightness ≤ 1.
- When an `Atmosphere` exists in Lighting, the legacy `FogStart/FogEnd/FogColor` are ignored/hidden.
- Local light range is clamped to **120 studs** (PointLight/SpotLight/SurfaceLight).
- `ExposureCompensation` range −5…5; +1 doubles exposure, −1 halves it.

## Property map (what each knob really does)
| Property | Affects | Typical use | Common mistake |
|---|---|---|---|
| `ClockTime` / `TimeOfDay`, `GeographicLatitude` | sun/moon direction, sky colour | set the key light angle (low sun = long shadows, warm) | noon sun (14:00) flattens everything |
| `Brightness` | sun/moon (directional key light) intensity | day 2–3, overcast 1–1.5, night 0–0.3 | cranking it to fix dark interiors (sun doesn't reach them) |
| `ExposureCompensation` | whole-image exposure before tonemapping | final balance: −1…+0.5 | using ColorCorrection.Brightness instead (clips/looks cheap) |
| `EnvironmentDiffuseScale` (0–1) | image-based ambient light from the **sky** onto surfaces | 1 outdoors for natural fill; 0.2–0.6 interiors | 0 + high Ambient = flat plastic look |
| `EnvironmentSpecularScale` (0–1) | sky **reflections** on smooth/metal surfaces | 1 outdoors (metals look like metal); 0.2–0.5 in sealed interiors (otherwise bright sky reflects in a dark room) | 0 makes metal look like grey plastic |
| `OutdoorAmbient` | flat fill in areas open to the sky | 70–130 grey (day), 20–40 bluish (night) | too high → washed out exteriors |
| `Ambient` | flat fill **everywhere**, including enclosed interiors | 0–30 for realistic/horror interiors; higher only for stylized | the #1 cause of the "cheap Roblox look": grey (128,128,128) ambient kills contrast and hides light direction |
| `ColorShift_Top` / `_Bottom` | tint on surfaces facing toward/away from sun | subtle warm top / cool bottom for sunsets | saturated shifts look toxic |
| `GlobalShadows` | sun/moon shadows | on (almost always) | off → floating objects |
| `ShadowSoftness` | penumbra softness (Realistic) | 0.1–0.3 crisp daylight; 0.5+ overcast | |
| `FogColor/Start/End` | legacy fog (ignored when Atmosphere exists) | use `Atmosphere` instead | |

Values above are starting points for art direction, not platform rules; always judge on target devices.

## Why scenes look washed-out or "cheap" (diagnosis → fix)
| Symptom | Cause | Fix |
|---|---|---|
| Everything evenly lit, no depth | high `Ambient`/`OutdoorAmbient`, no key light direction | lower ambient (0–30 interior), add a motivated key (window/lamp), let shadows exist |
| Grey, milky image | Atmosphere `Haze`/`Density` too high, `ExposureCompensation` too high, ColorCorrection Brightness > 0 | reduce haze, lower exposure, keep CC Brightness ≈ 0, add slight Contrast (0.05–0.15) |
| Everything glows | Bloom `Threshold` too low / Intensity too high; Neon everywhere | Threshold ≥ ~1.5–2 so only emissives/brightest pixels bloom, Intensity 0.2–0.6 |
| Toy/plastic materials | SmoothPlastic/Plastic everywhere, EnvironmentSpecularScale 0, no roughness variation | real materials/MaterialVariants/SurfaceAppearance, specular scale ≥ 0.5, roughness variety |
| Oversaturated neon candy | saturated part colours + Saturation > 0 + saturated lights | desaturate base colours (real materials are rarely > 70 % saturated), CC Saturation −0.1…0, keep light colours near-white with slight temperature |
| Flat night | pure blue ambient everywhere | dark ambient, a single moon key (Brightness 0.1–0.3, cool), warm practical lights for contrast |
| Interior lit by the sky through walls | thin/leaky walls, EnvironmentDiffuseScale high | thicker walls/ceilings, lower env diffuse indoors, `CastShadow` on blockers |
| Light banding/blotches | too many overlapping shadowed lights, low graphics level | fewer shadow-casters, bigger soft sources (SurfaceLight), fill without shadows |

## Scene lighting workflow (order matters)
1. **Blockout in neutral light**: default-ish lighting, grey materials. Check scale, sightlines, readability.
2. **Choose style**: `LightingStyle = Realistic` (Studio) for realism/horror; `PrioritizeLightingQuality = true` for
   close-up moody scenes.
3. **Key light**: sun angle (`ClockTime`, `GeographicLatitude`) for exteriors; for interiors decide the motivating
   sources (windows, ceiling fixtures, lamps, screens).
4. **Kill fake fill**: `Ambient` near black for interiors; tune `OutdoorAmbient` and `EnvironmentDiffuseScale` for
   exteriors.
5. **Practical lights** ([03](03-local-lights.md)): place where fixtures actually are; only a few cast shadows.
6. **Materials pass** ([04](04-materials-pbr.md)): check roughness/metal response under final lights.
7. **Atmosphere & sky** ([02](02-atmosphere-sky-post.md)): depth, colour of distance, mood.
8. **Exposure**: `ExposureCompensation` to put mid-greys where you want them.
9. **Post**: small ColorCorrection contrast/tint, Bloom with high threshold, optional ColorGrading preset,
   DepthOfField only for cinematic/menus.
10. **Test**: fixed camera shots on low/medium/high graphics levels and a real phone; walk the level.

## Runtime lighting changes (what scripts may change)
Scripts can change: `ClockTime`, `Brightness`, `ExposureCompensation`, `Ambient`, `OutdoorAmbient`,
`EnvironmentDiffuseScale/SpecularScale`, `ColorShift_*`, `GlobalShadows`, `ShadowSoftness`, `GeographicLatitude`,
Atmosphere/Sky/Clouds properties, post effects, local lights. Not: `LightingStyle`, `PrioritizeLightingQuality`,
`Technology`.
- Changes made on the **server** replicate to everyone (day/night cycle, blackout event). Per-player looks (a dream
  sequence, low-health vignette, a zone mood) → change on that **client** only; the server's next replicated change
  of the same property overwrites client edits, so own each property on exactly one side.
- Smooth transitions: `TweenService:Create(Lighting, TweenInfo.new(2), { ExposureCompensation = -0.5 })`.
- Zone moods: client blends between named presets (tables of Lighting/Atmosphere/CC values) when the camera enters
  tagged volumes; hysteresis to avoid flicker. Recipe: [lighting controller](../../recipes/graphics/lighting-controller-presets.md).

Sources: cd:environment/lighting, cd:reference/engine/classes/Lighting, cd:reference/engine/enums/LightingStyle,
cd:reference/engine/enums/Technology, cd:effects/light-sources, cd:reference/engine/classes/Atmosphere,
cd:performance-optimization/improve, api:Lighting.LightingStyle (write:plugin-only).
