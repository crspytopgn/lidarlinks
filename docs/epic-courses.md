# Epic courses

Built-in courses set somewhere dramatic: vast real scenery, each with its own
ground, plants and rock, and Links 2003's physics and difficulty unchanged.
Most are original designs on real landforms. One, Vermilion Ridge, plays a
real course's hole layout as mapped on OpenStreetMap, under our own name and
with our own scenery (see below). They show in the course list after Kettle
Hollow as "(built in)".

| Course | Biome | Where the ground comes from | Status |
|---|---|---|---|
| Red Spire | desert | Castle Valley, Utah (38.64 N, 109.39 W): a red-rock valley floor between 400 m sandstone walls | Playable |
| Vermilion Ridge | desert | a real 18-hole layout in the badlands near Mesquite, Nevada, from OpenStreetMap, on USGS 3DEP lidar | Playable |
| Glacier Crown | alpine | a real 18-hole Alpine layout 1,500 m up in Valais, Switzerland, from OpenStreetMap, above the Rhône valley | Playable |
| Ember Coast | tropical | a real 18-hole layout on the Kohala lava coast of Hawaii's Big Island, from OpenStreetMap, on USGS 3DEP lidar | Playable |

## How they are built

`python3 tools/homecourse/build_epic_course.py red_spire --preview /tmp/rs.png`
writes `game/assets/courses/red_spire.olc`. It reuses the Kettle Hollow builder
(`build_home_course.py`, see [home-course.md](home-course.md)) for the holes
themselves (tees, fairways, rough, contoured greens, bunkers, ponds, mounding,
pins), so every course follows the same real design figures. Per course it sets
the location, the routing, the biome and what stands between the holes. Ground:
Terrarium elevation tiles (USGS 3DEP in the US, public domain).

Two new fields in the course file (`DesignedCourse`):

- `biome`: `"desert"`, `"snow"`, `"alpine"` or `"tropical"` (`Biome`). It sets the colour of
  the semi-rough, deep rough and out of bounds, and whether that ground is bare
  (desert hardpan and snow take the sand texture under their own colour and grow
  no grass blades). Fescue becomes sparse sage scrub in the desert (30 %), and
  none through snow. Tees, fairways and greens stay green: such courses are
  irrigated.
- `landscape`: the real land round the course, 16 km square on a 40 m grid,
  heights in decimetres on the course's datum (`dm-delta-s16-deflate-base64`).
  Inside the course it follows the course's own ground and it eases into the
  real land over 160 m outside, so the two meet without a step. The game draws
  it (`Landscape`, `landscape.gdshader`) in place of the apron and FarScenery's
  rings, coloured by slope and height (bedded rock on cliffs, sand or forest or
  snow on the gentle ground), with its own clear-air haze, and cloud shadows
  drifting across it. The round camera's far plane goes out to 12 km on these
  courses. High and Ultra draw every sample; Low and Medium (phones, iPad, the
  web) every other one, a quarter of the triangles.

## Red Spire's rock and plants

The centrepiece is the sandstone, made in the game from a few numbers per
formation (`RockFormations`), no models:

- Spires (towers about 40 m high at scale 1), hoodoos (14 m columns of soft and
  hard beds under a wider cap rock), buttes (flat-topped mesas about 45 m high on
  a concave apron of rubble, with a bench part way up) and an arch (46 m span,
  framing the 7th green), plus fallen blocks round their feet.
- Each is rings stacked up a profile, the outline wandering by low-harmonic
  noise and stepping in and out bed by bed, stretched one way as joints split
  them. `rock_formation.gdshader` colours them with beds of red and buff,
  partings, dark desert varnish streaking down the steep faces and pale dust on
  ledges (`rock_strata.gdshaderinc`, shared with the distant cliffs), with the
  Poly Haven "cliff_side" scan (CC0, fetched as the `cliff` slot) for grain and
  bumps close up.
- The ball hits them as drawn: towers are stacks of cylinders following the
  same profile, the arch its two legs and the span (`RockFormations.add_obstacles`).
- With the private Megascans pack, RockField scatters scanned sandstone boulders
  round them too.

Cacti (`DesertPlants`): saguaros (6 to 11 m, 16 ribs, up to four arms), barrel
cacti and prickly pear clumps, a few variants each, drawn for the whole course
in MultiMeshes by 400 m area (saguaros to 1.4 km on High, small cacti to 220 m;
less on Low and Medium). Saguaro trunks are solid; their arms and the small
cacti slow the ball like a canopy or bush. The saguaros and barrels are
scanned models where they're there: PlantCatalog's on Sketchfab (CC BY,
`tools/sketchfab/models.json`, `cactus_saguaro_0` to `_3` and
`cactus_barrel_0` to `_3`), cut to 3,000 and 1,500 triangles without their
flowers, fine spines and fuzz, each saguaro scaled to its variant's height
and stood on its foot so the obstacles still match. The prickly pear is
still built here.

Nothing is placed on a tee, fairway, green, fringe or bunker (checked by
`designer_tests.gd`), and plants keep 14 to 22 m off each line of play.

## Red Spire's routing

Par 36, 3,418 yards, on the valley floor rising gently toward the rock band.
It plays as real desert courses do ("target golf"): the grass is islands in the
desert. Most holes start with a carry of 120 to 150 m over bare desert from the
tees to the fairway (`carry` in the hole spec), and dry washes cross some
fairways (`gaps`), so the tee shot is a choice between laying up and carrying
them. Fairway and rough edges wander more than on parkland (`wander`).

