#!/usr/bin/env python3
"""A 2 x 2 card atlas (cells of 512 px, each plant standing on the bottom
centre of its cell, colour bled into the transparent texels) from the
billboard textures that come with Megascans 3D plants: each plant's
*_Billboard_BaseColor/Opacity holds a few pre-rendered views of it. For
the private Megascans pack (docs/megascans-pack.md); never commit the result.

    python3 billboard_cards.py OUT.png MODEL_DIR [MODEL_DIR ...]

The biggest sprites of the given plants are taken in turn, so one model
gives four views of itself and four models one each. Needs numpy and Pillow.
"""
import glob
import sys

import numpy as np
from PIL import Image, ImageFilter

CELL = 512
LABEL_SIZE = 1024  # sprites are found on a mask this many texels across


def _components(mask):
    """A label per texel (0 for none) and, per 8-connected part of a small
    boolean mask, its label, bounding box (y0, x0, y1, x1) and size."""
    h, w = mask.shape
    seen = np.zeros(mask.shape, np.int32)
    out = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        label = len(out) + 1
        stack = [(y, x)]
        seen[y, x] = label
        y0, x0, y1, x1, n = y, x, y, x, 0
        while stack:
            cy, cx = stack.pop()
            n += 1
            y0, x0, y1, x1 = min(y0, cy), min(x0, cx), max(y1, cy), max(x1, cx)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = label
                        stack.append((ny, nx))
        out.append((label, (y0, x0, y1 + 1, x1 + 1), n))
    return seen, out


def sprites(d):
    c = Image.open(glob.glob(d + '/*Billboard_BaseColor.jpg')[0]).convert('RGB')
    o = Image.open(glob.glob(d + '/*Billboard_Opacity.jpg')[0]).convert('L')
    if o.size != c.size:
        o = o.resize(c.size)
    # Grow the mask a texel so a plant's loose blades join its body.
    small = o.resize((LABEL_SIZE, LABEL_SIZE), Image.BOX).filter(ImageFilter.MaxFilter(3))
    s = c.width / LABEL_SIZE
    out = []
    labels, parts = _components(np.asarray(small) > 30)
    for label, (y0, x0, y1, x1), n in parts:
        if (y1 - y0) < LABEL_SIZE * 0.08:
            continue
        box = (int(x0 * s), int(y0 * s), min(c.width, int(x1 * s)), min(c.height, int(y1 * s)))
        sp = c.crop(box).convert('RGBA')
        # Only this plant's texels: neighbours reaching into its box are cut.
        own = Image.fromarray(((labels[y0:y1, x0:x1] == label) * 255).astype(np.uint8))
        own = own.filter(ImageFilter.MaxFilter(3)).resize(sp.size, Image.BILINEAR)
        alpha = np.asarray(o.crop(box)).astype(np.float32) * np.asarray(own).astype(np.float32) / 255
        sp.putalpha(Image.fromarray(alpha.astype(np.uint8)))
        out.append((n, sp))
    out.sort(key=lambda t: -t[0])
    return [sp for _, sp in out]


def atlas(dirs):
    lists = [sprites(d) for d in dirs]
    picks = []
    k = 0
    while len(picks) < 4 and any(lists):
        lst = lists[k % len(lists)]
        if lst:
            picks.append(lst.pop(0))
        k += 1
    if not picks:
        return None
    while len(picks) < 4:
        picks.append(picks[len(picks) % max(1, len(picks))].transpose(Image.FLIP_LEFT_RIGHT))
    out = Image.new('RGBA', (CELL * 2, CELL * 2), (0, 0, 0, 0))
    for i, sp in enumerate(picks):
        f = (CELL - 8) / max(sp.width, sp.height)
        sp = sp.resize((max(1, int(sp.width * f)), max(1, int(sp.height * f))), Image.LANCZOS)
        out.paste(sp, ((i % 2) * CELL + (CELL - sp.width) // 2, (i // 2) * CELL + CELL - sp.height), sp)
    arr = np.asarray(out).astype(np.float32)
    bl = np.asarray(out.filter(ImageFilter.GaussianBlur(8))).astype(np.float32)
    fill = np.clip(bl[..., :3] / np.maximum(bl[..., 3:4], 1) * 255, 0, 255)
    m = arr[..., 3:4] / 255
    arr[..., :3] = arr[..., :3] * m + fill * (1 - m)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def main():
    out = atlas(sys.argv[2:])
    if out is None:
        sys.exit('no sprites found')
    out.save(sys.argv[1])
    bg = Image.new('RGBA', out.size, (150, 190, 230, 255))
    bg.alpha_composite(out)
    bg.convert('RGB').save(sys.argv[1] + '.preview.jpg')


if __name__ == '__main__':
    main()
