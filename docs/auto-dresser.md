# Auto-dresser

The auto-dresser dresses a course the way a course artist would, using the
course's own data. It covers every built-in, designed and real (lidar)
course with no hand placement. It is visual only: physics never reads it.

## Today (PR #275)

`FescueField` holds three rules:

- **Native drifts:** golden long grass on the deep rough, in broad patches
  that favour banks. `terrain.gdshader` tints the ground under each drift
  straw, using the same noise, so the field and its tufts agree.
- **Reeds:** tall tufts on the bank within 2.5 m of water.
- **Understory:** taller, shaded brush under and around tree crowns.

## The plan

### 1. A tagged plant catalogue

Each plant in the private Megascans pack (and each free stand-in we ship)
gets a record:

| tag | values |
|---|---|
| `kind` | grass, reed, fern, heather, shrub, flower, litter |
| `look` | tight, wispy, leafy, seeded, rough |
| `moisture` | wet, damp, dry |
| `colour` | green, olive, straw, russet, mixed |
| `height_m` | min, max |
| `light` | sun, part, shade |
| `season` | spring, summer, autumn, winter (when it looks its best) |
| `density` | clumps per m² that close into a bank |
| `atlas` | card atlas path in the pack (from the importer) |

The "Grab Megascans" thread tags each plant once, by eye with AI help, and
writes the result as one JSON file next to the pack.

### 2. What the dresser knows about each spot

All of this comes from data we already have:

- **Surface** from the splat map: deep rough, rough, the edges of each cut.
- **Lidar:** slope, curvature (mound or hollow), height above the nearest
  water, and the flow line, which marks where the ground is wet.
- **Shade:** tree crowns from `ObstacleField.canopies()` and the baked
  `GroundShade`.
- **Play:** distance from the line of play (tees, landing areas, green),
  so play areas stay tidy.
- **Land cover** (new): classes from the aerial photo the real-course
  builder already fetches (grass, scrub, heath, wetland, bare), plus
  OpenStreetMap `natural=*` and `landuse=*` areas where they exist.

### 3. Rules: score, then pick

For each spot, every catalogue plant gets a score from rules such as
"dry and seeded on south-facing banks", "wet on flow lines and pond
edges", "shade plants under crowns" and "tight near play, wispy further
out". Where the land cover names a class, it wins. The dresser picks the
plant with the highest score, plus a little noise so stands mix at their
edges, the way real plants do. Everything is deterministic per course.

### 4. Where it runs

- **Real courses** (`realcourse/real_course_builder.gd`): the builder
  bakes a small "dress map" with the plant index and density per 1 m
  texel next to the splat map. The terrain shader reads it for the ground
  tint, and the dresser fields read it for placement.
- **Designed and built-in courses:** the same rules run on their splat
  map and heights when the course loads.
- **The course designer:** paint over the result to change a zone's plant.

### 5. Budgets

Each tier keeps its plant count and VRAM budget (CI `render_check`). Far
off, each stand turns into the ground tint alone. Without the private pack,
the free cards stand in, so the public build keeps working.
