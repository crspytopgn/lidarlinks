#!/usr/bin/env python3
"""Draws the sward atlas: dense, short rough grass for right by the camera
(FescueField's sward ring).

    python3 tools/grass/sward_atlas.py OUT.png

Close up, real rough is a thick mat of fine blades: you see grass, not the
ground between it. Our 3D blades (GrassField) are a dozen per tuft, so near
the camera they stood apart as dark spikes on the ground texture. One card
of this atlas holds a couple of hundred fine blades for two triangles, so a
low carpet of them closes the gaps for a few thousand triangles. Four
variants (2 x 2, each 512 px for a patch 1 m wide and 1 m tall): fresh
green, a darker damp green, one with a few dry blades, and one with clover
leaves at the foot. Blades lean every way and bend over at the tips; the
deepest ones are darkest, as a sward shades itself. Alpha is the grass,
colour bled into the gaps for clean mipmaps. Needs only Pillow.
"""

import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

CELL = 512
GRID = 2
ROOT = (30, 48, 18)
MID = (60, 92, 36)
TIP = (98, 128, 60)
DRY = (160, 150, 98)
CLOVER = (58, 92, 34)


def _mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _patch(rng, s, damp, dry_share, clover):
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if clover:
        for _ in range(40):
            x = s * 0.5 + rng.gauss(0, s * 0.2)
            y = s - rng.uniform(6, s * 0.12)
            r = rng.uniform(0.012, 0.018) * s
            col = _mix(CLOVER, MID, rng.random() * 0.6)
            for k in range(3):
                a = k / 3 * math.tau - math.pi / 2 + rng.uniform(-0.2, 0.2)
                cx, cy = x + math.cos(a) * r, y + math.sin(a) * r * 0.55
                d.ellipse([cx - r, cy - r * 0.6, cx + r, cy + r * 0.6], fill=col + (255,))
    blades = []
    for _ in range(rng.randint(320, 380)):
        rx = min(max(s * 0.5 + rng.gauss(0, s * 0.16), s * 0.1), s * 0.9)
        # Ragged: mostly short blades and a few long ones, so a card has no
        # flat top edge (a row of them read as clipped hedges).
        height = (0.15 + 0.82 * rng.random() ** 1.6) * s
        lean = rng.gauss(0, 0.4)
        bend = rng.uniform(0.1, 0.7) * (1 if lean >= 0 else -1)
        blades.append((rng.random(), rx, height, lean, bend, rng.random() < dry_share))
    blades.sort()  # back to front
    for depth, rx, height, lean, bend, dry in blades:
        shade = (0.5 + 0.5 * depth) * (0.85 if damp else 1.0)
        steps = 10
        pts = []
        for i in range(steps + 1):
            t = i / steps
            x = rx + (lean * t + bend * t * t * t * 0.5) * height * 0.6
            y = s - 3 - height * (t - 0.15 * abs(bend) * t * t * t)
            pts.append((x, y, t))
        for i in range(steps):
            x0, y0, t0 = pts[i]
            x1, y1, _t1 = pts[i + 1]
            w = max(1, int(round(5 * (1.0 - t0 * 0.75))))
            c = _mix(ROOT, MID, t0 * 1.6) if t0 < 0.6 else _mix(MID, TIP, (t0 - 0.6) / 0.4)
            if dry:
                c = _mix(c, DRY, 0.3 + 0.6 * t0)
            c = tuple(min(255, int(v * shade)) for v in c)
            d.line([(x0, y0), (x1, y1)], fill=c + (255,), width=w)
    return img


def _bleed(img: Image.Image) -> Image.Image:
    alpha = img.getchannel("A")
    mask = alpha.point(lambda v: 255 if v > 8 else 0)
    filled = img.convert("RGB")
    for radius in (2, 4, 8, 16, 32):
        blur = filled.filter(ImageFilter.GaussianBlur(radius))
        filled = Image.composite(filled, blur, mask)
        mask = mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: 255 if v > 20 else 0)
    out = filled.convert("RGBA")
    out.putalpha(alpha)
    return out


def build(out_path: str, seed: int = 2003) -> None:
    rng = random.Random(seed)
    atlas = Image.new("RGBA", (CELL * GRID, CELL * GRID), (0, 0, 0, 0))
    variants = [(False, 0.04, False), (True, 0.02, False), (False, 0.18, False), (False, 0.05, True)]
    for k, (damp, dry, clover) in enumerate(variants):
        cell = _patch(rng, CELL * 2, damp, dry, clover).resize((CELL, CELL), Image.LANCZOS)
        atlas.alpha_composite(cell, ((k % GRID) * CELL, (k // GRID) * CELL))
    _bleed(atlas).save(out_path, optimize=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    build(sys.argv[1])
