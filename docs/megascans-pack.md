# Megascans pack (private)

Quixel Megascans became free on Fab in November 2026. Its licence lets the
scans be used in a game but not passed on as files, so nothing from it is
in this repository or the web build. Each player who has the scans can bake
a private pack, and the desktop game reads it from `user://megascans/`
(on a Mac, `~/Library/Application Support/Godot/app_userdata/OpenLinks2003/megascans/`),
or from the folder named by the `OL_MEGASCANS` environment variable.

| Pack file | Replaces | Made by |
|---|---|---|
| `foliage/fescue.png` | the drawn fescue tuft atlas (FescueField) | `tools/megascans/fescue_from_scans.py MEGASCANS_DIR OUT.png` |

`fescue_from_scans.py` cuts single photographed blades out of the
Megascans grass atlases (Dune Onion Weed, Canary Grass, Dry Grass, Wild
Grass) and builds four 1 m tufts from them, in the same 2 x 2 layout as
`tools/grass/fescue_atlas.py`. Needs numpy, scipy and Pillow.

`tools/megascans/billboard_cards.py OUT.png MODEL_DIR...` makes the same
2 x 2 card layout from the whole-plant views in a Megascans 3D plant's
`*_Billboard_BaseColor/Opacity` textures. These look far more real than
cut blades, so use it for new plant cards (made so far, in
`megascans_pack/foliage/cards/` on the Mac: fescue from Wild Grass and Xeric
Grass, marram, reeds, thatching grass, lady fern, field poppy, and a shrub
card from Dwarf Birch and Downy Willow). Megascans has no full trees,
gorse or heather.

`tools/megascans/build_pack.py MEGASCANS_DIR PACK_DIR` does this for every 3D
plant in the download's `catalogue.json` that has billboards: it bakes
`foliage/cards/<uid8>.png` and writes `foliage/cards.json`, one entry per
card with its kind (grass, fern, flower, rush, reed, shrub), full height in
metres and golf roles (links_fescue, deep_rough, dune, water_edge, heath,
scrub, meadow, woodland_edge), from rules on the plant's name. The game
reads the list through `MegascansCards` (`cards()`, `for_kind()`,
`for_role()`, `for_cover()`, `atlas()`), which is empty without a pack.

The real-course importer records what grows on OpenStreetMap
`natural=heath`, `scrub`, `wetland`, `dune` and `grassland` areas as the
shape's cover (all played as deep rough). `CourseTerrain.cover_at(x, z)`
returns it, so the foliage dresser can put heath plants on heath, reeds on
wetland and marram on dunes (`MegascansCards.for_cover()`).

## Woodland floor (debris)

`tools/megascans/debris_pack.py MEGASCANS_DIR PACK_DIR` and then
`godot --headless --path game -s tools/megascans/debris_meshes.gd -- PACK_DIR`
bake the ground under tree lines into `PACK_DIR/debris/`:

- `litter_leaves.png` and `litter_needles.png` (with `_n.jpg` normal maps):
  2 x 2 atlases of 2.5 m litter patches cut from the Dry Fallen Leaves,
  Fallen Leaves, Fallen Oak Leaves, Pine Forest Floor and Fallen Pine
  Needles scans. Each patch has a ragged edge that follows the scan's
  displacement, so the top leaves reach out furthest and the turf shows
  through in gaps.
- `<uid8>_<n>.olmesh` plus albedo (AO multiplied in, opacity as alpha)
  and normal map per scanned prop: the Dead Leaves piles, Fallen Pine
  Branches, Pine Wood Debris, Small Pine Cones (laid out as a little
  scatter), dead oak and pine branches, seven logs and eight stumps (the
  `PROPS` table names them). The Godot step reads the scans' FBX meshes
  and cuts them to 200 to 4,000 triangles with Godot's own simplifier,
  which keeps UV seams. Stumps are scaled down to 0.9 m tall at most and
  logs to 0.7 m.
- `debris.json` lists them, with each prop's kind and the trees it lies
  under (conifer, broadleaf or any).

`DebrisField` (read through `MegascansDebris`) puts them under every tree
crown on the rough and deep rough, never on the fairway, green, tee, sand
or water. Needles carpet the ground under conifers and leaves lie under
broadleaf trees; course trees say which they are
(`ObstacleField.mark_conifer`). Low grass draws the litter to 70 m, Medium
adds the logs and stumps to 110 m, and High adds small pieces near the
camera to 45 m. Each course uses only two or three types of each kind, so
draw calls stay low. How much falls follows the course's kind of place
(`FreeAmbience.setting_for_place`, from its real location when known): a
parkland is kept tidy, a wood gets the most, a links less, and a desert
little. Desert and warm courses get no mossy scans. All of it is visual
only: the ball never meets a log.

Tried and not used: Megascans turf, sand, path and dirt surfaces in place of
the free ground set. Up close on a tee, the lawn scans looked mottled and
clumpy, even with their low frequencies flattened and their colour matched,
and from further back they looked no different.
