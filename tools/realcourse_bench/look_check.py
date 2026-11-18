#!/usr/bin/env python3
"""Dev tool: does a built real course look like the real place from above?

    look_check.py /tmp/rc/look_<slug>      (the files look_export.gd wrote)

Fetches a satellite picture of the same ground (Esri World Imagery, kept
only in /tmp as a cache for this check: never committed, saved into a
course or used by the builder), reads it into the same cells and flags
what the built course gets wrong, in patches big enough to see:

  water  the picture shows water (a lake, the sea, a pond) where the game
         has land: Lake Michigan beside Whistling Straits was a flat field
  fescue the picture shows straw native grass where the game has mown grass
  sand   the picture shows sand where the game has none

Prints one line per finding and a LOOK summary, and writes <base>_look.png
(picture | game | findings) to look at. Exit code 1 when anything is
flagged, so it can gate a batch.
"""
import io
import json
import math
import os
import sys
import urllib.request

import numpy as np
from PIL import Image

ESRI = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
CACHE = "/tmp/rc/esri_cache"
ZOOM = 17
WATER_PATCH = 20000.0  # m2 of water the game misses before it counts
FESCUE_SHARE = 0.7     # of the picture's fescue cells the game may mow
FESCUE_MIN = 50000.0   # m2 of fescue in the picture before that counts
SAND_PATCH = 150.0     # m2 of a sand patch the game misses


