#!/usr/bin/env python3
"""Draws the meadow plant atlas for the wild ground off the course (FescueField).

    python3 tools/grass/meadow_atlas.py OUT.png

Real long grass is never only grass. In photos of real rough and meadow
(and in Toni Macaroni's Godot forest scenes Michael pointed to, 2026-11-17)
the ground is a mix: broad-leaved plants such as plantain and dock low
among the blades, clover, and small white and yellow flowers dotted
through it. That mix is what makes a hillside read as living ground rather
than one even fur. This draws four such plants (2 x 2, each 512 px for a
plant 1 m wide and 1 m tall; most are drawn in the lower part of the cell):

    0  oxeye daisies: thin stems with white heads, yellow eyes
    1  buttercups: branched stems with small glossy yellow cups
    2  a broad-leaved rosette (plantain or dock), no flowers
    3  yarrow and clover: flat white flower heads over soft leaves

Alpha is the plant, colour bled into the gaps for clean mipmaps. Nothing
is photographed or downloaded, so it needs only Pillow.
"""

import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

CELL = 512
GRID = 2
LEAF_DARK = (34, 58, 22)
LEAF = (66, 104, 38)
LEAF_LIGHT = (112, 146, 64)
STEM = (78, 104, 46)
WHITE = (236, 234, 222)
EYE = (222, 176, 40)
YELLOW = (238, 200, 36)


def _mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def _leaf(d, x, y, angle, length, width, col, rib=True):
    """A pointed oval leaf from (x, y) along `angle` (radians, 0 = up)."""
    pts_l, pts_r = [], []
    steps = 12
    dx, dy = math.sin(angle), -math.cos(angle)
    nx, ny = -dy, dx
    for i in range(steps + 1):
        t = i / steps
        w = math.sin(math.pi * min(t * 1.1, 1.0)) * width * (1.0 - 0.3 * t)
        cx, cy = x + dx * length * t, y + dy * length * t
        pts_l.append((cx + nx * w, cy + ny * w))
        pts_r.append((cx - nx * w, cy - ny * w))
    d.polygon(pts_l + pts_r[::-1], fill=col + (255,))
    if rib:
        d.line([(x, y), (x + dx * length * 0.9, y + dy * length * 0.9)], fill=_shade(col, 1.25) + (255,), width=2)


def _stem(d, x0, y0, x1, y1, bend, col, width=3):
    pts = []
    for i in range(11):
        t = i / 10
        pts.append((x0 + (x1 - x0) * t + bend * math.sin(math.pi * t), y0 + (y1 - y0) * t))
    d.line(pts, fill=col + (255,), width=width)
    return pts[-1]


def _grass_skirt(d, rng, s, count, top):
    """A few fine blades round the plant's foot, so it sits in the grass."""
    for _ in range(count):
        rx = s * 0.5 + rng.gauss(0, s * 0.12)
        h = rng.uniform(0.08, top) * s
        lean = rng.gauss(0, 0.35)
        col = _mix(LEAF_DARK, LEAF_LIGHT, rng.random() * 0.8)
        d.line([(rx, s - 2), (rx + lean * h * 0.5, s - 2 - h)], fill=col + (255,), width=3)


def _daisies(rng, s):
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for _ in range(14):
        _leaf(d, s * 0.5 + rng.gauss(0, s * 0.06), s - 4, rng.gauss(0, 1.1), rng.uniform(0.08, 0.16) * s, s * 0.018,
              _mix(LEAF_DARK, LEAF, rng.random()))
    heads = []
    for _ in range(rng.randint(5, 8)):
        x0 = s * 0.5 + rng.gauss(0, s * 0.07)
        top = (rng.uniform(0.35, 0.62)) * s
        x1 = x0 + rng.gauss(0, s * 0.08)
        tip = _stem(d, x0, s - 4, x1, s - top, rng.gauss(0, 10), STEM, 4)
        heads.append((rng.random(), tip))
    _grass_skirt(d, rng, s, 70, 0.3)
    for depth, (x, y) in sorted(heads):
        r = rng.uniform(0.026, 0.036) * s
        tilt = rng.uniform(0.45, 0.8)  # seen a little from the side
        for k in range(18):
            a = k / 18 * math.tau + rng.uniform(-0.05, 0.05)
            px, py = x + math.cos(a) * r, y + math.sin(a) * r * tilt
            pr = r * 0.3
            d.ellipse([min(x, px) - pr * 0.4, min(y, py) - pr * 0.4, max(x, px) + pr * 0.4, max(y, py) + pr * 0.4],
                      fill=_shade(WHITE, 0.82 + 0.18 * depth) + (255,))
        e = r * 0.34
        d.ellipse([x - e, y - e * tilt, x + e, y + e * tilt], fill=EYE + (255,))
    return img


