#!/usr/bin/env python3
"""Dresses a course built from the map (the designer's "Real course..."
button) as an epic desert course: our own desert biome, sandstone
formations, saguaros and small cacti, bare desert between the holes, and
the real land for miles round it.

    python3 tools/homecourse/dress_real_course.py IN.olc OUT.olc --name "Vermilion Ridge" [--cache DIR] [--preview out.png]

The holes, greens, bunkers, water and ground stay exactly as mapped and
measured (OpenStreetMap layout, national lidar). What changes is only the
scenery: roads, buildings' trees and the aerial photo are dropped, and the
formations and plants are placed by the rules here. The club's name is not
used. See docs/epic-courses.md.
"""

import argparse
import base64
import gzip
import json
import math
import os
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_epic_course as epic  # noqa: E402
import build_home_course as hc  # noqa: E402
import geom  # noqa: E402

ROCK_REACH = epic.ROCK_REACH
PLAY = ("Tee", "Fairway", "Green", "Sand", "Water")
# How many of each formation to look for room for, biggest first.
# The last figure is how far from play to aim for: 0 is as near as fits,
# more stands them out on the skyline.
FORMATIONS = [("rock_butte", 3, (1.2, 1.6), 260.0), ("rock_spire", 3, (1.7, 2.3), 170.0),
              ("rock_butte", 2, (0.8, 1.1), 0.0), ("rock_arch", 1, (0.9, 1.1), 0.0),
              ("rock_spire", 4, (1.0, 1.6), 0.0), ("rock_hoodoo", 6, (0.8, 1.3), 0.0)]


def load(path):
    raw = open(path, "rb").read()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    return json.loads(raw)


def decode_heights(d):
    h = d["heights"]
    assert h["encoding"] == "cm-delta-s16-deflate-base64", h["encoding"]
    deltas = np.frombuffer(zlib.decompress(base64.b64decode(h["data"])), dtype="<i2").astype(np.int64)
    cm = np.cumsum(deltas)
    x0, z0, w, hh = d["area"]
    cell = d["cell"]
    cols = int(round(w / cell)) + 1
    rows = int(round(hh / cell)) + 1
    assert cols * rows == cm.size, (cols, rows, cm.size)
    return cm.reshape(rows, cols) / 100.0


def flat(points):
    return np.asarray(points, dtype=np.float64).reshape(-1, 2)


def hole_lines(d):
    out = []
    for h in d["holes"]:
        tees = flat(h["tees"])
        pts = [tees[0]] + list(flat(h.get("route", []))) + [np.asarray(h["pin"], dtype=np.float64)]
        out.append(np.array(pts))
    return out


