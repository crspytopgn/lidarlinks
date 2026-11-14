#!/usr/bin/env python3
"""A 2 x 2 card atlas (cells of 512 px, each plant standing on the bottom
centre of its cell, colour bled into the transparent texels) from the
billboard textures that come with Megascans 3D plants: each plant's
*_Billboard_BaseColor/Opacity holds a few pre-rendered views of it. For
the private Megascans pack (docs/megascans-pack.md); never commit the result.

    python3 billboard_cards.py OUT.png MODEL_DIR [MODEL_DIR ...]

The biggest sprites of the given plants are taken in turn, so one model
gives four views of itself and four models one each.
"""
import glob
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

CELL = 512


def sprites(d):
    c = Image.open(glob.glob(d + '/*Billboard_BaseColor.jpg')[0]).convert('RGB')
    o = Image.open(glob.glob(d + '/*Billboard_Opacity.jpg')[0]).convert('L')
    a = np.asarray(o) > 30
    lab, _ = ndimage.label(ndimage.binary_dilation(a, iterations=6))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), 1):
        y, x = sl
        if y.stop - y.start < c.height * 0.08:
            continue
        mask = (lab[sl] == i) & a[sl]
        alpha = Image.fromarray((np.asarray(o)[sl] * mask).astype(np.uint8))
        s = c.crop((x.start, y.start, x.stop, y.stop)).convert('RGBA')
        s.putalpha(alpha)
        out.append((int(mask.sum()), s))
    out.sort(key=lambda t: -t[0])
    return [s for _, s in out]


def main():
    out, dirs = sys.argv[1], sys.argv[2:]
    lists = [sprites(d) for d in dirs]
    picks = []
    k = 0
    while len(picks) < 4 and any(lists):
        lst = lists[k % len(lists)]
        if lst:
            picks.append(lst.pop(0))
        k += 1
    atlas = Image.new('RGBA', (CELL * 2, CELL * 2), (0, 0, 0, 0))
    for i, s in enumerate(picks):
        f = (CELL - 8) / max(s.width, s.height)
        s = s.resize((max(1, int(s.width * f)), max(1, int(s.height * f))), Image.LANCZOS)
        atlas.paste(s, ((i % 2) * CELL + (CELL - s.width) // 2, (i // 2) * CELL + CELL - s.height), s)
    arr = np.asarray(atlas).astype(np.float32)
    bl = np.asarray(atlas.filter(ImageFilter.GaussianBlur(8))).astype(np.float32)
    fill = np.clip(bl[..., :3] / np.maximum(bl[..., 3:4], 1) * 255, 0, 255)
    m = arr[..., 3:4] / 255
    arr[..., :3] = arr[..., :3] * m + fill * (1 - m)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(out)
    bg = Image.new('RGBA', atlas.size, (150, 190, 230, 255))
    bg.alpha_composite(atlas)
    bg.convert('RGB').save(out + '.preview.jpg')


if __name__ == '__main__':
    main()
