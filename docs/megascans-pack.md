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

Tried and not used: Megascans turf, sand, path and dirt surfaces in place of
the free ground set. Up close on a tee, the lawn scans looked mottled and
clumpy, even with their low frequencies flattened and their colour matched,
and from further back they looked no different.

## Turf detail (ground/)

`tools/megascans/turf_detail.py SCAN_DIR PACK_DIR` bakes a Megascans lawn
scan (its BaseColor and Normal, 1 x 1 m) into `ground/turf_detail.jpg` and
`ground/turf_normal.jpg`. Both are high-passed at about 3 cm, so only the
blades are left: no clumps, bare patches or light baked into the photo.
When the pack has them, `Materials.terrain()` turns on `has_scan` in
terrain.gdshader, and the mown turf (fairway, tee, collar and green) shows
the scan's blades at real size, 1.5 times finer on close-cut turf. They sit
over the course's own colour, mowing stripes and a soft metre-scale tint
from the free grass. The scan's displacement isn't used for relief. The
Uncut_Grass_a4d8af19 scan gave the evenest result (2026-11-15).
