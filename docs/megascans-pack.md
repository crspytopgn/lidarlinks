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

## 3D plants round the tees and greens

`tools/megascans/plant_meshes.py MEGASCANS_DIR PACK_DIR` bakes the real
scanned meshes of the download's 3D plants (ferns, wild grasses,
wildflowers, reeds; logs, ivy, dead and tropical plants left out) into
`foliage/plants/<uid8>.olplant`, with `<uid8>_albedo.png` (opacity in alpha)
and `<uid8>_normal.png` (translucency in alpha) at 2048, and lists them in
`foliage/plants.json`. Each plant keeps up to four variants, each with a
near mesh (the most detailed Megascans LOD under 2,600 triangles) and a mid
mesh (the next one down); the flat billboard LODs are dropped, since the
plant cards take over further off. `tools/megascans/fbx_mesh.py` is the
small binary FBX reader it uses (numpy only). The format is described at
the top of `plant_meshes.py`.

The game reads them through `MegascansPlants` and grows them with
`ScannedPlants`: beds on the long grass round the hole's tee boxes (30 m)
and green (34 m), on the deep rough anywhere and on the plain rough only
well off the line of play, never within 1.4 m of a mown or sandy surface.
What grows follows the course's place, as the ambience hears it
(`FreeAmbience.setting_for_place`): meadow grasses, ferns and wildflowers
on parkland, mostly ferns in woodland, marram and xeric grass on a links,
dry grasses and rushes in the desert (the download has no cacti or
succulents), fewer ferns where it is warm; ferns under tree crowns and
reeds by water wherever those grow. Near the camera each plant is its
near mesh, then the mid mesh, which dissolves into the plant cards
(`shaders/scanned_plant.gdshader`, the trees' dithered cross-fade). Off at
Low grass and on the web; Medium grows fewer plants and hands over sooner.