def offset(poly, dist):
    """The outline pushed out by `dist` along its vertex normals (outlines
    from the map are smooth, so a mitre-free offset is enough)."""
    p = poly
    area = 0.5 * np.sum(p[:, 0] * np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1) * p[:, 1])
    t = np.roll(p, -1, 0) - np.roll(p, 1, 0)
    t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-6)
    n = np.stack([t[:, 1], -t[:, 0]], 1)
    if area < 0:
        n = -n
    return p + n * dist


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--name", required=True)
    ap.add_argument("--cache", default="/tmp/dem")
    ap.add_argument("--saguaros", type=int, default=650)
    ap.add_argument("--small", type=int, default=2600)
    ap.add_argument("--preview")
    args = ap.parse_args()

    d = load(args.src)
    height = decode_heights(d)
    x0, z0, w, hh = d["area"]
    cell = d["cell"]
    rows, cols = height.shape
    gx = x0 + np.arange(cols) * cell
    gz = z0 + np.arange(rows) * cell
    X, Z = np.meshgrid(gx, gz)
    lines = hole_lines(d)

    near = np.full(X.shape, np.inf)  # metres to the nearest line of play
    for ln in lines:
        dd, _ = geom.polyline_distance(ln, X, Z)
        near = np.minimum(near, dd)

    def near_at(x, z):
        j = int(np.clip(round((z - z0) / cell), 0, rows - 1))
        i = int(np.clip(round((x - x0) / cell), 0, cols - 1))
        return near[j, i]

    # --- Scenery that belongs to the town, not the course ------------------
    paths = []
    for p in d["paths"]:
        pts = flat(p["points"])
        mid = min(near_at(x, z) for x, z in pts)
        far = max(near_at(x, z) for x, z in pts)
        # Cart paths wind between the holes; roads, the airfield and the
        # streets of houses go.
        if p["width"] <= 3.0 and mid < 40.0 and far < 120.0:
            paths.append(p)
    print(f"paths: kept {len(paths)} of {len(d['paths'])}")
    d["paths"] = paths

    # Shapes of a neighbouring course, and drains along the airfield, go:
    # only what lies by this course's holes stays.
    kept = []
    for s in d["shapes"]:
        pts = flat(s["points"])
        if min(near_at(x, z) for x, z in pts) < 60.0:
            kept.append(s)
    print(f"shapes: kept {len(kept)} of {len(d['shapes'])}")
    d["shapes"] = kept
    shapes = [(s["surface"], flat(s["points"])) for s in d["shapes"]]
    trees = []
    for o in d["objects"]:
        if not o["id"].startswith("tree_"):
            continue
        if near_at(o["x"], o["z"]) > 55.0:
            continue  # gardens and streets
        o = dict(o)
        o["id"] = "tree_broadleaf"  # desert trees round the greens, not pines
        o["scale"] = round(min(o["scale"], 1.0) * 0.85, 2)
        trees.append(o)
    print(f"trees: kept {len(trees)} of {len(d['objects'])}")

    # --- Ground: bare desert, grass only where it is played ----------------
    m = 2.0
    base = [x0 + m, z0 + m, x0 + w - m, z0 + m, x0 + w - m, z0 + hh - m, x0 + m, z0 + hh - m]
    new_shapes = [{"surface": "Deep rough", "points": base}]
    bands = {"Fairway": 7.0, "Green": 9.0, "Tee": 5.0}
    for s, p in shapes:
        if s in bands and len(p) >= 3:
            o = offset(p, bands[s])
            new_shapes.append({"surface": "Rough", "points": [round(float(v), 2) for v in o.ravel()]})
    new_shapes += [s for s in d["shapes"]]
    d["shapes"] = new_shapes

    # --- Where nothing may stand -------------------------------------------
    blocked = np.zeros(X.shape, dtype=bool)
    play_mask = np.zeros(X.shape, dtype=bool)
    for s, p in shapes:
        margin = 3.0 if s == "Rough" else (16.0 if s == "Tee" else 10.0)
        lo = p.min(0) - margin
        hi = p.max(0) + margin
        mm = (X >= lo[0]) & (X <= hi[0]) & (Z >= lo[1]) & (Z <= hi[1])
        sd = geom.signed_distance(p, X[mm], Z[mm])
        blocked[mm] |= sd < margin
        if s in PLAY:
            play_mask[mm] |= sd < 0
    for p in paths:
        dd, _ = geom.polyline_distance(flat(p["points"]), X, Z)
        blocked |= dd < 5.0
    gzr, gxr = np.gradient(height, cell)
    slope = np.hypot(gxr, gzr)

    # Distance to anything played (for the formations, which are big).
    play_d = np.full(X.shape, np.inf)
    for s, p in shapes:
        if s not in PLAY:
            continue
        lo = p.min(0) - 250
        hi = p.max(0) + 250
        mm = (X >= lo[0]) & (X <= hi[0]) & (Z >= lo[1]) & (Z <= hi[1])
        play_d[mm] = np.minimum(play_d[mm], geom.signed_distance(p, X[mm], Z[mm]))
    for p in paths:
        dd, _ = geom.polyline_distance(flat(p["points"]), X, Z)
        play_d = np.minimum(play_d, dd + 10.0)
    play_d = np.minimum(play_d, near)

    rng = np.random.default_rng(2003)
    formations = []
    edge = np.minimum.reduce([X - x0, x0 + w - X, Z - z0, z0 + hh - Z])
    for kind, count, (s_lo, s_hi), target in FORMATIONS:
        for _ in range(count):
            scale = rng.uniform(s_lo, s_hi)
            reach = ROCK_REACH[kind] * scale
            ok = (play_d > reach + 22.0) & (edge > reach + 6.0)
            for (k2, fx, fz, _, sc2) in formations:
                gap = ROCK_REACH[k2] * sc2 + reach + 60.0
                ok &= (X - fx) ** 2 + (Z - fz) ** 2 > gap * gap
            if not ok.any():
                print(f"no room for a {kind}")
                break
            # Seen from the holes: as close to play as it fits, with a little
            # chance so they don't line up.
            score = np.where(ok, np.abs(play_d - (reach + 22.0) - target) + rng.random(X.shape) * 60.0, np.inf)
            j, i = np.unravel_index(np.argmin(score), score.shape)
            formations.append((kind, float(X[j, i]), float(Z[j, i]), float(rng.uniform(0, 360)), float(scale)))
    for kind, x, z, _, sc in formations:
        r = ROCK_REACH[kind] * sc + 3.0
        blocked |= (X - x) ** 2 + (Z - z) ** 2 < r * r
    blocked |= slope > 0.5

    objects = [dict(id=k, x=round(x, 1), z=round(z, 1), yaw=round(y, 1), scale=round(s, 2)) for k, x, z, y, s in formations]
    dens = geom.value_noise(X, Z, 120.0, 51) + 0.35 * geom.value_noise(X, Z, 40.0, 52)
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
        grid.setdefault((int(x // 10), int(z // 10)), []).append((x, z))

    for t in trees:
        take(t["x"], t["z"])

    def cell_of(x, z):
        return int(round((z - z0) / cell)), int(round((x - x0) / cell))

    sag = 0
    tries = 0
    while sag < args.saguaros and tries < 300000:
        tries += 1
        x = rng.uniform(x0 + 4, x0 + w - 4)
        z = rng.uniform(z0 + 4, z0 + hh - 4)
        j, i = cell_of(x, z)
        if blocked[j, i] or near[j, i] < 22.0:
            continue
        if rng.random() > (dens[j, i] + 0.15) * 1.6 or not clear(x, z, 7.0):
            continue
        objects.append(dict(id="cactus_saguaro", x=round(x, 1), z=round(z, 1), yaw=round(rng.uniform(0, 360), 1), scale=round(rng.uniform(0.6, 1.25), 2)))
        take(x, z)
        sag += 1
    small = 0
    tries = 0
    while small < args.small and tries < 300000:
        tries += 1
        x = rng.uniform(x0 + 3, x0 + w - 3)
        z = rng.uniform(z0 + 3, z0 + hh - 3)
        j, i = cell_of(x, z)
        if blocked[j, i] or near[j, i] < 14.0 or not clear(x, z, 2.5):
            continue
        kind = "cactus_barrel" if rng.random() < 0.45 else "cactus_pear"
        objects.append(dict(id=kind, x=round(x, 1), z=round(z, 1), yaw=round(rng.uniform(0, 360), 1), scale=round(rng.uniform(0.7, 1.3), 2)))
        take(x, z)
        small += 1
    boulders = 0
    for kind, x, z, _, sc in formations:
        for k in range({"rock_butte": 14, "rock_arch": 8, "rock_spire": 6, "rock_hoodoo": 3}[kind]):
            a = rng.uniform(0, math.tau)
            r = ROCK_REACH[kind] * sc * rng.uniform(1.05, 1.6)
            bx, bz = x + math.cos(a) * r, z + math.sin(a) * r
            if not (x0 + 3 < bx < x0 + w - 3 and z0 + 3 < bz < z0 + hh - 3):
                continue
            j, i = cell_of(bx, bz)
            if near[j, i] < 18.0 or play_d[j, i] < 6.0:
                continue
            objects.append(dict(id="rock_boulder", x=round(bx, 1), z=round(bz, 1), yaw=round(rng.uniform(0, 360), 1), scale=round(rng.uniform(0.6, 2.2), 2)))
            boulders += 1
    d["objects"] = objects + trees
    print(f"dressing: {len(formations)} formations {[f[0] for f in formations]}, {boulders} boulders, {sag} saguaros, {small} small cacti")

    # --- The land to the horizon -------------------------------------------
    src = d["source"]
    base_h = float(src.get("base_height", 0.0))
    hc.LAT, hc.LON, hc.ZOOM = float(src["lat"]), float(src["lon"]), epic.LAND_ZOOM
    hc.SPAN = epic.LAND_HALF * 2 + 4000.0
    dem, mpp = hc.fetch_dem(args.cache)
    half = hc.SPAN * 0.5
    n = int(epic.LAND_HALF * 2 / epic.LAND_CELL) + 1
    cx, cz = x0 + w * 0.5, z0 + hh * 0.5
    ox = round((cx - epic.LAND_HALF) / epic.LAND_CELL) * epic.LAND_CELL
    oz = round((cz - epic.LAND_HALF) / epic.LAND_CELL) * epic.LAND_CELL
    LX, LZ = np.meshgrid(ox + np.arange(n) * epic.LAND_CELL, oz + np.arange(n) * epic.LAND_CELL)
    # The course's +x is west and +z north; the tiles run east and south.
    land = hc.sample(dem, mpp, half - LX, half - LZ) - base_h
    u = np.clip((LX - x0) / cell, 0, cols - 1.001)
    v = np.clip((LZ - z0) / cell, 0, rows - 1.001)
    i, j = u.astype(int), v.astype(int)
    fu, fv = u - i, v - j
    ch = (height[j, i] * (1 - fu) * (1 - fv) + height[j, i + 1] * fu * (1 - fv)
          + height[j + 1, i] * (1 - fu) * fv + height[j + 1, i + 1] * fu * fv)
    dx = np.maximum(np.maximum(x0 - LX, LX - (x0 + w)), 0.0)
    dz = np.maximum(np.maximum(z0 - LZ, LZ - (z0 + hh)), 0.0)
    wgt = geom.smoothstep(0.0, epic.LAND_BLEND, np.hypot(dx, dz))
    lh = ch * (1 - wgt) + land * wgt
    print(f"landscape: {n} x {n}, {lh.min():.0f} to {lh.max():.0f} m")
    d["landscape"] = {"origin": [float(ox), float(oz)], "cell": epic.LAND_CELL, "cols": n, "rows": n,
                      "heights": epic.encode_land(lh)}

    # --- Name, biome, credits ----------------------------------------------
    d["name"] = args.name
    d["biome"] = "desert"
    src.pop("photo", None)
    d["author"] = "OpenLinks2003 (layout: OpenStreetMap contributors)"
    d["credits"] = (
        "Hole layout from OpenStreetMap, (c) OpenStreetMap contributors, ODbL 1.0 "
        "(openstreetmap.org/copyright). Ground: USGS 3D Elevation Program lidar, public domain; "
        "the land round it from the Terrain Tiles on AWS Open Data (Mapzen). Scenery (rock "
        "formations, plants, desert) by OpenLinks2003. Not connected with or endorsed by any club.")
    blob = json.dumps(d, separators=(",", ":")).encode()
    with gzip.open(args.out, "wb", compresslevel=9) as f:
        f.write(blob)
    print(f"wrote {args.out}: {os.path.getsize(args.out) // 1024} KB, relief {height.max() - height.min():.1f} m")

    if args.preview:
        from PIL import Image, ImageDraw
        sc = 0.5
        im = Image.new("RGB", (int(w * sc), int(hh * sc)), (190, 120, 80))
        dr = ImageDraw.Draw(im)
        col = {"Rough": (110, 150, 70), "Fairway": (90, 190, 80), "Green": (60, 230, 90), "Tee": (40, 160, 40),
               "Sand": (240, 230, 180), "Water": (60, 100, 200)}

        def px(x, z):  # west (+x) on the left, north (+z) up
            return ((x0 + w - x) * sc, (z0 + hh - z) * sc)

        for s in d["shapes"]:
            if s["surface"] in col:
                dr.polygon([px(x, z) for x, z in flat(s["points"])], fill=col[s["surface"]])
        for p in paths:
            dr.line([px(x, z) for x, z in flat(p["points"])], fill=(200, 200, 200), width=1)
        for o in objects:
            x, z = px(o["x"], o["z"])
            if o["id"].startswith("rock_") and o["id"] != "rock_boulder":
                r = ROCK_REACH[o["id"]] * o["scale"] * sc
                dr.ellipse([x - r, z - r, x + r, z + r], outline=(90, 20, 10), width=2)
            elif o["id"] == "cactus_saguaro":
                dr.point((x, z), fill=(20, 80, 20))
        im.save(args.preview)


if __name__ == "__main__":
    main()