def _buttercups(rng, s):
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Lobed leaves low down: three small leaves fanned per leaf.
    for _ in range(10):
        x = s * 0.5 + rng.gauss(0, s * 0.08)
        base = rng.gauss(0, 0.9)
        for k in (-0.5, 0.0, 0.5):
            _leaf(d, x, s - 6, base + k, rng.uniform(0.06, 0.1) * s, s * 0.024, _mix(LEAF_DARK, LEAF, rng.random()), rib=False)
    _grass_skirt(d, rng, s, 80, 0.35)
    for _ in range(rng.randint(3, 5)):
        x0 = s * 0.5 + rng.gauss(0, s * 0.05)
        top = rng.uniform(0.4, 0.6) * s
        x1 = x0 + rng.gauss(0, s * 0.06)
        _stem(d, x0, s - 4, x1, s - top, rng.gauss(0, 8), STEM, 3)
        # Branches off the upper half, each with a cup.
        for b in range(rng.randint(2, 4)):
            t = rng.uniform(0.5, 0.95)
            bx, by = x0 + (x1 - x0) * t, s - 4 - top * t
            ex, ey = bx + rng.uniform(-0.09, 0.09) * s, by - rng.uniform(0.03, 0.1) * s
            d.line([(bx, by), (ex, ey)], fill=STEM + (255,), width=2)
            r = rng.uniform(0.014, 0.02) * s
            d.ellipse([ex - r, ey - r * 0.75, ex + r, ey + r * 0.75], fill=YELLOW + (255,))
            d.ellipse([ex - r * 0.5, ey - r * 0.6, ex + r * 0.2, ey - r * 0.1], fill=_shade(YELLOW, 1.12) + (255,))
        tr = rng.uniform(0.016, 0.022) * s
        d.ellipse([x1 - tr, s - top - tr * 0.75, x1 + tr, s - top + tr * 0.75], fill=YELLOW + (255,))
    return img


def _rosette(rng, s):
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    _grass_skirt(d, rng, s, 50, 0.25)
    leaves = []
    for _ in range(rng.randint(9, 13)):
        leaves.append((rng.random(), rng.gauss(0, 0.75), rng.uniform(0.18, 0.34) * s, rng.uniform(0.035, 0.06) * s))
    for depth, ang, length, width in sorted(leaves):
        col = _mix(LEAF_DARK, LEAF_LIGHT, 0.25 + 0.6 * depth)
        _leaf(d, s * 0.5 + rng.gauss(0, s * 0.02), s - 4, ang, length, width, col)
    # A couple of thin plantain seed spikes.
    for _ in range(rng.randint(1, 3)):
        x0 = s * 0.5 + rng.gauss(0, s * 0.04)
        top = rng.uniform(0.45, 0.6) * s
        x1, y1 = _stem(d, x0, s - 4, x0 + rng.gauss(0, s * 0.05), s - top, rng.gauss(0, 6), STEM, 2)
        d.ellipse([x1 - 4, y1 - 18, x1 + 4, y1 + 4], fill=(96, 92, 58, 255))
    return img


def _yarrow(rng, s):
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Clover underneath: trefoil leaves.
    for _ in range(26):
        x = s * 0.5 + rng.gauss(0, s * 0.16)
        y = s - rng.uniform(4, s * 0.09)
        r = rng.uniform(0.011, 0.016) * s
        col = _mix(LEAF_DARK, LEAF_LIGHT, rng.random() * 0.8)
        for k in range(3):
            a = k / 3 * math.tau - math.pi / 2 + rng.uniform(-0.2, 0.2)
            cx, cy = x + math.cos(a) * r, y + math.sin(a) * r * 0.6
            d.ellipse([cx - r, cy - r * 0.7, cx + r, cy + r * 0.7], fill=col + (255,))
        if rng.random() < 0.3:  # a white clover head
            d.ellipse([x - r, y - r * 3.2, x + r, y - r * 1.4], fill=_shade(WHITE, 0.92) + (255,))
    _grass_skirt(d, rng, s, 70, 0.3)
    for _ in range(rng.randint(2, 4)):
        x0 = s * 0.5 + rng.gauss(0, s * 0.06)
        top = rng.uniform(0.38, 0.55) * s
        x1, y1 = _stem(d, x0, s - 4, x0 + rng.gauss(0, s * 0.05), s - top, rng.gauss(0, 6), STEM, 3)
        # Feathery leaves up the stem.
        for k in range(5):
            t = 0.15 + k * 0.13
            lx, ly = x0 + (x1 - x0) * t, s - 4 - top * t
            side = 1 if k % 2 else -1
            _leaf(d, lx, ly, side * rng.uniform(0.7, 1.2), s * 0.05, s * 0.008, LEAF, rib=False)
        # A flat umbel of tiny white florets.
        w = rng.uniform(0.05, 0.075) * s
        for _ in range(60):
            fx = x1 + rng.uniform(-w, w)
            fy = y1 + rng.uniform(-w * 0.18, w * 0.18) + abs(fx - x1) / w * w * 0.12
            r = rng.uniform(2.5, 4.0)
            d.ellipse([fx - r, fy - r, fx + r, fy + r], fill=_shade(WHITE, rng.uniform(0.85, 1.0)) + (255,))
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
    plants = [_daisies, _buttercups, _rosette, _yarrow]
    for k, draw in enumerate(plants):
        # Drawn at twice the size and shrunk, for smooth thin stems.
        cell = draw(rng, CELL * 2).resize((CELL, CELL), Image.LANCZOS)
        atlas.alpha_composite(cell, ((k % GRID) * CELL, (k // GRID) * CELL))
    _bleed(atlas).save(out_path, optimize=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    build(sys.argv[1])
