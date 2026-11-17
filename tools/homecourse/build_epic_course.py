#!/usr/bin/env python3
"""Builds the epic built-in courses: original nines laid on real, dramatic
ground, each with its own biome (ground colours, plants, rock) and the real
land for miles round it (the landscape the game draws to the horizon).

    python3 tools/homecourse/build_epic_course.py red_spire [--cache /tmp/dem] [--preview out.png]

Writes game/assets/courses/<course>.olc. It reuses the Kettle Hollow builder
(build_home_course.py) for the holes themselves: tees, fairways, rough,
greens and their contours, bunkers, ponds, mounding and pins, so every
course follows the same real design figures (docs/home-course.md). What
differs per course is set here: where on Earth the ground comes from, the
routing, the biome and what grows and stands between the holes. See
docs/epic-courses.md.

The ground is only the landform. None of these is, or copies, a real golf
course.
"""

import argparse
import base64
import math
import os
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_home_course as hc  # noqa: E402
import geom  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "..", "game", "assets", "courses")

# --- Red Spire --------------------------------------------------------------
# A desert nine on the floor of a red-rock valley in south-east Utah (Castle
# Valley, 38.64 N, 109.39 W): a sloping valley floor 3 km wide between
# 400 m sandstone walls, with towers on the skyline. Terrarium tiles there
# come from USGS 3DEP (public domain). Map coordinates are metres east (E)
# and south (S) of the north-west corner of a 2.6 km patch round the centre.
RED_SPIRE = dict(
    file="red_spire.olc",
    name="Red Spire",
    lat=38.6414, lon=-109.39, zoom=14, span=2600.0,
    centre=(1200.0, 1350.0),
    biome="desert",
    rough_band=12.0,
    wander=0.24,
    holes=[
        # Desert target golf, as real desert courses play: the grass starts
        # after a carry over the desert from the tee ("carry", metres from
        # the back tee), and dry washes cross some holes ("gaps").
        # 1: uphill toward the rock band, a spire behind the green.
        dict(par=4, tee=(900, 1450), route=[], carry=150.0, green=(1150, 1180), gsize=(30, 23),
             fw=(33, 30, 24), bunkers=[("fw", 225, 19, 24, 10), ("gs", 290, 13, 7), ("gs", 70, 12, 6)],
             tilt=(2.2, 0.6), tier=None, seed=111),
        # 2: a par 5 bending round a hoodoo garden in its elbow.
        # A wash across the fairway at the lay-up: carry it or stop short.
        # The green sits up on a mesa, 35 m above: the third is played up
        # over its wall.
        dict(par=5, tee=(1180, 1130), route=[(1400, 1000)], carry=140.0, gaps=[(320.0, 360.0), (425.0, 470.0)], green=(1560, 820), gsize=(33, 22),
             fw=(36, 31, 24), bunkers=[("fw", 240, -20, 26, 11), ("fw", 380, 17, 18, 9), ("gs", 280, 15, 7),
                                       ("gs", 80, 12, 6)],
             tilt=(1.8, -0.8), tier=(0.55, 0.4), seed=123),
        # 3: a par 3 into the foot of twin towers.
        dict(par=3, tee=(1600, 770), route=[], carry=140.0, green=(1765, 705), gsize=(27, 24),
             fw=None, bunkers=[("gs", 300, 14, 7), ("gs", 50, 12, 6), ("gs", 170, 9, 5)],
             tilt=(2.4, 0.4), tier=None, seed=137),
        # 4: back down the valley, a butte along the right; a wash across
        # the driving zone (lay up, or carry it 235 m).
        dict(par=4, tee=(1785, 765), route=[], carry=130.0, gaps=[(200.0, 235.0)], green=(1705, 1145), gsize=(31, 22),
             fw=(34, 31, 24), bunkers=[("fw", 230, -18, 26, 11), ("gs", 300, 12, 6), ("gs", 60, 14, 7)],
             tilt=(1.9, 0.5), tier=None, seed=141),
        # 5: short and downhill, drivable, with a hoodoo standing in the
        # middle of the fairway 225 m out, on a strip of desert: play either
        # side of it, over it, or short.
        dict(par=4, tee=(1665, 1195), route=[], carry=130.0, gaps=[(208.0, 242.0)], green=(1405, 1390), gsize=(27, 24),
             fw=(30, 27, 22), bunkers=[("fw", 190, 15, 22, 10), ("gs", 320, 12, 6), ("gs", 30, 13, 6)],
             tilt=(2.6, -0.5), tier=None, seed=153),
        # 6: the long par 5 across the open desert.
        dict(par=5, tee=(1425, 1450), route=[(1380, 1720)], carry=150.0, gaps=[(300.0, 345.0)], green=(1220, 1880), gsize=(34, 22),
             fw=(36, 32, 24), bunkers=[("fw", 255, 19, 30, 12), ("fw", 230, -21, 16, 9), ("fw", 390, -15, 20, 9),
                                       ("gs", 285, 16, 7), ("gs", 95, 13, 6)],
             tilt=(2.0, 0.9), tier=(0.5, 0.4), seed=167),
        # 7: the signature: a par 3 played through a natural arch, 75 m
        # out from the tee, over an oasis pool.
        dict(par=3, tee=(1170, 1915), route=[], green=(1025, 1868), gsize=(28, 22),
             fw=None, bunkers=[("gs", 270, 13, 6), ("gs", 100, 14, 6)],
             pond=((1083, 1889), 24, 13, 0.3),
             tilt=(2.2, -0.6), tier=None, seed=171),
        # 8: dogleg home past a mesa.
        dict(par=4, tee=(990, 1815), route=[], carry=140.0, green=(690, 1560), gsize=(30, 23),
             fw=(34, 31, 24), bunkers=[("fw", 232, 18, 28, 11), ("fw", 245, -20, 20, 9), ("gs", 300, 12, 6),
                                       ("gs", 60, 15, 7)],
             tilt=(1.9, 0.5), tier=None, seed=183),
        # 9: back up to the clubhouse, a tower guarding the left.
        # Its green is up on a mesa 28 m above, the wall in front of it.
        dict(par=4, tee=(665, 1515), route=[], carry=120.0, gaps=[(270.0, 305.0)], green=(845, 1245), gsize=(31, 24),
             fw=(33, 30, 23), bunkers=[("fw", 210, -18, 26, 11), ("gs", 280, 15, 7), ("gs", 70, 14, 7),
                                       ("gs", 0, 9, 5)],
             tilt=(1.7, -0.7), tier=(0.45, 0.4), seed=197),
    ],
    stroke_index=[5, 1, 15, 7, 13, 3, 17, 9, 11],
    # Mesas sculpted into the valley floor, with sheer bedded walls: tees on
    # top playing down, greens perched up on them. Centre (E, S), size
    # (length, width m), angle (degrees, game frame), rise (m).
    benches=[
        dict(centre=(919, 1429), size=(100, 70), angle=133, rise=30.0, seed=501),  # 1st tee
        dict(centre=(1575, 800), size=(150, 95), angle=158, rise=35.0, seed=502),  # 2nd green, 3rd tee
        dict(centre=(1645, 1210), size=(100, 70), angle=-37, rise=40.0, seed=503),  # 5th tee
        dict(centre=(1156, 1910), size=(75, 60), angle=18, rise=24.0, seed=504),  # 7th tee
        dict(centre=(969, 1797), size=(100, 70), angle=40, rise=32.0, seed=505),  # 8th tee
        dict(centre=(851, 1237), size=(85, 75), angle=0, rise=28.0, seed=506),  # 9th green
    ],
    # The rock formations, the course's centrepiece: (kind, E, S, yaw
    # degrees, scale). Spires and hoodoos are towers (scale 1: about 40 m
    # and 14 m high), buttes flat-topped mesas (scale 1: about 90 m across
    # and 45 m high), the arch a natural bridge (scale 1: 46 m span).
    rocks=[
        ("rock_spire", 1245, 1150, 20, 1.45),  # beyond the 1st green
        ("rock_spire", 1275, 1180, 75, 0.8),
        ("rock_hoodoo", 1465, 1075, 0, 1.4),  # the 2nd's elbow
        ("rock_hoodoo", 1490, 1050, 130, 1.0),
        ("rock_hoodoo", 1440, 1105, 250, 0.8),
        ("rock_hoodoo", 1510, 1090, 60, 1.15),
        ("rock_spire", 1840, 650, 0, 1.6),  # twin towers behind the 3rd
        ("rock_spire", 1815, 600, 120, 1.25),
        ("rock_butte", 1905, 985, 15, 1.1),  # right of the 4th
        ("rock_hoodoo", 1600, 1330, 40, 1.0),  # left of the 5th
        ("rock_hoodoo", 1625, 1360, 200, 0.75),
        ("rock_hoodoo", 1485, 1330, 30, 0.9),  # in the 5th fairway
        ("rock_spire", 1560, 1640, 300, 1.1),  # right of the 6th
        ("rock_arch", 1099, 1892, 72, 1.0),  # the 7th is played through it, over the pool
        ("rock_spire", 950, 1835, 0, 1.0),  # behind the 7th green
        ("rock_butte", 760, 1780, 70, 1.25),  # a mesa off the 8th
        ("rock_spire", 700, 1330, 210, 1.3),  # left of the 9th
        ("rock_hoodoo", 735, 1300, 10, 0.9),
        ("rock_butte", 560, 1100, 160, 1.4),  # north-west corner
        ("rock_spire", 1970, 1250, 45, 1.3),  # east edge
        ("rock_spire", 1100, 2050, 0, 1.2),  # south edge, behind the 6th green
        ("rock_hoodoo", 1300, 2060, 80, 1.1),
    ],
    # Clear radius (metres, at scale 1) round each kind of formation.
    plants=dict(saguaro=1700, small=2600),
    credits=("Ground: Terrarium elevation tiles (Mapzen / AWS Open Data), from USGS 3DEP (public domain). "
             "An original course: the valley's landform only, no real course."),
)

