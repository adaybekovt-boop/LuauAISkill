# Environment art: scale, modular kits, composition, liminal & horror spaces

Read when: building maps, interiors, liminal/Backrooms/horror environments, making a place look intentional.
Related: [lighting](01-lighting.md), [materials](04-materials-pbr.md), [procedural](../roblox/12-procedural-generation.md),
scene recipes in [recipes/graphics](../../recipes/graphics/).

## Scale: design around the character, not the metre
Default R15 avatars are ~5 studs tall (varies with avatar scaling); the physics conversion is 1 stud = 0.28 m, which
would make avatars ~1.4 m — so **build to the avatar**, not to metres. Rules of thumb that read "real" with default
avatars (verify with your rig and camera):
| Element | Studs | Notes |
|---|---|---|
| Door opening | 4–5 wide × 8–9 tall | official environment-art sample keeps doorways/hallways ≥ 10 studs wide for third-person camera clearance |
| Corridor | 8–12 wide (first person: 6–8 feels tight/claustrophobic) | wider for third-person cameras and combat |
| Room ceiling | 10–14 | offices ~11–12; lower (8–9) = oppressive; halls/warehouses 20–40 |
| Stair step | rise 0.8–1, run 1.5–2 | Humanoid climbs ≤ ~2 stud steps; use invisible ramps for smooth movement |
| Railing / counter / table height | 3–3.5 / 3.5 / 2.5–3 | |
| Chair seat | ~1.8–2 | |
| Window sill | 2.5–3 | |
| Wall thickness | 0.5–1 (interior), 1–2 (exterior) | thin walls leak light and break shadows |
Choose one **modular grid** for the whole project (official Beyond the Dark sample: 16-stud grid; the environment-art
course uses 5-stud snapping). Every kit piece's pivot sits on the grid (corner or edge), so pieces snap without gaps.

## Modular kit essentials
- Pieces: wall straight (full/half), wall with door, wall with window, corner (inner/outer), floor tile, ceiling
  tile with fixture socket, column, trim/skirting, stairs, railings. Same height/thickness everywhere.
- Hide seams with trims (skirting, crown moulding, pillars) — they also add realism.
- Reuse identical meshes (same MeshId) → draw-call instancing; vary with material tint/decals, not new meshes.
- Keep collision simple (boxes) and separate from visual detail.

## Composition and navigation
- **Sightlines**: frame destinations; a door at the end of a corridor pulls the player. Break long straight lines
  with turns to hide pop-in and create anticipation.
- **Landmarks**: unique shapes/colours/lights visible from afar let players orient (a red exit sign, a broken
  column, a big window).
- **Light leads**: brighter areas attract; darker areas repel (or tempt in horror). Place key lights on the path.
- **Value structure**: design the scene in grey first: dark/medium/light masses. A good scene reads in greyscale.
- **Silhouettes**: readable shapes against the background; avoid noise everywhere.
- **Rule of three detail levels**: large forms (architecture), medium (furniture, machinery), small (clutter, decals).
  Spend detail where the player looks (eye level, near paths, interaction points).

## Clutter and storytelling
Clutter tells what happened: overturned chair + scattered papers + flickering light = something passed through. Use
clusters (groups of props that make sense together) not uniform scattering. Wear follows use: dirt at floor edges and
corners, scuffs near door handles, stains under pipes/leaks, grime in low-traffic corners, clean paths where people walk.
Decals for dirt/leaks/cracks at controlled density; don't cover every surface.

## Breaking repetition (essential for procedural and large spaces)
Vary: prop placement, damaged/missing tiles, a flickering or dead light every N fixtures, occasional unique rooms,
colour variation ±5–10 % value on repeated surfaces, different decal sets, rotations of floor tiles, water damage
patches. Keep the underlying grid consistent so variation reads as "wear", not chaos.

## Liminal spaces (Backrooms, poolrooms, empty offices, malls at night)
What makes them work:
- **Familiar but wrong**: ordinary architecture (office carpet, drop ceilings, tiled pools) with no people, no
  purpose, impossible layouts, too many repetitions.
- **Uniform artificial light**: flat fluorescent grid (Backrooms level 0: yellow-beige walls ~(200,180,110), damp
  carpet ~(150,130,80), ceiling tiles off-white, lights cool-white/slightly green), humming. Or bright diffuse
  white-blue (poolrooms: white tiles, turquoise water, soft even light).
- **Low contrast, low saturation, slight haze**; Atmosphere density for distance fade; exposure a bit high.
- **Emptiness and scale**: long views that fade into haze; doorways to nowhere; ceilings slightly too low or too high.
- **Sound**: constant hum/buzz, distant muffled noises, your own footsteps too loud.
- **Camera**: first person, slightly wide FOV; subtle handheld/VHS artefacts optional ([camera aesthetics](../../recipes/graphics/camera-aesthetics.md)).

## Horror environments
- **Darkness with purpose**: pools of light separated by darkness; the player's flashlight is the main light.
- **Occlusion and anticipation**: corners, half-open doors, long corridors with a turn at the end.
- **Contrast of safe vs unsafe**: warm light = safe rooms; cold/red/flickering = danger.
- **Readable threats**: never so dark that the player can't navigate; use rim lights and fog colour to silhouette.
- **Environmental narrative** over jump scares: blood trails, barricades, notes, moved furniture between visits.
- **Performance**: horror maps are often dense interiors — room culling, few shadowed lights, streaming.

## Realistic interiors checklist
- [ ] Consistent scale and grid; no floating or intersecting props (check corners, z-fighting on coplanar faces →
      offset by 0.01–0.05 studs or merge).
- [ ] Materials with real albedo/roughness; no SmoothPlastic default look.
- [ ] Every light motivated; ambient low; few shadow casters.
- [ ] Wear and clutter justified by story; clean vs dirty zones.
- [ ] Walls thick enough to block light; ceilings present (no sky leaks).
- [ ] Reads well on low graphics (no shadows): contrast from materials and light colour, not only from shadows.

Sources: cd:resources/beyond-the-dark/building-architecture, cd:tutorials/curriculums/environmental-art/greybox-your-environment,
cd:tutorials/curriculums/environmental-art/develop-polished-assets, cd:tutorials/curriculums/environmental-art/optimize-your-experience,
cd:physics/units, cd:parts/materials, cd:performance-optimization/improve.
