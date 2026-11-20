# Free pack (public, CC0)

The private Megascans pack (docs/megascans-pack.md) gives the desktop game
scanned rocks, real 3D plants round the tees and greens, woodland debris and
scanned surfaces, but only for players who have the scans. The free pack
gives every desktop build the same things from CC0 scans (Poly Haven and
ambientCG), in the same layout and read by the same code. Wherever the
private pack has a part (its manifest), that part wins; otherwise the game
reads the free one (`FreeAssets.pack_dir`, `pack_dirs`). `OL_FREE_PACK=0`
turns it off, to compare before and after.

It is not in the web export (its download budget), and desktop games in
Compatibility don't read it either: that renderer keeps textures
uncompressed, so the pack would add about 100 MB of video memory (472 to
572 MB in the render check, over the 512 MB budget of the low-end tier).
Both keep their plain look there, as they always have without the private
pack. Forward+ desktops get it.

| Part | Manifest | What's in it |
|---|---|---|
| Rocks (RockField, StoneWalls) | `rocks/rocks.json` | boulders and outcrops by kind: upland (boulder_01, rock_face_02), woodland (the mossy rock sets, four rocks each), sandstone and scatter (the Namaqualand boulders), dry outcrops (rock_face_01, namaqualand_cliff_01), shore (coast_rocks_05, sand_rocks_small_01) and a shore outcrop (coast_land_rocks_02) |
| 3D plants (ScannedPlants) | `foliage/plants.json` | fern, wild and Bermuda grass, dandelion, nettle, celandine, wood sorrel, and for the desert two succulents and a gazania (the `dry` group) |
| Woodland floor (DebrisField) | `debris/debris.json` | two stumps, two logs, dry pine branches, bark debris, and the leaf and pine-needle litter atlases |
| Surfaces (ScannedSurfaces) | `surfaces/surfaces.json` | asphalt cart paths (concrete in the US, desert and tropics), weathered deck boards (Planks023A; Planks011 in the US, Planks037A in the tropics), the bench's Wood060 |

There are no free plant cards (`foliage/cards.json`) yet: FescueField keeps
its drawn atlases.

## How it is made

`python3 tools/free_pack/free_pack.py bake --godot GODOT` downloads the
models' glTF and cuts their meshes down with Godot's own simplifier
(`tools/free_pack/bake_meshes.gd`) into `tools/free_pack/baked/`: rocks as
`.res` ArrayMeshes with LODs (about 3,000 triangles at the top), plants as
`.olplant` (up to four variants, a near level of about 2,400 triangles and
a mid one of 700), debris as `.olmesh`, and the four manifests. These are
committed. Pebbles under half a metre are left out. Change the tables at
the top of free_pack.py and bake again to change what's in the pack.

`tools/fetch_free_assets.py` then calls `free_pack.fetch()`, which copies
`baked/` to `game/free_assets/pack/` and downloads the textures the
manifests name: colour at 1024 px, normal maps at 512 and roughness at 256,
all WebP (alpha kept for leaves). Plants get their opacity map as alpha,
debris its ambient occlusion multiplied in, and the litter atlases are cut
from Poly Haven's leaf and needle scans by the Megascans baker's own
`litter_cell`. Each file gets an `importer="keep"` .import so it's
exported as it is and the game reads it as it reads the private pack.
About 15 MB.

## Ground finishes (every build, web too)

What bare ground looks like where it isn't turf, from rules that hold for
every course built from shapes (designed, built-in and real courses), never
per course. DesignedTerrain paints a finish per 0.5 m raster cell
(`Finish`, `_paint_finishes`, `finish_at`) and hands it to the terrain
shader in the high four bits of the splat codes:

- **Beach sand** on sand shapes mapped as beaches, dunes and desert waste
  (CourseShape cover `beach`), not on bunkers.
- **Pine straw** under every conifer's crown, where the ground is unmown.
- **Mud** in a 1.2 m band along every pond, creek and shore, where the
  bank is unmown.
- **Bare rock** on unmown banks steeper than about 52 degrees (from the
  ground's slope in the shader, so no raster cell).
- **Desert hardpan**: the bare ground of desert courses takes the scan's
  crust and grit under its own colour.

The shader shows a finish only where the surface allows (beach only on
sand, the rest never on mown turf), with a ragged edge, and the grass
blades and fescue leave those cells bare. The scans (Poly Haven, CC0):
dense_sand, forrest_ground_03, mud_forest, dry_ground_01, and the cliff
slot's cliff_side for rock, fetched as `finish_*` slots at 1k (normals 512)
and packed into one texture array (`FreeAssets.finish_array`: one sampler,
as Compatibility has few), 1024 per layer on Forward+ and 512 in
Compatibility.