COURSES = {"red_spire": RED_SPIRE}

# Footprint radius (metres at scale 1) of each formation: nothing else stands
# within it, and it must stay this far off tees, fairways, greens and bunkers.
ROCK_REACH = {"rock_spire": 9.0, "rock_hoodoo": 4.5, "rock_butte": 48.0, "rock_arch": 26.0, "rock_boulder": 2.5}

# The land round the course, drawn to the horizon: metres between samples
# and how far it reaches each way from the course's middle.
LAND_CELL = 40.0
LAND_HALF = 8000.0
LAND_ZOOM = 12
LAND_BLEND = 160.0  # metres outside the course over which the land eases into it


def configure(spec):
    hc.LAT, hc.LON = spec["lat"], spec["lon"]
    hc.ZOOM, hc.SPAN = spec["zoom"], spec["span"]
    hc.CENTRE = spec["centre"]
    hc.HOLES = spec["holes"]
    hc.STROKE_INDEX = spec["stroke_index"]
    hc.NAME = spec["name"]
    hc.CREDITS = spec["credits"]
    hc.ROUGH_BAND = spec["rough_band"]
    hc.FW_WANDER = spec.get("wander", hc.FW_WANDER)
    hc.BLUR = spec.get("blur", hc.BLUR)
    hc.BENCHES = spec.get("benches", [])
    hc.RELIEF = spec.get("relief", 1.0)
    hc.ROUGH_WANDER = spec.get("wander", hc.ROUGH_WANDER) * 0.92


