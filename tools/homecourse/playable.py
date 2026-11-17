#!/usr/bin/env python3
"""Makes a course built from the map playable, hole by hole.

Greens are graded as a club's builder would: a green that follows a hillside (Glacier Crown's sat on the mountain
at 10 to 20 %, where no ball can stop) is cut and filled to a gentle plate
falling 2 % toward the front, keeping a softened share of its own contours,
and the ground round it is eased onto the new plate over 14 m. Greens that
are already playable (under 3 % with no steep spots) are left as measured.
Even lidar greens come out 4 to 6 % across once resampled to the 2 m grid,
where a real green's pinnable ground is under 3 %.

    python3 tools/homecourse/playable.py IN.olc [OUT.olc]

It also drops par 3 tees no club can carry to the green from (trim_tees)
and clears trees standing in a hole's line of play (clear_lines): Glacier
Crown's 13th had a grove of pines 20 to 70 m in front of its tee.

dress_real_course.py runs this on every course it dresses; run it alone to
grade a course that is already dressed. game/tests/reach_tests.gd checks the
greens can be held.
"""

import gzip
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_home_course as hc  # noqa: E402
import geom  # noqa: E402

FALL = 0.02  # the graded plate's fall toward the front
MAX_PLANE = 0.03  # a green steeper overall than this is graded
MAX_SPOT = 0.045  # or with a quarter of it steeper than this
BLEND_M = 14.0  # the ground round it eases onto the plate over this
CONTOUR_KEEP = 0.35  # share of the green's own (smoothed) contours kept
CONTOUR_MAX = 0.15  # m, either side of the plate


def decode(d):
    import base64
    import zlib
    h = d["heights"]
    deltas = np.frombuffer(zlib.decompress(base64.b64decode(h["data"])), dtype="<i2").astype(np.int64)
    x0, z0, w, hh = d["area"]
    cols = int(round(w / d["cell"])) + 1
    rows = int(round(hh / d["cell"])) + 1
    return np.cumsum(deltas).reshape(rows, cols) / 100.0


def _front(d, pin):
    """Unit (x, z) from the pin toward where the green is approached from."""
    best = None
    for h in d["holes"]:
        p = np.asarray(h["pin"], dtype=np.float64)
        if np.hypot(*(p - pin)) < 60.0:
            route = np.asarray(h.get("route", []), dtype=np.float64).reshape(-1, 2)
            back = route[-1] if len(route) else np.asarray(h["tees"][:2], dtype=np.float64)
            best = back - p
            break
    if best is None or np.hypot(*best) < 1e-6:
        return None
    return best / np.hypot(*best)


def _slopes(h, cell):
    gz, gx = np.gradient(h, cell)
    return np.hypot(gx, gz)


def grade(d, log=print):
    """Grades `d`'s too-steep greens in place. Returns how many it graded."""
    height = decode(d)
    x0, z0 = d["area"][0], d["area"][1]
    cell = d["cell"]
    rows, cols = height.shape
    graded = 0
    for s in d["shapes"]:
        if s["surface"] != "Green":
            continue
        poly = np.asarray(s["points"], dtype=np.float64).reshape(-1, 2)
        lo = poly.min(0) - BLEND_M - 2 * cell
        hi = poly.max(0) + BLEND_M + 2 * cell
        i0 = max(0, int((lo[0] - x0) / cell))
        i1 = min(cols, int((hi[0] - x0) / cell) + 2)
        j0 = max(0, int((lo[1] - z0) / cell))
        j1 = min(rows, int((hi[1] - z0) / cell) + 2)
        xs = x0 + np.arange(i0, i1) * cell
        zs = z0 + np.arange(j0, j1) * cell
        X, Z = np.meshgrid(xs, zs)
        sd = geom.signed_distance(poly, X, Z)
        g = sd < 0.0
        if g.sum() < 20:
            continue
        h = height[j0:j1, i0:i1]
        A = np.stack([np.ones(g.sum()), X[g], Z[g]], 1)
        coef, *_ = np.linalg.lstsq(A, h[g], rcond=None)
        plane = coef[0] + coef[1] * X + coef[2] * Z
        tilt = math.hypot(coef[1], coef[2])
        # Steep spots inside it (the collar's bank at the edge doesn't count).
        core = sd < -2.0 * cell
        spot = np.percentile(_slopes(h, cell)[core if core.sum() >= 10 else g], 75)
        if tilt <= MAX_PLANE and spot <= MAX_SPOT:
            continue
        c = np.array([X[g].mean(), Z[g].mean()])
        front = _front(d, c)
        if front is None:
            front = -np.array([coef[1], coef[2]]) / max(tilt, 1e-9)  # keep its own fall
        # The plate: the green's mean height at its middle, falling FALL
        # toward the front.
        plate = h[g].mean() - FALL * ((X - c[0]) * front[0] + (Z - c[1]) * front[1])
        # Its own contours, smoothed and softened, so it isn't a flat board.
        res = np.where(g, h - plane, 0.0)
        res = geom.gaussian(res, 2.0)
        res = np.clip(res * CONTOUR_KEEP, -CONTOUR_MAX, CONTOUR_MAX)
        inner = geom.smoothstep(0.0, 3.0, -sd)
        outer = 1.0 - geom.smoothstep(0.0, BLEND_M, sd)
        # Inside the plate (with the kept contours); round it, the change of
        # plane carried out and eased away.
        delta = np.where(g, (plate - plane) + inner * (res - (h - plane)), (plate - plane) * outer)
        height[j0:j1, i0:i1] = h + delta
        graded += 1
        log(f"  green at ({c[0]:.0f}, {c[1]:.0f}): {tilt * 100:.1f} % (steep quarter {spot * 100:.1f} %)"
            f" graded to {FALL * 100:.0f} %, up to {np.abs(delta).max():.1f} m cut or fill")
    if graded:
        d["heights"] = hc.encode_heights(height)
    return graded


