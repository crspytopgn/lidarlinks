# Real courses from open data

The course designer can build a real golf course from its name. Press
**Real course...** in the designer, type a club or course anywhere in the
world (for example "St Andrews Old Course"), pick the right match, and the
game fetches open map and elevation data, builds the course, saves it and
opens it in the designer for polishing. It works the same on desktop and in
the browser, needs no account or API key, and uses no Google data.

A course is only as complete as its map. Well-mapped courses (most famous
ones and many clubs in the UK, Europe and the US) come in with every hole,
tee, green, bunker and pond; others may have only a boundary. If OpenStreetMap
has no holes for a course, the importer says so: anyone can map them at
[openstreetmap.org](https://www.openstreetmap.org) (the golf tags are
documented at [wiki.openstreetmap.org/wiki/Tag:leisure=golf_course](https://wiki.openstreetmap.org/wiki/Tag:leisure%3Dgolf_course)),
and the next import picks them up.

## Where the data comes from

| Step | Source | Licence |
| --- | --- | --- |
| Name to place | [Nominatim](https://nominatim.openstreetmap.org) (OpenStreetMap's search) | ODbL; [usage policy](https://operations.osmfoundation.org/policies/nominatim/): at most one search a second, which a person typing never reaches |
| Holes, fairways, greens, tees, bunkers, water, woods, trees, cart paths, roads | [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API) (public servers, all asked at once, first answer wins) | OpenStreetMap, ODbL 1.0 |
| Ground heights | National lidar where a service covers the course (below), else the [Terrain Tiles on AWS Open Data](https://registry.opendata.aws/terrain-tiles/) (Mapzen "Terrarium" PNG tiles, zoom 15) | Per source, below |
| Trees | Lidar canopy height (surface model minus ground) where offered, else the aerial photo, plus OpenStreetMap's trees and woods | As the source |
| Aerial photo | National orthophoto tile services (below) | Per source, below |
| Land cover (trees the map lacks, ground colours without a photo) | [Impact Observatory / Microsoft / Esri Sentinel-2 10 m land cover](https://www.arcgis.com/home/item.html?id=cfcb7609de5f478eb7666240902d4d3d), Esri image service | CC BY 4.0 |

### Elevation by country

The terrain tiles already merge the best open elevation data per region, so
the importer gets national lidar wherever it was open when the tiles were
built, and global data elsewhere. Zoom 15 is about 4.8 m per pixel at the
equator and 2.7 m in Scotland; the course grid is 2 m.

| Where | Underlying data in the tiles |
| --- | --- |
| England | Environment Agency lidar (data.gov.uk, 2 m) |
| United States | USGS 3DEP / National Elevation Dataset (about 10 m, finer in places) |
| New Zealand | LINZ 8 m DEM |
| Norway | Kartverket DEM |
| Austria | Austrian 10 m DGM |
| Australia | Geoscience Australia DEM |
| Canada | CDEM |
| Mexico | INEGI continental relief |
| Arctic | ArcticDEM |
| Europe elsewhere | EU-DEM (25 m) |
| Everywhere else | SRTM (30 m), GMTED, ETOPO1 for the sea floor |

Courses in places covered only by SRTM or EU-DEM come out with the right
broad shape (hills, valleys, the slope of the land) but without small
humps and hollows; those are worth sculpting by hand in the designer.

### National lidar (used where it covers the course)

`NationalLidar` (`game/scripts/realcourse/national_lidar.gd`) asks these
services for the course's box in latitude and longitude, at 1 m, in
requests of at most 1000 pixels a side (Japan's comes as web map tiles).
Where the boxes overlap (near borders), each service is tried in turn and
the first that covers at least a quarter of the course is used. All of them allow requests from a
web page, so the browser build uses them too. Where a service has gaps
(under water, some buildings, past a border) the Terrain Tiles fill in,
shifted to match. Under 25% coverage, it isn't used.

Lidar services can stall on a request and drop it (in November 2026 the
Environment Agency's did on about half of them). A chunk that never came was
filled from the much coarser Terrain Tiles, so a whole square of the course
came out lumpy, with steps of up to 12 m where it met the lidar. Each lidar
request now gives up after 45 s, and failed downloads (no answer, 5xx, 408,
429) are asked for again up to four rounds, as are the Terrain Tiles, photos
and land cover. If any lidar ground is still missing, or the lidar failed
altogether, the designer's status line says so and suggests building again
later.

| Where | Service | Ground | Surface (for trees) | Licence |
| --- | --- | --- | --- | --- |
| England | Environment Agency lidar composite, WCS 2.0 | 1 m DTM | 1 m first-return DSM | Open Government Licence v3.0 |
| Netherlands | AHN via PDOK, WCS 2.0 | 0.5 m DTM | 0.5 m DSM | CC0 |
| Flanders (Belgium) | Digitaal Hoogtemodel Vlaanderen II, WCS 1.0 | 1 m DTM | 1 m DSM | Modellicentie Gratis Hergebruik |
| North Rhine-Westphalia (Germany) | Geobasis NRW, WCS 2.0 (asked for Deflate) | 1 m DGM | 1 m DOM | dl-de/zero-2-0 |
| France | IGN RGE ALTI / LiDAR HD via the Geoplateforme WMS-R (float BIL) | 1 m | LiDAR HD MNS where flown | Licence Ouverte 2.0 |
| Norway | Kartverket national lidar (NHM), WCS 1.0 | 1 m DTM | 1 m DOM | CC BY 4.0 |
| Japan | GSI elevation tiles (PNG, height in centimetres): DEM1A at zoom 17 where flown, else DEM5A (zoom 15), else DEM10B (zoom 14) | 1 to 10 m | none | GSI terms (credit) |
| United States | USGS 3DEP ImageServer exportImage | 1 to 10 m, best available | none | Public domain |
| Everywhere else, and the fallback after the ones above | Mapterhorn terrain tiles (512 px Terrarium WebP), zoom 16 then 15 only | about 1 to 2 m where a country's lidar is open: Scotland, Wales, Denmark, Sweden, Finland, Poland, Germany, Canada, New Zealand and more | none | per source, all open (CC BY 4.0, OGL, public domain and similar; mapterhorn.com/attribution) |

Mapterhorn's coarser zooms (14 and below) come from 5 to 30 m models, no
better than the Terrain Tiles, so they aren't asked for: where it has no
zoom 15 tile (Ireland, Northern Ireland, most of Australia and Italy in
Nov 2026) the course keeps the Terrain Tiles. A tile service answers 404
where it has no data; that isn't counted as a failed download. Found
through the God's Eye View project's source list (2026-11-18).

`GeoRaster` reads what they send: GeoTIFF in either byte order, float32 or
int16, uncompressed or Deflate with the floating-point predictor, in
strips or tiles, placed by ModelPixelScale and ModelTiepoint or
ModelTransformation; the raw float BIL from WMS; and GSI's colour-coded
PNG tiles, and Terrarium PNG or WebP tiles (Mapterhorn).

**Trees from lidar:** the canopy height is the surface model minus the
ground. Every local peak at least 3 m tall is a tree, its height the peak
height, one per 4 m at most; level peaks (roofs) are skipped, and so are
trees on OpenStreetMap buildings, play areas and water. A wooded course
has tens of thousands, so the ones nearest the holes are planted first, up
to 30,000 (2,500 on phones and tablets); with lidar trees, woods aren't
filled by guesswork. Until November 2026 the limit was 6000, which on a
course in a forest (West Essex, in Epping Forest) planted the trees along
the holes and left the woods beyond them as bare grass. The extra trees
stand well away from the holes, where the round draws them in batches
without sun shadows, and those more than 130 m from the hole being played
as impostors only (`DesignedCourse.FULL_TREE_REACH`): a camera near the
line of play is past the impostor distance from them anyway. Every crown
within 150 m of a hole is planted; when there are more crowns farther off
than room for them, an even share of them is planted (a little bigger),
so the woods reach the edge of the area instead of stopping in a ring round
the holes (Hilversum has 40,000 crowns). On Hilversum, 30,000 trees cost
about the same draw calls as the old 6,000 and a fifth more triangles from
the first tee, and fewer from inside the woods.

### Aerial photos

`AerialPhotos` (`game/scripts/realcourse/aerial_photos.gd`) fetches web
mercator tiles at zoom 17 (about 0.8 m a pixel; zoom 16 for big courses)
and crops them to a north-up photo of the course, at most 2048 pixels a
side, saved beside the course as `<course>.photo.jpg` (the `.olc` names it
in `source.photo`). The designer lays it over the ground (**Show the aerial
photo**), to check and trace the course against.

| Where | Service | Licence |
| --- | --- | --- |
| Flanders (Belgium) | Digitaal Vlaanderen summer orthophoto (WMS) | Modellicentie Gratis Hergebruik |
| North Rhine-Westphalia | Geobasis NRW DOP (WMS) | dl-de/zero-2-0 |
| Netherlands | PDOK Luchtfoto RGB (Beeldmateriaal Nederland) | CC BY 4.0 |
| Switzerland | swisstopo SWISSIMAGE | free reuse with credit |
| Austria | basemap.at orthophoto | CC BY 4.0 |
| France | IGN BD ORTHO via the Geoplateforme | Licence Ouverte 2.0 |
| Spain | PNOA (IGN Espana) | CC BY 4.0 |
| Japan | GSI seamless photo | GSI terms (credit) |
| United States | USDA NAIP full mosaic (0.6 m) from the USGS ImageServer, then the cached National Map basemap (zoom 16 at most) | Public domain |
| Bavaria (Germany) | Bayerische Vermessungsverwaltung DOP 40 cm (WMS) | CC BY 4.0 |
| Wallonia (Belgium) | SPW ORTHO_LAST (ArcGIS export) | open data with credit |
| Poland | GUGiK orthophoto (WMS) | open data (Prawo geodezyjne art. 40a) |
| Estonia | Maa-amet orthophoto (TMS) | open data with credit |
| New South Wales (Australia) | Spatial Services NSW Imagery | CC BY 4.0 |
| Victoria (Australia) | Vicmap Basemap aerial | CC BY 4.0 |
| Queensland (Australia) | Queensland Government latest state imagery | CC BY 4.0 |
| Czechia | CUZK orthophoto (WMS) | CC BY 4.0 |
| Portugal | DGT OrtoSat 2023 (WMS) | CC BY 4.0 |

**Satellite guide (designer only):** on a real course the designer also
offers **Show the satellite guide (Esri)**. It streams Esri World Imagery
for the course area into memory and lays it over the ground in place of
the photo, with Esri's credit shown under the course credits. It is never
saved, never used for detection or ground colours, and isn't in
`AerialPhotos.SOURCES` (it is `AerialPhotos.GUIDE`): Esri's terms allow
showing the imagery with its credit, not copying it. It is the only photo
to check English, Scottish, Welsh and Irish courses against.

WMS services are asked for each web mercator tile's box. Services answer
white or empty tiles outside their country; those don't count, and the next
service is tried when fewer than half the tiles have a photo.

**Ground colours from the photo:** with a photo, the ground takes its
colours partly from it, softened to about 6 m so crowns and cars blur out
and kept near the game's own brightness: most beyond the course (fields,
tracks, car parks), a lot in the rough (worn and dry patches), and only a
touch on fairways, tees and greens, which keep their stripes. Deep shade
and water in the photo are skipped. This works in the designer and in the
round (`DesignedTerrain`, `DesignedCourse.tint_image()`).

The photo also helps with trees. With lidar trees, the crown colour picks
pines (dark green) or broadleaves (lighter, or brown in a winter photo).
Without lidar, cells of 5 m that are mostly dark leafy pixels or deep shade,
darker than the fairways' grass, become trees.

### Land cover (everywhere)

`LandCover` (`game/scripts/realcourse/land_cover.gd`) fetches the 10 m
Sentinel-2 land cover for the course box in one request (8-bit classes:
water, trees, flooded vegetation, crops, built-up, bare, snow, clouds,
grass and scrub). It is used where the finer data is missing:

- **Trees:** without lidar or photo trees, each tree pixel outside the
  mapped woods gets a tree, nearest the holes first, at most half of the
  tree budget, and none within 25 m of a hole's line (at 10 m a tree-lined
  fairway reads as woods).
- **Ground colours:** without a photo, a picture of the classes in their
  typical colours (fields, bare ground, towns, grass, woods) is saved
  beside the course as `<course>.ground.png` (`source.ground`) and tints the
  ground the same way a photo does. It is coarse (10 m) and doesn't show in
  the designer's photo overlay.

### Not covered yet

England, Scotland, Wales and Ireland have no open aerial photo service a
web page can read (the Environment Agency's vertical photos are project
by project ECW downloads; Google, Bing, Apple and Esri imagery can't be
saved into courses under their terms). Since 2026-11-18 Mapterhorn covers
the lidar of Scotland, Wales, Denmark, Canada, New Zealand, Sweden,
Finland and Germany's other states, whose own services a web page
couldn't read. Still missing:

- Ireland and Northern Ireland: no open fine height model anywhere yet.
- Most of Australia and Italy: Mapterhorn has only 5 m or coarser there.
- Spain's 5 m model: whole metres only.

### Scorecards

Par comes from each hole's `par` tag and the stroke index from its
`handicap` tag when mappers have added them; otherwise par is guessed from
the length. Most scorecard websites forbid copying their data, so the
importer doesn't read them. Anyone can add a missing par or stroke index to
OpenStreetMap from the club's own published scorecard.

## How the map becomes a course

`RealCourseBuilder` (`game/scripts/realcourse/real_course_builder.gd`):

- **Area:** the `leisure=golf_course` outline containing the picked place
  (or the nearest one), plus 80 m of ground round it, at most 3.6 km a side.
  With no outline, the golf features within 1.5 km of the place.
- **Projection:** a local tangent plane at the course centre (`GeoFrame`):
  +z north, +x west. Latitudes and longitudes stay 64-bit floats until they
  are metres, since a `Vector2` would round them by tens of centimetres.
- **Areas:** `golf=green`, `tee`, `fairway`, `bunker` (sand), `rough`,
  `fringe`, `water_hazard` and `lateral_water_hazard`, `natural=water`
  (water), `natural=scrub` and `heath` (deep rough), `natural=grassland` and
  `landuse=meadow` (deep rough with meadow grass). Multipolygons are joined
  from their outer ways. Outlines are simplified (0.3 m for greens, tees and
  bunkers, more for big areas, at most 90 points) and clipped to the area.
  Streams, ditches and rivers become water strips cut into 60 m pieces, so
  each piece keeps its own water line on sloping ground. Culverted and
  piped ones (`tunnel`, `covered=yes`, `location=underground` or a
  negative `layer`) are left out, and with lidar ground a ditch or drain
  is only dug where the lidar shows it: lower than the ground 3 m either
  side by 12 cm or more along at least a third of it. Field drains are
  often mapped as ditches without a tag saying they're piped, and were
  cut as long straight trenches across fields.
- **Several courses at one club:** when the holes' `golf:course:name` names
  two or more courses of nine holes or more, each is built as its own
  course; the first is opened and the others saved beside it.
- **Holes:** each `golf=hole` line whose start or end lies inside the chosen
  course's outline, in `ref` order. The pin is the `golf=pin` on the green
  at the end of the line, else the green's centre; tees are the tee boxes
  along the start of the line, back to forward (up to three); the line's
  bends become aim points. A line drawn green to tee is turned round.
- **Trees:** `natural=tree` points (sized by their `height` tag),
  `natural=tree_row` lines (a tree every 7 m) and woods (`natural=wood`,
  `landuse=forest`) filled on a jittered 9 m grid, thinned to keep the
  course under the tree limit. `leaf_type` picks pines or broadleaves. No tree
  is planted on a fairway, green, tee, bunker or in water.
- **What the map lacks:** many clubs are mapped with their hole lines but
  not every green, tee, fairway or bunker. `CourseGuesser`
  (`game/scripts/realcourse/course_guesser.gd`) fills in whatever a hole is
  missing. First it looks for the real thing (`CourseDetector`,
  `course_detector.gd`):
  - **Close-ups:** where a green or its bunkers aren't mapped, the
    importer also fetches a close-up 140 m across round the green (zoom
    18, kept at 0.4 m a pixel against about 1 m for the course photo) from
    the same photo service, if that service goes finer than the course
    photo (not USGS). Greens and greenside bunkers are read from the
    close-up.
  - **Greens in the photo:** the evenly coloured grass grown out from the
    pin (its colour the median within 4 m of the pin), with the loosest
    colour match that doesn't yet leak 26 m out (into the fringe and
    fairway), 150 to 1200 m2.
  - **Bunkers in the photo:** compact patches of bright, whitish or pale
    yellow sand by the green and at the driving distance, 15 to 600 m2, at
    least 3 m wide in every direction, not on a mapped path (sandy
    tracks), and cut into grass: most of the ground 3 m round them is
    green and they are clearly brighter (0.15) than it. Dunes, heather
    and bare ground fail that. Patches are read at rising brightness
    (0.6 to 0.84), so a bunker touching pale ground or a track still
    stands alone at a brighter level.
  - **Fairways in the photo:** on a softened copy (about 2.5 m a pixel),
    cross-sections every 10 m along the line find the bands of grass of
    the line's own colour that are 15 to 60 m wide, within 50 m of the
    line. Mappers' hole lines often cut corners or cross water, so the
    fairway needn't touch the line: one band per cross-section is picked
    (or none) for the least cost of distance from the line plus sideways
    jumps (an edge may move at most 8 m between sections). The longest
    run of picked bands, bridging up to two missing ones (a cross bunker,
    a path), at least 35% of the stretch looked at, with steady widths
    (spread under a quarter of the mean), becomes the fairway. Ragged
    bands (rough, heather, some winter photos) are left to the fallback.
  - **Not lidar hollows:** bunkers as hollows in the 2 m lidar heights
    were tried and were wrong about two times in three on the benchmark
    below, worse than a marked guess, so heights aren't used for them.

  **Benchmark** (`tools/realcourse_bench/`): 21 fully mapped courses in
  the Netherlands, Germany, Switzerland, Austria, France, Spain, Japan,
  the US and England, with their greens, bunkers and fairways taken out
  and found again. On 2026-10-31, of 414 mapped greens, 340 were found
  (82%; the rest are on the 4 English courses, with no photo) and 257 of
  those overlap the mapped green by 60% or more (mean overlap 0.67, about
  what two careful mappers would agree on); 13 were wrong. Of bunkers
  found, 90% are on a mapped bunker (324 of 362), and a third of mapped
  greenside bunkers are found (small, shaded or winter-photo ones are
  missed and fall back to guesses). Fairways are found on 117 of 320 par
  4 and 5 holes (37%), and on average 69% of a found fairway lies on the
  mapped one (the rest is mostly the first cut of rough beside it).
  **To scale:** course metres come from latitude and longitude through
  WGS84's radii of curvature (`GeoFrame`, tested to 1 cm in 1 km), and a
  hole's length runs from the back tee along the line to the pin, as
  scorecards measure it. Against published scorecards (2026-10-31,
  `bench_lengths.gd`): Augusta National 7,501 yards against 7,555 (most
  holes within 2%; the 13th's new tee isn't mapped yet), Torrey Pines South
  7,751 against 7,765, and Royal Birkdale 7,161 against 7,156. Holes are
  only as long as the map's back tee: a tee moved since it was mapped
  shows up as a difference, and the designer can move it.
  Whatever isn't found is drawn at typical sizes along the line: a green
  round the pin (about 520, 600 and 650 m2 for par 3, 4 and 5, a quarter
  longer than wide), a tee box at each tee, on par 4s and 5s a fairway
  from the landing area (at most 140 m out) to the green, about 34 m wide
  and narrower at its ends, and, on holes with no bunker within 45 m of
  the line, two or three greenside bunkers and a fairway bunker at 230 m.
  Found and guessed shapes are saved with `"guessed": true` (found ones
  also `"found": true`). The designer draws them dashed (guesses in
  orange), its message says how many of each there are, and selecting one
  says where it came from, so they can be checked against the photo and
  redrawn. Moving one or its points makes it the designer's own (no
  longer marked).
- **Cart paths:** `golf=cartpath` and `golf_cart=designated` ways.
- **Buildings:** every `building=*` outline inside the area: the
  clubhouse, houses along the boundary, barns and sheds
  (`CourseBuilding`, drawn by `CourseBuildings`, solid to the ball). With
  a lidar surface model the height is the lidar's: the roof's top is the
  90th percentile of surface minus ground at points a metre apart inside
  the outline, and a roof whose points spread more than a metre from eaves
  to ridge is pitched. Otherwise `height`, `building:levels` (2.9 m a
  floor) or a typical height for the kind (a two-storey house 5.3 m to the
  eaves, 8.6 m to the ridge; a shed 3.2 m). Simple outlines (filling at
  least 78% of the rectangle round them) get a pitched roof over that
  rectangle: gabled along the long side, hipped when nearly square, on a
  bungalow, or as `roof:shape` says; complex ones and big ones are flat.
  `building.gdshader` draws brick courses, render or clapboard siding,
  windows on each floor (none on sheds and barns) and roof tiles, in the
  colours of the course's region (`ScannedSurfaces.region`): British brick
  and render under slate and clay, European render under terracotta and
  anthracite, American siding and brick under asphalt shingles (and red
  barns), stucco under clay in deserts and the tropics; shared along a
  street more often than not. The United States lidar has no surface model,
  so American buildings take typical heights (a house 4 m to the eaves,
  7.2 m to the ridge) unless the map tags them.
- **Roads:** `highway=*` ways crossing the course (not tunnels or unpaved tracks; footpaths only when paved) as tarmac paths, at their `width`, `lanes` x 3.2 m or a typical width for the road class. The ball bounces and runs on them as on the Links path surface, and they give free relief.
- **Ground:** the lidar or tile heights at every 2 m sample, bilinear. Heights below
  -12 m (the sea floor) are raised to -12 m, then the grid is stored round
  the midpoint of its range; the sea-level height of that midpoint is kept
  in the course's `source`.

The result is an ordinary designed course (`.olc`) with two extra keys:
`credits` (the attribution, shown under the course name in the designer)
and `source` (where it came from). It plays with the usual ground textures,
grass and trees of the current graphics look.

## Playable and solid on every course

Tested end to end (search, map, ground, lidar, photos, build, then every
hole played through the physics) on 18 clubs in 11 countries: West Essex,
St Andrews, Royal Portrush, Royal County Down, Hilversum, Golf National,
Crans-sur-Sierre, Pebble Beach, Banff Springs, Hirono, Kasumigaseki, Royal
Melbourne, The Australian, Leopard Creek, Emirates, and clubs mapped badly
or not at all. What that found, and what the builder now does:

- **Greens that hold a ball** (`CoursePlayability`, the in-game side of
  `tools/homecourse/playable.py`): a green steeper than a real one's
  pinnable ground (over 3 % overall, or a quarter of it over 4.5 %) is cut
  and filled to a plate falling 2 % toward its front, keeping a softened
  share of its own contours, with the ground round it eased onto it over
  14 m. Crans-sur-Sierre's greens followed the mountain at 8 to 13 % and
  Sydney's (on coarse tiles) 15 to 33 %, where no ball stopped. Tee boxes
  are levelled, and a par 3 tee further than a driver carries (220 m) is
  dropped while the hole has another.
- **Coarse ground smoothed:** without lidar the open elevation tiles (3 to
  5 m a pixel) carry speckle and steps at their tile edges, a metre or two
  high; they are smoothed over about two of their pixels (4 to 10 m).
- **Lines of play clear:** trees the lidar, photo or land cover finds
  within 8 m of a hole's line (each tee along its route to the pin, past
  its first 10 m) are left out; Hirono's 12th had 93 photo trees on it.
  Trees mapped one by one and tree rows stay where they are.
- **The right course:** a name often finds the clubhouse, its restaurant
  or its road rather than the course (Pebble Beach Golf Links is a
  restaurant on the map; Royal Portrush's club a building). The search then
  looks for golf courses round the places found, the one round the place
  first, and ranks the courses named like the query first (a stable sort:
  equal places kept their order). Searches keep a second apart, as
  Nominatim asks. The builder picks the outline named like the place, then
  the one with most mapped holes, so a lodge beside a pitch-and-putt still
  gives the real course.
- **Clubs parted into their courses** even without `golf:course:name`: by
  the holes' own names ("L'Aigle - Trou n°3" at Golf National), refs like
  "4/9" (Banff Springs' nine beside its eighteen) or the courses' own
  outlines inside the club's (Crans-sur-Sierre). A few stray holes of a
  third course stay out. The course with most holes, then the longest
  (Royal County Down's Championship before Annesley), opens first.
- **Fails fast:** a map with no holes says so as soon as the map is read
  (it used to fetch a minute of ground, lidar and photos first), naming the
  tag that is missing. A hole whose ends run off the ground built (a club
  over 3.6 km is cut) or a stub under 20 m is left out. A lidar service
  that answers with no data (the course is outside its country) is not
  reported as a failed download. A search that can't reach Nominatim says
  so, rather than "nothing found".
- **No freezes:** the course is built in steps of a fraction of a second
  (`RealCourseBuilder.build_steps`), the lidar canopy is read a band of
  rows at a time, and trees are checked against the play areas, buildings
  and woods by 32 m cells instead of one by one (Pebble Beach's photo has
  77,000 trees). Golf National held the game still for 8 s and Hilversum's
  lidar for 2 s; the longest pause is now about half a second. The
  club's other courses reuse the ground already read.
- **The land to the horizon** (`RealLandscape`): the open elevation tiles
  8 km each way from the course, on a 40 m grid, drawn by `Landscape` as
  the epic courses' land is, instead of the flat apron that showed from
  every high view. It follows the course's ground inside the course and
  eases into the land over 160 m outside. Where the tiles carry a sea floor
  (2 % of the land deeper than 8 m below sea level) the course gets a sea
  (`source.sea`), as at St Andrews, but only when hardly any of the
  course's own ground lies below sea level.
- **Lidar must agree with the tiles:** England's lidar answers outside
  England with zeros, which put Royal County Down at sea level and let the
  sea in over it. Lidar is used only when its ground and the open tiles'
  agree (not mostly zeros where the tiles say the land is above 2 m, and
  medians within 30 m: the tiles measure tree tops in places like
  Hilversum's woods).
- **No terraces:** where the open tiles come from data rounded to whole
  metres (SRTM; `TerrainTiles.height_step` finds a tenth or more of their
  pixels on whole metres), flat land reads as shelves tens of metres wide
  with a 1 m step between them: Royal County Down's fairways came out in
  stairs. `CoursePlayability.unterrace` gives each sample the ground
  smoothed over about its terrace's width (the step over the slope).
- **Burns that hold water:** a stream's line is smoothed and drawn as a
  ribbon with round bends (`ribbon`; mitred offsets folded over at tight
  bends), cut into pieces that fall at most 0.3 m (`stream_pieces`), and
  `DesignedTerrain` digs a narrow water shape to its depth within its own
  half width, so the Swilcan Burn shows water instead of a dark trench.
- **Greens kept dry:** a pond mapped over an island or peninsula green
  without its inner ring (Leopard Creek's 18th) has the green and a 3 m
  bank cut out (`dry_out`), joined to the shore by a 3 m causeway so the
  pond stays one shape with one water line.
- **Outlines that don't fold:** a shape whose curve crosses itself (a
  narrow green, a fairway's thin neck) has its points respaced
  (`untangle_shapes`).
- **Guessed fairways shaped like mown ones:** rounded ends, widest round
  the landing area, narrowing into the approach, wandering a little either
  side of the line, instead of a straight even bar.
- **The club's full name:** "Royal County Down Golf Club" finds nothing on
  the map; with no results the search tries the name with Golf Course,
  Golf Club and Golf Links, then alone.
- **Tees and pins where they belong:** a tee point mapped on the last
  hole's green is moved off it, and a hole whose line ends with no green
  near gets its pin moved out of the water it was drawn into.

`tools/realcourse_bench/e2e.sh` builds a course the way the game does and
audits it (each hole's tee and pin surfaces, green slope, par for its
length, trees on its line, and the reach check of `reach_tests.gd`);
`realcourse_tests.gd` checks each step above on made-up maps in CI.

## Building in the browser

The Web build has one thread, so a build runs between frames: downloads
are awaited, and the slow steps (decoding lidar chunks, finding trees one
surface chunk at a time) hand a frame back every 60 ms or between chunks.
A progress window shows the current step and the time taken, with a Cancel
button; a failure stays in that window until it is dismissed.

Phones and tablets (a touch screen in the browser, which includes iPads,
whose Safari reports a Mac) build a lighter course: at most 2,500 trees
and no close-up photos of the greens. iPad Safari drops the page's WebGL
context when it runs short of memory, which used to leave a black screen;
the page now shows a "Reload" message instead (`html/head_include` in the
Web export preset). The course is saved as soon as it is built, before the
designer draws it, so a reload keeps it.

## Licence notes

OpenStreetMap data is under the [ODbL](https://opendatacommons.org/licenses/odbl/).
A course built from it is a derivative of the map: keep its `credits` when
sharing it, and share it under the ODbL too. The importer adds the credits
itself, with one line for each lidar or photo source used. Nothing from
these services is stored in the repository; each player's game fetches it
when they build a course. The aerial photo stays on the player's machine
beside the course and isn't part of an exported `.olc`.

## Code map

```
game/scripts/realcourse/
  geo_frame.gd            GeoFrame: latitude and longitude to course metres
  geo_raster.gd           GeoRaster: GeoTIFF and BIL height grids
  national_lidar.gd       NationalLidar: the lidar services, and trees from the canopy
  aerial_photos.gd        AerialPhotos: the photo services, the course photo, trees from it
  land_cover.gd           LandCover: 10 m land cover, trees and ground colours from it
  course_guesser.gd       CourseGuesser: greens, tees, fairways and bunkers the map lacks
  course_detector.gd      CourseDetector: real greens, fairways and bunkers in the photo
  terrain_tiles.gd        TerrainTiles: which tiles, PNG decoding, height sampling
  real_course_builder.gd  RealCourseBuilder: OpenStreetMap data to a DesignedCourse
  course_playability.gd   CoursePlayability: greens that hold, level tees, smooth coarse ground
  real_landscape.gd       RealLandscape: the land round the course to the horizon
  real_course_fetcher.gd  RealCourseFetcher: the Nominatim, Overpass and tile requests
  real_course_dialog.gd   RealCourseDialog: the designer's window
game/tests/realcourse_tests.gd  checks on a made-up map (no network)
```

## Still to do

- Greens in the lidar (smooth, raised) where there is no photo, and
  fairways in low-contrast photos.
- More lidar and photo services (above); reprojecting from national
  grids would open most of the rest.
- The course outline as out of bounds where the club marks it so.
- The land round a real course coloured from the land cover (woods,
  towns, fields); it is one parkland green now.
- Hedges (`barrier=hedge`) and fences.