def rocks_in_game(spec):
    out = []
    for kind, e, s, yaw, scale in spec["rocks"]:
        x, z = hc.to_game((e, s))
        out.append((kind, x, z, yaw, scale))
    return out


def desert_dressing(spec):
    """The formations, then saguaros and small cacti over the open desert."""

    def place(holes, shapes, X, Z, height, area):
        rng = np.random.default_rng(4242)
        x0, z0, w, hh = area
        objects = []
        rocks = rocks_in_game(spec)
        # Formations must not stand on the playing surfaces.
        for kind, x, z, yaw, scale in rocks:
            reach = ROCK_REACH[kind] * scale
            for s, p in shapes:
                if s in (hc.ROUGH,):
                    continue
                d = geom.signed_distance(geom.outline(p), np.array([x]), np.array([z]))[0]
                if d < reach + 4.0:
                    print(f"warning: {kind} at ({x:.0f}, {z:.0f}) is {d:.0f} m from a {s}")
            objects.append((kind, x, z, yaw, scale))
        # Where plants may not grow: the playing surfaces (and a margin),
        # the rough bands, and the formations' feet.
        blocked = np.zeros(X.shape, dtype=bool)
        for s, p in shapes:
            poly = geom.outline(p)
            # Tee pads have mown banks round them (TeePads).
            margin = 3.0 if s == hc.ROUGH else (16.0 if s == hc.TEE else 10.0)
            lo = poly.min(0) - margin
            hi = poly.max(0) + margin
            m = (X >= lo[0]) & (X <= hi[0]) & (Z >= lo[1]) & (Z <= hi[1])
            blocked[m] |= geom.signed_distance(poly, X[m], Z[m]) < margin
        for kind, x, z, yaw, scale in rocks:
            r = ROCK_REACH[kind] * scale + 3.0
            blocked |= (X - x) ** 2 + (Z - z) ** 2 < r * r
        # Cart paths play as fairway: keep them clear.
        for p in hc.LAST_PATHS:
            d, _ = geom.polyline_distance(np.asarray(p, dtype=np.float64), X, Z)
            blocked |= d < 5.0
        # Bare rock: nothing grows on the steep slickrock.
        gz, gx = np.gradient(height, hc.CELL)
        blocked |= np.hypot(gx, gz) > 0.5
        near = np.full(X.shape, np.inf)
        for h in holes:
            d, _ = geom.polyline_distance(h.line, X, Z)
            near = np.minimum(near, d)
        # Saguaros stand in loose stands (a slow noise), thinning toward
        # the lines of play; small cacti (barrel, prickly pear, cholla)
        # everywhere between.
        dens = geom.value_noise(X, Z, 120.0, 51) + 0.35 * geom.value_noise(X, Z, 40.0, 52)
        taken = []
        grid = {}

        def clear(x, z, gap):
            ci, cj = int(x // 10), int(z // 10)
            for di in (-1, 0, 1):
                for dj in (-1, 0, 1):
                    for (tx, tz) in grid.get((ci + di, cj + dj), ()):
                        if (tx - x) ** 2 + (tz - z) ** 2 < gap * gap:
                            return False
            return True

        def take(x, z):
            taken.append((x, z))
            grid.setdefault((int(x // 10), int(z // 10)), []).append((x, z))

        def cell(x, z):
            return int(round((z - z0) / hc.CELL)), int(round((x - x0) / hc.CELL))

        count = 0
        tries = 0
        while count < spec["plants"]["saguaro"] and tries < 200000:
            tries += 1
            x = rng.uniform(x0 + 4, x0 + w - 4)
            z = rng.uniform(z0 + 4, z0 + hh - 4)
            j, i = cell(x, z)
            if blocked[j, i] or near[j, i] < 22.0:
                continue
            if rng.random() > (dens[j, i] + 0.15) * 1.6:
                continue
            if not clear(x, z, 7.0):
                continue
            objects.append(("cactus_saguaro", x, z, rng.uniform(0, 360), rng.uniform(0.6, 1.25)))
            take(x, z)
            count += 1
        saguaros = count
        count = 0
        tries = 0
        while count < spec["plants"]["small"] and tries < 200000:
            tries += 1
            x = rng.uniform(x0 + 3, x0 + w - 3)
            z = rng.uniform(z0 + 3, z0 + hh - 3)
            j, i = cell(x, z)
            if blocked[j, i] or near[j, i] < 14.0:
                continue
            if not clear(x, z, 2.5):
                continue
            kind = "cactus_barrel" if rng.random() < 0.45 else "cactus_pear"
            objects.append((kind, x, z, rng.uniform(0, 360), rng.uniform(0.7, 1.3)))
            take(x, z)
            count += 1
        # Fallen blocks round each formation's foot.
        boulders = 0
        for kind, x, z, yaw, scale in rocks:
            n = {"rock_butte": 14, "rock_arch": 8, "rock_spire": 6, "rock_hoodoo": 3}[kind]
            for k in range(n):
                a = rng.uniform(0, math.tau)
                r = ROCK_REACH[kind] * scale * rng.uniform(1.05, 1.6)
                bx, bz = x + math.cos(a) * r, z + math.sin(a) * r
                if not (x0 + 3 < bx < x0 + w - 3 and z0 + 3 < bz < z0 + hh - 3):
                    continue
                j, i = cell(bx, bz)
                if near[j, i] < 18.0:
                    continue
                inside_shape = False
                for s, p in shapes:
                    if s == hc.ROUGH:
                        continue
                    poly = geom.outline(p)
                    if geom.signed_distance(poly, np.array([bx]), np.array([bz]))[0] < 5.0:
                        inside_shape = True
                        break
                if inside_shape:
                    continue
                objects.append(("rock_boulder", bx, bz, rng.uniform(0, 360), rng.uniform(0.6, 2.2)))
                boulders += 1
        print(f"dressing: {len(rocks)} formations, {boulders} boulders, {saguaros} saguaros, {count} small cacti")
        return objects

    return place


def encode_land(heights):
    """Heights in decimetres, each the difference from the one before, as
    little-endian int16, deflated and base64-encoded (the land reaches far
    higher than a course's +-150 m)."""
    dm = np.round(heights.ravel() * 10).astype(np.int64)
    deltas = np.diff(np.concatenate([[0], dm]))
    assert np.abs(deltas).max() < 32767
    raw = deltas.astype("<i2").tobytes()
    return {"encoding": "dm-delta-s16-deflate-base64", "count": int(dm.size),
            "data": base64.b64encode(zlib.compress(raw, 9)).decode()}


def landscape(spec, area, course_height, cache):
    """The real land round the course on a LAND_CELL grid in game
    coordinates, measured from the course's datum. Inside the course it
    follows the course's own ground, and it eases into it over LAND_BLEND
    metres outside, so the two meet without a step."""
    saved = (hc.ZOOM, hc.SPAN)
    hc.ZOOM, hc.SPAN = LAND_ZOOM, LAND_HALF * 2 + 4000.0
    dem, mpp = hc.fetch_dem(cache)
    hc.ZOOM, hc.SPAN = saved
    n = int(LAND_HALF * 2 / LAND_CELL) + 1
    cx, cz = area[0] + area[2] * 0.5, area[1] + area[3] * 0.5
    ox = round((cx - LAND_HALF) / LAND_CELL) * LAND_CELL
    oz = round((cz - LAND_HALF) / LAND_CELL) * LAND_CELL
    gx = ox + np.arange(n) * LAND_CELL
    gz = oz + np.arange(n) * LAND_CELL
    X, Z = np.meshgrid(gx, gz)
    # The wide patch is centred on the same point as the course's map, so
    # map E, S (from its own north-west corner) shift by the difference.
    shift = (LAND_HALF * 2 + 4000.0 - hc.SPAN) * 0.5
    E = hc.CENTRE[0] - X + shift
    S = hc.CENTRE[1] - Z + shift
    land = hc.sample(dem, mpp, E, S) - hc.DATUM
    # The course's own ground where the two overlap.
    x0, z0, w, h = area
    cols = course_height.shape[1]
    rows = course_height.shape[0]
    u = np.clip((X - x0) / hc.CELL, 0, cols - 1.001)
    v = np.clip((Z - z0) / hc.CELL, 0, rows - 1.001)
    i, j = u.astype(int), v.astype(int)
    fu, fv = u - i, v - j
    ch = (course_height[j, i] * (1 - fu) * (1 - fv) + course_height[j, i + 1] * fu * (1 - fv)
          + course_height[j + 1, i] * (1 - fu) * fv + course_height[j + 1, i + 1] * fu * fv)
    dx = np.maximum(np.maximum(x0 - X, X - (x0 + w)), 0.0)
    dz = np.maximum(np.maximum(z0 - Z, Z - (z0 + h)), 0.0)
    out = np.hypot(dx, dz)
    wgt = geom.smoothstep(0.0, LAND_BLEND, out)
    heights = ch * (1 - wgt) + land * wgt
    print(f"landscape: {n} x {n} at {LAND_CELL:.0f} m, {heights.min():.0f} to {heights.max():.0f} m from the course's low point")
    return {"origin": [float(ox), float(oz)], "cell": LAND_CELL, "cols": n, "rows": n,
            "heights": encode_land(heights)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("course", choices=sorted(COURSES))
    ap.add_argument("--cache", default="/tmp/dem")
    ap.add_argument("--preview")
    args = ap.parse_args()
    spec = COURSES[args.course]
    configure(spec)
    if spec["biome"] == "desert":
        hc.place_trees = desert_dressing(spec)
    dem, mpp = hc.fetch_dem(args.cache)
    holes, shapes, paths, objects, area, cols, rows, height = hc.build(dem, mpp)
    hc.EXTRA = {"biome": spec["biome"], "landscape": landscape(spec, area, height, args.cache)}
    if hc.LAST_BENCHES:
        # The benches' walls, drawn as bedded rock cliffs (RockFormations).
        hc.EXTRA["cliffs"] = [[round(float(v), 2) for p in o for v in p] for o in hc.LAST_BENCHES]
    out = os.path.join(OUT_DIR, spec["file"])
    hc.write_course(out, holes, shapes, paths, objects, area, cols, rows, height)
    total = 0
    for h in holes:
        y = h.length / hc.YARD
        total += y
        print(f"hole {h.n}: par {h.par}, {y:.0f} yd ({h.length:.0f} m)")
    print(f"total {total:.0f} yd, area {area[2]:.0f} x {area[3]:.0f} m, {len(objects)} objects,"
          f" relief {height.max():.1f} m, file {os.path.getsize(out) / 1024:.0f} KB")
    if args.preview:
        hc.preview(args.preview, holes, shapes, paths, objects, area, height)


if __name__ == "__main__":
    main()
