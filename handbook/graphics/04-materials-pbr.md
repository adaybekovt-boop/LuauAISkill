# Materials and PBR: Material, MaterialVariant, SurfaceAppearance, textures

## TL;DR
- Choose built-in materials, material variants, or surface appearance deliberately.
- Keep PBR maps in the expected workflow.
- Match texel density across adjacent assets.
- Break tiling without hiding poor material scale.
- Evaluate transparency and material cost on target hardware.

Read when: surfaces look plastic/toy-like, choosing textures, realistic environments, memory budgets.
Related: [lighting](01-lighting.md), [environment art](05-environment-art.md).

## Three layers of surface appearance
| Layer | What | Best for | Runtime scripting |
|---|---|---|---|
| `BasePart.Material` (`Enum.Material`: Concrete, Brick, Metal, DiamondPlate, Wood, WoodPlanks, Fabric, Slate, Plastic, SmoothPlastic, Neon, Glass, ...) + `Color` | built-in tileable PBR materials | blockout, generic surfaces | writable |
| `MaterialVariant` in `MaterialService` (custom tileable PBR) | ColorMap/NormalMap/RoughnessMap/MetalnessMap (+emissive), `StudsPerTile` [<!-- fact-value: material-variant-studs-per-tile-default -->10<!-- /fact-value -->], `MaterialPattern` (`Regular` / `Organic` = less visible tiling), `BaseMaterial` (physics), `AlphaMode` | reusable walls, floors, terrain overrides; "adaptive materials" (parts reference the variant **by name** via `BasePart.MaterialVariant`) | swap `part.MaterialVariant = "Name"` (the scriptable property is tagged NotReplicated with a hidden serialized twin — verify runtime changes replicate in a 2-client test, or set it on each client); create variants at edit time | <!-- fact-examples: {"values": ["2"], "reason": "Illustrative aesthetic/test/code values; not additional platform limits."} -->
| `SurfaceAppearance` under a `MeshPart` | unique UV-mapped PBR: ColorMap, NormalMap, RoughnessMap, MetalnessMap, `EmissiveMaskContent` + `EmissiveStrength`/`EmissiveTint`, `AlphaMode` (`Overlay` default, `Transparency`, `TintMask`, `Opaque`), `Color` tint | hero props, characters, unique meshes | **maps are PluginSecurity — not readable/swappable by game scripts**; `Color`, `EmissiveStrength`, `EmissiveTint` are writable |
Material overrides in `MaterialService` replace a base material globally (the only way to customize **terrain**
materials; `TerrainDetail` for top/side/bottom).

## PBR rules (metalness workflow, OpenGL tangent-space normals)
- **Albedo/Color**: no baked lighting/AO shadows (small cavity AO is OK); realistic albedo ranges: charcoal ~(50),
  concrete ~(120–150), fresh snow ~(230); avoid pure black/white.
- **Roughness**: most real surfaces 0.5–0.95; polished floors/wet surfaces 0.1–0.3; vary it with a map — uniform
  roughness is the plastic giveaway.
- **Metalness**: 0 or 1 (binary); partial only for dirt over metal. Rusted metal = metal 1 with rust areas 0.
- **Normal maps**: OpenGL format ([127,127,255] = flat). DirectX maps (green inverted) light "from below" — flip G.
- **Emissive**: for screens, signs, fixture diffusers; drive bloom via emissive strength rather than Neon cubes where
  possible. Emissive surfaces don't light the scene — pair with a real Light if needed.
- Test materials under multiple lighting setups (don't tune to one room).

## Texel density and resolution (official guidance)
- Max texture 4096² (SurfaceAppearance/MaterialVariant maps); built-in materials ≈ 1024² per 8×8-stud face.
- Guideline: 256² per ~2×2×2-stud object size step (5×5-stud object → 256², 10×10 → 512², 20×20 → 1024²).
- Keep texel density **consistent** across a scene — a 4K crate next to a 512² wall looks wrong.
- GPU memory ∝ pixels (1024² = 4× 512²); engine streams lower mips first. Upload each texture once; reuse via tint
  (`SurfaceAppearance.Color`) and trim sheets.

## Tiling and repetition breaking
- `MaterialPattern.Organic` on natural materials; `StudsPerTile` matched to real scale (brick courses ~0.25 studs
  high ⇒ a brick texture covering 8 bricks ≈ 2 studs tall; concrete panels 4–8 studs).
- Break repetition: decals (dirt, leaks, stains) at low density, vertex-colour-like variation via part `Color`
  variation (±5 % value), different variant per wall section, trims/skirting/pipes covering seams, damage props.
- `Texture` (tiling image on a part face, `StudsPerTileU/V`, `OffsetStudsU/V`) and `Decal` (stretched image) are
  cheap overlays but each is an extra draw — use purposefully.

## Mesh materials pipeline
Model in Blender with real-world scale (1 stud = 0.28 m) → UV unwrap (no overlaps for unique maps, consistent
density) → bake/paint PBR maps (Substance/Blender) → export FBX/glTF → Studio 3D Importer → add SurfaceAppearance →
check normals orientation, pivot, collision fidelity (Box/Hull for props). Reuse the same MeshId for duplicates (draw
call instancing).

## Glass, water, transparency
- `Glass` material + `Transparency` 0.3–0.7 renders refraction-like distortion in Realistic; heavy use = overdraw.
- For foliage/fences use `AlphaMode.Transparency` with `MeshPart.Transparency = 0` for crisp cutouts (depth-correct);
  ≥ 0.02 for smooth semi-transparency (dirty windows).
- Avoid stacking transparent layers (smoke + glass + fog cards).

## Common "cheap look" material mistakes
SmoothPlastic everywhere; saturated primary colours; Neon used as paint; identical texture scale on floor/walls/
ceiling; no roughness variation; metal without environment specular; floors spotless in "abandoned" spaces; every
surface high-frequency noisy (visual clutter) — balance noisy and calm surfaces.

Sources: cd:parts/materials, cd:art/modeling/surface-appearance, cd:art/modeling/texture-specifications,
cd:art/modeling/material-reference, cd:parts/textures-decals, cd:parts/meshes, cd:reference/engine/classes/SurfaceAppearance,
cd:reference/engine/classes/MaterialVariant, cd:reference/engine/classes/MaterialService, cd:studio/material-generator,
cd:performance-optimization/improve.
