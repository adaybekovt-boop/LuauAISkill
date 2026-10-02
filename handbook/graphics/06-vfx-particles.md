# VFX: particles, beams, trails, decals, transparency cost

## TL;DR
- Choose particles, beams, or trails for the effect shape.
- Make timing and silhouette readable before adding detail.
- Keep cosmetic presentation separate from authoritative gameplay.
- Budget screen coverage and effect concurrency.
- Pool and clean up effects with explicit ownership.

Read when: dust, smoke, sparks, rain, muzzle flashes, magic, blood, weather.
Related: [local lights](03-local-lights.md), [quality tiers](07-quality-tiers.md), [performance](../roblox/08-performance.md#gpu--render-thread).

## Objects
| Object | Use | Key properties |
|---|---|---|
| `ParticleEmitter` (in a part = volume/surface emission; in an Attachment = point) | smoke, dust, sparks, rain, fire | `Rate`, `Lifetime` (NumberRange), `Speed`, `SpreadAngle`, `Acceleration`, `Drag`, `Size`/`Transparency` (NumberSequence), `Color` (ColorSequence), `LightEmission` (blending endpoints <!-- fact-value: particle-light-emission-endpoints -->[0, 1]<!-- /fact-value -->), `LightInfluence` (how scene light affects it <!-- fact-value: particle-light-influence-range -->[0, 1]<!-- /fact-value -->), `Brightness`, `Orientation`, `Squash`, `ZOffset`, `FlipbookLayout`/`FlipbookMode` (texture must be dimensions <!-- fact-value: particle-flipbook-texture -->[1024, 1024]<!-- /fact-value --> for flipbooks), `Shape`/`ShapeStyle`, `LockedToPart`, `VelocityInheritance`, `TimeScale`, `WindAffectsDrag` | <!-- fact-refs: particle-light-emission-endpoints, particle-light-influence-range, particle-flipbook-texture -->
| `ParticleEmitter:Emit(n)` | one-shot bursts (impacts, muzzle flash) with `Rate = 0` | |
| `Beam` (between two Attachments) | lasers, light shafts, ropes, tracers, electricity | `Width0/1`, `CurveSize0/1`, `Texture`, `TextureMode`, `TextureSpeed`, `LightEmission`, `FaceCamera`, `Segments` |
| `Trail` (two attachments on a moving part) | sword swings, bullet streaks, tire marks | `Lifetime`, `MinLength`, `WidthScale`, `FaceCamera` |
| `Decal` / `Texture` | blood splats, bullet holes, grime | each adds draw cost; pool/limit count |
| `Highlight` | outlines / x-ray feedback | ≤ <!-- fact-value: highlight-slots -->255<!-- /fact-value --> slots per client; disabled highlights still consume slots | <!-- fact-refs: highlight-slots -->
| `Fire`/`Smoke`/`Sparkles`/`Explosion` | legacy quick effects | prefer ParticleEmitter for control; `Explosion` also applies physics/kills unless `DestroyJointRadiusPercent = 0` / `BlastPressure = 0` |

## Look-dev rules
- Lit smoke/dust: `LightInfluence` 0.5–1, `LightEmission` 0 — reacts to scene lights (volumetric feel in flashlight
  beams). Fire/sparks/magic: `LightEmission` 0.5–1 (additive), `LightInfluence` 0, plus a small `PointLight`.
- Soft particles: large, low-opacity, slow, long-lived sprites beat many small opaque ones.
- Dust in light shafts: sparse, slow, small, only inside the light volume (emitter part sized to the beam).
- Fade in/out via `Transparency` sequence (start and end at 1) to avoid popping; grow `Size` over life.
- Flipbooks (1024² sheet, 2×2/4×4/8×8) for animated smoke/fire; `FlipbookStartRandom` for variety.
- Rain: particles following the camera (emitter in a part above the camera, client-side), plus puddle ripples near
  the player; wet materials (lower roughness) and darker albedo sell rain more than particle count.

## Replication and ownership
Create cosmetic effects on **clients** (server sends event + position). Server-created emitters replicate to all and
count against network/instance budgets. Property changes on emitters every frame are expensive (per docs) — set once
or at low rate.

## Budgets
- Fill-rate (overdraw) dominates: big, close, overlapping transparent particles on mobile are the worst case.
- Cap concurrent emitters and total particles per effect category; LOD by distance (disable emitters beyond ~100
  studs, reduce `Rate` with quality tier).
- Pool one-shot effect instances (reset `Enabled`, `Emit`) instead of cloning new ones per shot.
- Keep counts in the low hundreds of visible particles on low tier, low thousands on high (measure).

Sources: cd:effects/particle-emitters, cd:effects/beams, cd:effects/trails, cd:effects/highlighting,
cd:reference/engine/classes/ParticleEmitter, cd:reference/engine/classes/Beam, cd:reference/engine/classes/Trail,
cd:reference/engine/classes/Explosion, cd:performance-optimization/improve.