def tile_xy(lat, lon, z):
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    y = (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n
    return x, y


def fetch(z, x, y):
    os.makedirs(CACHE, exist_ok=True)
    path = f"{CACHE}/{z}_{x}_{y}.jpg"
    if not os.path.exists(path):
        req = urllib.request.Request(ESRI.format(z=z, x=x, y=y), headers={"User-Agent": "openlinks2003-dev-check"})
        data = urllib.request.urlopen(req, timeout=30).read()
        with open(path, "wb") as f:
            f.write(data)
    return Image.open(path).convert("RGB")


def picture(meta, zoom):
    """The picture's colour at each cell centre, as an (h, w, 3) float array."""
    w, h = meta["w"], meta["h"]
    c = meta["corners"]
    lat = lambda i, j: (c["00"][0] * (1 - i) * (1 - j) + c["10"][0] * i * (1 - j) + c["01"][0] * (1 - i) * j + c["11"][0] * i * j)
    lon = lambda i, j: (c["00"][1] * (1 - i) * (1 - j) + c["10"][1] * i * (1 - j) + c["01"][1] * (1 - i) * j + c["11"][1] * i * j)
    u = np.linspace(0, 1, w)[None, :].repeat(h, 0)
    v = np.linspace(0, 1, h)[:, None].repeat(w, 1)
    la, lo = lat(u, v), lon(u, v)
    n = 2 ** zoom
    tx = (lo + 180.0) / 360.0 * n
    ty = (1.0 - np.arcsinh(np.tan(np.radians(la))) / np.pi) / 2.0 * n
    x0, x1 = int(tx.min()), int(tx.max())
    y0, y1 = int(ty.min()), int(ty.max())
    if (x1 - x0 + 1) * (y1 - y0 + 1) > 900:
        return picture(meta, zoom - 1)
    mosaic = Image.new("RGB", ((x1 - x0 + 1) * 256, (y1 - y0 + 1) * 256))
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            try:
                mosaic.paste(fetch(zoom, x, y), ((x - x0) * 256, (y - y0) * 256))
            except Exception as e:
                print(f"  tile {zoom}/{x}/{y}: {e}")
    m = np.asarray(mosaic, dtype=np.float32) / 255.0
    # A cell is 6 m, several pixels: the mean of a 5 x 5 block round its centre.
    px = ((tx - x0) * 256).astype(int)
    py = ((ty - y0) * 256).astype(int)
    out = np.zeros((h, w, 3), np.float32)
    k = 0
    for dy in (-2, -1, 0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            out += m[np.clip(py + dy, 0, m.shape[0] - 1), np.clip(px + dx, 0, m.shape[1] - 1)]
            k += 1
    return out / k


def hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn + 1e-6
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
    s = np.where(mx > 0, (mx - mn) / (mx + 1e-6), 0)
    return hue, s, mx


def grow(mask, n):
    """A boolean mask grown by n cells each way (a square)."""
    out = mask.copy()
    for axis in (0, 1):
        acc = out.copy()
        for d in range(1, n + 1):
            acc |= np.roll(out, d, axis) | np.roll(out, -d, axis)
        out = acc
    return out


def patches(mask):
    """Connected patches of a boolean mask: list of (cells, (i, j) centre)."""
    h, w = mask.shape
    seen = np.zeros_like(mask)
    out = []
    for j0, i0 in zip(*np.nonzero(mask)):
        if seen[j0, i0]:
            continue
        stack = [(j0, i0)]
        seen[j0, i0] = True
        cells = []
        while stack:
            j, i = stack.pop()
            cells.append((j, i))
            for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                a, b = j + dj, i + di
                if 0 <= a < h and 0 <= b < w and mask[a, b] and not seen[a, b]:
                    seen[a, b] = True
                    stack.append((a, b))
        js = [c[0] for c in cells]
        is_ = [c[1] for c in cells]
        out.append((len(cells), (int(np.mean(is_)), int(np.mean(js)))))
    return out


def main():
    base = sys.argv[1]
    meta = json.load(open(base + ".json"))
    game = np.asarray(Image.open(base + ".png"))
    if game.ndim == 3:
        game = game[..., 0]
    rough = game == 8
    game = np.where(rough, 0, game)  # mapped rough is mown grass too
    cell = meta["cell"]
    area = cell * cell
    pic = picture(meta, ZOOM)
    hue, sat, val = hsv(pic)
    r, g, b = pic[..., 0], pic[..., 1], pic[..., 2]
    fair = [(j, i) for i, j in meta["fairway_cells"] if 0 <= j < game.shape[0] and 0 <= i < game.shape[1]]
    fh = lambda a: float(np.median([a[j, i] for j, i in fair])) if fair else 0.0
    fair_hue, fair_sat, fair_val = fh(hue), fh(sat), fh(val)
    # The picture's season: in a dormant (winter or drought) picture the
    # fairways are straw too, and fescue can't be told from them.
    green = fair_hue > 0.17 and fair_sat > 0.18
    # Water: cyan to blue, well bluer than the fairways (a turbid shore
    # reads green-grey and is missed; the open water past it is not).
    water = (hue >= max(0.4, fair_hue + 0.12)) & (hue <= 0.72) & (sat > 0.12) & (val > 0.15)
    sand = (val > max(0.7, fair_val + 0.12)) & (sat < 0.3)
    trees = val < 0.3
    fescue = (~water) & (~sand) & (~trees) & (sat >= 0.14) & (val >= 0.3) & (hue < fair_hue - 0.045) & (hue > 0.05)
    g_water = (game == 3) | (game == 6)
    near_trees = np.zeros_like(game, bool)
    t4 = game == 4
    for dj in (-2, -1, 0, 1, 2):
        for di in (-2, -1, 0, 1, 2):
            near_trees |= np.roll(np.roll(t4, dj, 0), di, 1)
    # Off the course's edges (houses, roads, gardens) and off the picture's
    # wood edges (pine straw under the trees reads as straw fescue).
    edge = grow(game >= 5, 4) | grow(trees, 2)
    in_course = (game <= 3) & ~near_trees & ~edge
    findings = []
    notes = []
    for n, (i, j) in patches(water & ~g_water & (game != 4)):
        if n * area >= WATER_PATCH:
            findings.append(f"water: the picture has {n * area / 1e4:.1f} ha of water at cell ({i}, {j}) where the game has land")
    mown = fescue & in_course & (game == 0)
    pic_fescue = fescue & in_course & (game != 2) & (game != 3)
    if not green:
        notes.append("the picture's grass is dormant, so fescue and sand aren't judged")
    elif pic_fescue.sum() * area >= FESCUE_MIN and mown.sum() > FESCUE_SHARE * pic_fescue.sum():
        findings.append(f"fescue: {mown.sum() * area / 1e4:.1f} of the picture's {pic_fescue.sum() * area / 1e4:.1f} ha of straw fescue is mown in the game ({(mown & rough).sum() * area / 1e4:.1f} ha of it mapped rough)")
    bunkers = [p for p in patches(sand & in_course) if SAND_PATCH <= p[0] * area <= 3000.0]
    missing = 0
    for n, (i, j) in bunkers:
        if game[j, i] != 2:
            missing += 1
    if green and len(bunkers) >= 8 and missing > 0.5 * len(bunkers):
        findings.append(f"sand: {missing} of the picture's {len(bunkers)} sand patches have no sand in the game")
    # The side-by-side to look at.
    colours = np.array([[70, 120, 50], [170, 160, 90], [230, 215, 160], [60, 110, 190], [30, 60, 30], [110, 110, 100], [40, 80, 150], [90, 100, 80]], np.uint8)
    gimg = colours[np.clip(game, 0, 7)]
    flag = np.zeros(game.shape + (3,), np.uint8) + 40
    flag[water & ~g_water & (game != 4)] = (60, 140, 255)
    flag[mown] = (255, 220, 60)
    flag[sand & in_course & (game != 2)] = (255, 255, 255) if green else (90, 90, 90)
    # Rows run with +z (north) and columns with +x (west): flipped both
    # ways each panel reads north up, east right.
    side = np.concatenate([p[::-1, ::-1] for p in ((pic * 255).astype(np.uint8), gimg, flag)], 1)
    Image.fromarray(side).save(base + "_look.png")
    name = meta.get("name", base)
    for f in findings:
        print(f"  {f}")
    for f in notes:
        print(f"  ({f})")
    print(f"LOOK {name}: {len(findings)} problems" + ("" if findings else ", matches the picture"))
    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()
