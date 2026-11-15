# Epic courses

Built-in courses set somewhere dramatic: vast real scenery, each with its own
ground, plants and rock, and Links 2003's physics and difficulty unchanged.
They are original designs on real landforms; none is, or copies, a real golf
course. They show in the course list after Kettle Hollow as "(built in)".

| Course | Biome | Where the ground comes from | Status |
|---|---|---|---|
| Red Spire | desert | Castle Valley, Utah (38.64 N, 109.39 W): a red-rock valley floor between 400 m sandstone walls | Playable |
| (snow) | snow | an alpine valley | Planned |
| (volcanic coast) | tropical | a Hawaiian lava coast | Planned |

## How they are built

`python3 tools/homecourse/build_epic_course.py red_spire --preview /tmp/rs.png`
writes `game/assets/courses/red_spire.olc`. It reuses the Kettle Hollow builder
(`build_home_course.py`, see [home-course.md](home-course.md)) for the holes
themselves (tees, fairways, rough, contoured greens, bunkers, ponds, mounding,
pins), so every course follows the same real design figures. Per course it sets
the location, the routing, the biome and what stands between the holes. Ground:
Terrarium elevation tiles (USGS 3DEP in the US, public domain).

Two new fields in the course file (`DesignedCourse`):

- `biome`: `"desert"`, `"snow"` or `"tropical"` (`Biome`). It sets the colour of
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
cacti slow the ball like a canopy or bush.

Nothing is placed on a tee, fairway, green, fringe or bunker (checked by
`designer_tests.gd`), and plants keep 14 to 22 m off each line of play.

## Red Spire's routing

Par 36, 3,418 yards, on the valley floor rising gently toward the rock band:
1 plays uphill to a green with a spire beyond it; 2 is a par 5 bending round a
hoodoo garden; 3 a par 3 into the foot of twin towers; 4 back down the valley
past a butte; 5 short and downhill; 6 the long par 5 across the open desert; 7 a
par 3 over an oasis pool to a green framed by the arch; 8 doglegs home past a
mesa; 9 climbs back to the clubhouse past a tower.