1 plays uphill over the desert to a green with a spire beyond it; 2 is a par 5
bending round a hoodoo garden, with a wash across the lay-up zone; 3 a par 3
into the foot of twin towers; 4 back down the valley past a butte, a wash
across the driving zone (lay up, or carry it 235 m); 5 short, downhill and
drivable, with a hoodoo standing on a strip of desert in the middle of the
fairway 225 m out; 6 the long par 5 across the open desert with a wash at
300 m; 7 the signature hole, a par 3 played through a natural arch 75 m from
the tee, over an oasis pool; 8 doglegs home past a mesa; 9 climbs back to the
clubhouse past a tower.

## Red Spire's mesas

Michael wanted height change. Ten-metre elevation tiles cannot make a crisp
cliff, so some tees and greens stand on sculpted mesas (`benches` in the
spec): an outline, a rise of 24 to 40 m and near-sheer walls. The builder adds
each mesa to both the ground and the 20 m blur that tee grading eases toward,
or the tees sink into pits. The outlines are saved as `cliffs` in the course
file, and `RockFormations.cliff_mesh` skins each wall in strata rock (the
ground underneath is what the ball plays). Steep bare ground everywhere is
drawn as strata rock too (`rock_slopes` in the terrain shader).

## Vermilion Ridge: a real layout, our scenery

Michael's ask: "use a real course layout but make the scenery epic yourself",
shipped publicly. `tools/homecourse/dress_real_course.py` takes a course built
by the designer's "Real course..." button (OpenStreetMap layout, USGS 3DEP
lidar ground) and keeps every tee, fairway, green, bunker, pond and the ground
exactly as mapped and measured. Only the scenery changes:

- the town goes: roads, the airfield, other courses' shapes, the aerial photo
  and garden trees (anything far from the holes);
- the ground between the holes is bare desert (one deep-rough base), with a
  rough band of 5 to 9 m round each tee, fairway and green, plus the mapped
  rough;
- sandstone formations are placed by rule: big buttes and towers out on the
  skyline (aiming about 170 to 260 m from play), smaller towers, an arch and
  hoodoos as near the holes as they fit, never within 22 m of play;
- saguaros, barrel cacti and prickly pear as on Red Spire;
- the real land for 8 km round, from the Terrain Tiles.

The club's name and marks are not used, and the credits say the course is not
connected with any club. The layout is credited to OpenStreetMap
contributors (ODbL). Rebuild:

```bash
# 1. Build the real course in the designer (or tools/realcourse_bench), then:
python3 tools/homecourse/dress_real_course.py "Real.olc" game/assets/courses/vermilion_ridge.olc --name "Vermilion Ridge" --cache /tmp/dem
```

## Glacier Crown: alpine summer

The same tool with `--biome alpine` (2026-11-17; it was `snow` at first):
the course as the real Alpine courses are played, in summer. Parkland turf,
long meadow grass and wild flowers between the holes, spruce woods in
stands on the slopes (`--pines`), the mapped trees kept as spruce, and the
Alps and the Rhône valley to the horizon, with meadow and forest on the
valley sides, grey crags and snow only above about 1,300 m over the course
(the peaks across the valley). Green turf in fields of deep snow read as
fake: nobody plays golf in snow. `--biome snow` still builds the winter
version: deep snow between the holes and snow on the trees' crowns (the
`tree_snow` shader global, set from the course's biome when a hole loads).

```bash
python3 tools/homecourse/dress_real_course.py "Real.olc" game/assets/courses/glacier_crown.olc --name "Glacier Crown" --biome alpine --cache /tmp/dem
```

## Ember Coast: tropical

`--biome tropical`: bare black lava between the holes (the deep rough and
out of bounds, with dry fountain grass in it), a mown band round each tee,
fairway and green, coconut palms in groves in the rough beside play (the
mapped trees become palms too, kept off fairways and paths), small kiawe out
on the lava, and nothing in the sea or on the shore. The sea is a plane
(`sea.gdshader`: deep ocean blue, the sky reflected toward the horizon, sun
glitter on a moving swell, hazed like the land; the pond water's shader took
the course's fog and drew the far sea as a grey wall) at sea level over the land (Landscape.sea_level: a map-built course's
heights are measured from `source.base_height`), reaching past the far
plane so the horizon is the sea's. The palm (`palm_coconut`, DesertPlants)
is a real model: four palms taken out of Next Spring's CC BY "Realistic Palm
Tree 2" pack (`palm_coconut_0` to `_3` in `tools/sketchfab/models.json`, cut
out by node with process.mjs's `keep`), scaled to `palm_height` plus the
crown so the obstacles still match. The numbers-built palm (a ringed, leaning
trunk and a crown of arching fronds) is the fallback when a model is missing.
The land beyond the course is the Kohala coast's old lava under golden
fountain grass, greening up the mountain. Bare lava and desert hardpan get
their own finish in terrain.gdshader (`bare_style`): black, rusty, rough
clinker; and hardpan with gravel patches, grit and small stones.

```bash
python3 tools/homecourse/dress_real_course.py "Real.olc" game/assets/courses/ember_coast.olc --name "Ember Coast" --biome tropical --cache /tmp/dem
```
