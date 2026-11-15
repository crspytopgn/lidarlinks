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

| `surfaces/surfaces.json` + `surfaces/<slot>_albedo/normal/roughness.jpg` | the flat colours of cart paths, bridge decks and sides (designed, real and built-in courses) and the tee bench | `tools/megascans/build_surfaces.py PACK_DIR SLOT=SOURCE_DIR[@SIZE_M] ...` |

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

## Dry-stone walls

`StoneWalls` (game/scripts/graphics/stone_walls.gd) draws a course's field
walls. A course built from a map gets them from OpenStreetMap's
barrier=wall, dry_stone_wall and stone_wall, stored as
`DesignedCourse.walls`. Each wall is about 1.2 m high, battered from
0.7 m to 0.4 m, with coping stones set on edge. stone_wall.gdshader lays
ragged courses of grey stone on the faces. This is in the public build as
well. With the pack, each stone shows a patch of a scanned rock.
## Scanned surfaces

`ScannedSurfaces` reads `surfaces/surfaces.json`: one scan per slot with its
real size in metres. `path` is the cart path (DesignedTerrain paths on
designed, imported and built-in courses), `deck` and `timber` a bridge's
deck and boarded sides (the boards run along the image's x: across the
deck, along the sides), `bench` the tee bench's slats, projected from three
sides in the bench's own space and darkened by its baked shade. Without the
pack each keeps its flat colour.

A slot can also have regional versions, `path@us` and so on (regions uk,
europe, us, desert, tropical, south; boxes in `ScannedSurfaces.REGION_BOXES`),
picked from where the course is in the world with the birdsong's place data
(`FreeAmbience.location_of`, `KNOWN_PLACES`, a map course's own location) and
desert courses wherever they are. The baked pack uses Megascans Asphalt
(eb97ec51) everywhere but concrete cart paths (Concrete Road 145a28e5) in the
US, the desert and the tropics, as American resort courses mostly have;
bridges are weathered grey boards (Planks023A) by default, brown treated
boards (Planks011) in the US and dark hardwood (Planks037A) in the tropics.
`OL_SURFACE_REGION=us` forces a region, to look at its scans.

A bridge's sides are built as real cart bridges are, in every build: a
0.3 m fascia board along each deck edge, a kerb rail, posts every 2 m and a
top and middle rail at 1.07 m (42 in) and 0.55 m
(`DesignedTerrain._add_railings`), in the `timber` scan or the flat brown.

The download's 881 "surfaces" are ground: asphalt, roads, soil, gravel and
sand. It has no planks, timber, brick, cobbles or stone walls (the only
wood is two oak end-grain scans and indoor parquet), so the wood slots are
baked from CC0 ambientCG scans instead: Planks023A (weathered deck boards,
0.85 m, six boards) for `deck` and `timber`, Wood060 (0.5 m) for `bench`.
The cart path uses the Megascans asphalt chosen by eye from close-ups (see
the project's scanned-surfaces images). For example:

```bash
M=MEGASCANS/surfaces/material
python3 tools/megascans/build_surfaces.py PACK path=$M/Asphalt_eb97ec51 \
    path@us=$M/Concrete_Road_145a28e5 path@desert=$M/Concrete_Road_145a28e5 path@tropical=$M/Concrete_Road_145a28e5 \
    deck=Planks023A@0.85 timber=Planks023A@0.85 deck@us=Planks011@2.24 timber@us=Planks011@2.24 \
    deck@tropical=Planks037A@2.2 timber@tropical=Planks037A@2.2 bench=Wood060@0.5
```

Megascans and ambientCG normal maps are both OpenGL style (green up), as
Godot wants; Megascans' sizes come from each scan's JSON.

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