LONGEST_PAR3 = 220.0  # m: a driver carries about 224 m (Club.standard_set)


def trim_tees(d, log=print):
    """Drops par 3 tees further than LONGEST_PAR3 from the pin while the hole
    keeps another: from Ember Coast's real back tee the 3rd is 245 m all
    carry over the sea, which no club in the bag reaches. The tee box stays
    as scenery. Returns how many it dropped."""
    dropped = 0
    for n, h in enumerate(d["holes"]):
        if h["par"] != 3:
            continue
        tees = np.asarray(h["tees"], dtype=np.float64).reshape(-1, 2)
        pin = np.asarray(h["pin"], dtype=np.float64)
        keep = [t for t in tees if np.hypot(*(t - pin)) <= LONGEST_PAR3]
        if keep and len(keep) < len(tees):
            for t in tees:
                if np.hypot(*(t - pin)) > LONGEST_PAR3:
                    log(f"  hole {n + 1}: tee {np.hypot(*(t - pin)):.0f} m from the pin dropped")
            dropped += len(tees) - len(keep)
            h["tees"] = [round(float(v), 2) for t in keep for v in t]
    return dropped


LINE_CLEAR = 10.0  # m either side of a hole's line kept free of trees


def clear_lines(d, log=print):
    """Drops trees within LINE_CLEAR of any hole's line of play, from each
    tee along its route to the pin. Returns how many it dropped."""
    lines = []
    for h in d["holes"]:
        route = [tuple(p) for p in np.asarray(h.get("route", []), dtype=np.float64).reshape(-1, 2)]
        for t in np.asarray(h["tees"], dtype=np.float64).reshape(-1, 2):
            lines.append(np.array([tuple(t)] + route + [tuple(h["pin"])]))
    keep = []
    dropped = 0
    for o in d["objects"]:
        if o["id"].startswith(("tree_", "palm_")):
            x = np.array([o["x"]])
            z = np.array([o["z"]])
            if any(geom.polyline_distance(line, x, z)[0][0] < LINE_CLEAR for line in lines):
                dropped += 1
                continue
        keep.append(o)
    if dropped:
        log(f"  {dropped} trees cleared from lines of play")
    d["objects"] = keep
    return dropped


def main():
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else src
    raw = open(src, "rb").read()
    zipped = raw[:2] == b"\x1f\x8b"
    d = json.loads(gzip.decompress(raw) if zipped else raw)
    n = grade(d)
    t = trim_tees(d)
    c = clear_lines(d)
    blob = json.dumps(d, separators=(",", ":")).encode()
    if zipped:
        with gzip.open(out, "wb", compresslevel=9) as f:
            f.write(blob)
    else:
        open(out, "wb").write(blob)
    print(f"{out}: {n} greens graded, {t} tees dropped, {c} trees cleared")


if __name__ == "__main__":
    main()
