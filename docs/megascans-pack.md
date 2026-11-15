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

## Rocks (rocks/)

`tools/megascans/rock_prep.py MEGASCANS PREP` picks 32 rock scans (beach,
sandstone, mossy forest and upland boulders, sea cliffs, one huge layered
boulder) and shrinks their maps to 2K. `tools/megascans/rock_pack.gd`
(copied into game/tests/tmp/) then bakes each into `rocks/<id>.res`, an
ArrayMesh with LODs at real size, base at y = 0. It also writes the three
textures and `rocks/rocks.json` with `{id, title, size, kind}`.

`RockField` (game/scripts/graphics/rock_field.gd) places them on each hole
when the pack has them, at Medium quality and up, outside Classic Links.
They go along pond and creek banks, and in small groups through the deep
rough and woods, never within 7 m of mown turf, sand or a green. They're
scenery only. The stone follows the course's place (FreeAmbience's setting):
- links: beach boulders and sea-cliff outcrops;
- desert: sandstone, three times as many;
- woodland and parkland: mossy, lichened boulders and grey upland stone.

`RockField.mesh(id)` and `material(id)` load one rock for other features.
