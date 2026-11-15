"""Fescue tuft atlas for FescueField from Megascans photographed blades
(private pack): 2 x 2 cells of 512 px, a tuft about 1 m wide and up to
0.9 m tall in each, its root at the bottom centre, colour bled into the
transparent texels. python3 fescue_from_scans.py MEGASCANS_DIR OUT.png"""
import glob, math, random, sys
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

M, OUT = sys.argv[1], sys.argv[2]
CELL = 512


def blades(uid8, minfrac=0.18):
    d = glob.glob(f'{M}/*/material/*_{uid8}*')[0]
    c = Image.open(glob.glob(d + '/*BaseColor.jpg')[0]).convert('RGB').resize((2048, 2048), Image.LANCZOS)
    o = Image.open(glob.glob(d + '/*Opacity.jpg')[0]).convert('L').resize((2048, 2048), Image.LANCZOS)
    lab, n = ndimage.label(np.asarray(o) > 60, structure=np.ones((3, 3)))
    out = []
    for sl in ndimage.find_objects(lab):
        y, x = sl
        if y.stop - y.start < 2048 * minfrac:
            continue
        b = c.crop((x.start, y.start, x.stop, y.stop)).convert('RGBA')
        b.putalpha(o.crop((x.start, y.start, x.stop, y.stop)))
        arr = np.asarray(b).astype(np.float32)
        m = arr[..., 3] > 128
        if m.sum() < 50:
            continue
        lum = arr[..., :3][m].mean() / 255
        # Root at the bottom: scans are laid out tips up, mostly.
        out.append((b, lum))
    return out


def pick(lst, lo, hi):
    return [b for b, l in lst if lo <= l <= hi] or [b for b, _ in lst]


green = pick(blades('4eedbd46') + blades('3c66bbfe'), 0.0, 0.6)
dry = pick(blades('062b6490') + blades('5460fc12'), 0.0, 0.66)
seed = pick(blades('31674ec1', 0.3), 0.0, 1.0)
print(len(green), len(dry), len(seed))
GREY_GREEN = np.array([0.72, 0.86, 0.70])


def place(canvas, b, rng, h, tint):
    bb = b.resize((max(2, int(b.width * h / b.height * 0.6)), int(h)), Image.LANCZOS)
    arr = np.asarray(bb).astype(np.float32)
    arr[..., :3] *= np.linspace(1.05, 0.45, bb.height)[:, None, None] * tint
    bb = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    if rng.random() < 0.5:
        bb = bb.transpose(Image.FLIP_LEFT_RIGHT)
    k = max(-0.4, min(0.4, rng.gauss(0, 0.18)))  # lean: top moves k * height sideways
    H, w = bb.height, bb.width
    off = int(-k * H) if k < 0 else 0
    W = w + int(abs(k) * H) + 1
    sh = bb.transform((W, H), Image.AFFINE, (1, k, -k * H - off, 0, 1, 0), resample=Image.BICUBIC)
    rootx = CELL / 2 + max(-0.18, min(0.18, rng.gauss(0, 0.07))) * CELL
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    layer.paste(sh, (int(rootx - off - w / 2), CELL - H), sh)
    canvas.alpha_composite(layer)


def tuft(rng):
    img = Image.new('RGBA', (CELL, CELL), (0, 0, 0, 0))
    items = [('g', b) for b in rng.choices(green, k=50)] + [('d', b) for b in rng.choices(dry, k=8)] \
        + [('s', b) for b in rng.choices(seed, k=6)]
    rng.shuffle(items)
    for kind, b in items:
        h = rng.uniform(0.45, 0.85) * CELL * (1.1 if kind == 's' else 1.0)
        place(img, b, rng, min(h, CELL - 4), GREY_GREEN if kind == 'g' else np.ones(3))
    return img


rng = random.Random(11)
A = Image.new('RGBA', (CELL * 2, CELL * 2), (0, 0, 0, 0))
for i in range(4):
    A.paste(tuft(rng), ((i % 2) * CELL, (i // 2) * CELL))
arr = np.asarray(A).astype(np.float32)
bl = np.asarray(A.filter(ImageFilter.GaussianBlur(8))).astype(np.float32)
fill = bl[..., :3] / np.maximum(bl[..., 3:4], 1) * 255
m = arr[..., 3:4] / 255
arr[..., :3] = arr[..., :3] * m + np.clip(fill, 0, 255) * (1 - m)
Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(OUT)
bg = Image.new('RGBA', A.size, (150, 190, 230, 255)); bg.alpha_composite(A); bg.convert('RGB').save(OUT + '.preview.jpg')
