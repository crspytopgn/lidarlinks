"""Bakes the sculpted golfer's own ambient occlusion into the look pack: how
much of the sky each point of the skin sees past the rest of the body.

    python3 tools/golfer/skin_occlusion.py [--pack game/assets/golfer/free_golfer_parts.olg] [--preview out.png]

A real face is lit unevenly even under a flat sky: the eye sockets, the
sides of the nose, under the nose and the lower lip, the corners of the
mouth, the folds of the ear and under the jaw stay darker, because the
face itself hides part of the sky from them. The scanned people's
textures carry that shading (it was photographed in); the sculpted
golfer's skin texture is one even colour, and screen-space AO is too
coarse at a face's scale (and Compatibility has none), so the Custom
golfer's face read as flat, a mask with features drawn on.

This traces it from the body mesh itself (with the eyes in their sockets):
for each skin vertex, CAST rays over the hemisphere it faces, cosine
weighted, and the share that hit the body within REACH (nearer hits count
more). The vertex values are drawn into the body's uv layout as a grey
image (materials.Skin.occlusion, white = open), grown past the islands'
edges so filtering never pulls in the background. golfer_skin.gdshader
takes it as ambient occlusion and darkens the colour a little in the
deepest creases, as the scans are.

It is traced on the neutral body: the face sliders move the features by
millimetres to a centimetre or two, and the hollows stay where they are.
It refuses a pack that has it already ("skin_occlusion").
"""

import argparse
import io
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(__file__))
import golf_shoes  # noqa: E402
from cap import part_arrays, span  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
CAST = 96  # rays per vertex
REACH = 0.1  # metres: hollows at a face's scale (eye sockets under the brow), not the arms over the chest
SIZE = 1024
GROW = 8  # texels the image reaches past each uv island
OCCLUDERS = ("Body", "Eyes")


def mesh(info, blob, name):
    e = info["parts"][name]
    pos = part_arrays(info, blob, name)[0].astype(np.float64)
    nrm = span(blob, e["normals"], np.float16).reshape(-1, 3).astype(np.float64)
    idx = span(blob, e["indices"], np.int32).reshape(-1, 3)
    uvs = span(blob, e["uvs"], np.float32).reshape(-1, 2).astype(np.float64)
    return pos, nrm, idx, uvs


def directions(n, count, rng):
    """`count` cosine-weighted directions over the hemisphere round `n`."""
    u1, u2 = rng.random(count), rng.random(count)
    r, phi = np.sqrt(u1), 2 * np.pi * u2
    local = np.stack([r * np.cos(phi), r * np.sin(phi), np.sqrt(1 - u1)], -1)
    a = np.array([1.0, 0, 0]) if abs(n[0]) < 0.9 else np.array([0, 1.0, 0])
    t = np.cross(n, a)
    t /= np.linalg.norm(t)
    b = np.cross(n, t)
    return local[:, :1] * t + local[:, 1:2] * b + local[:, 2:] * n


def first_hits(o, dirs, tris):
    """Distance along each of `dirs` from `o` to the nearest of `tris`
    (k x 3 x 3), inf where none is hit (Moller-Trumbore)."""
    if len(tris) == 0:
        return np.full(len(dirs), np.inf)
    v0, e1, e2 = tris[:, 0], tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    p = np.cross(dirs[:, None, :], e2[None])  # rays x tris x 3
    det = np.einsum("rtk,tk->rt", p, e1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    s = o - v0
    u = np.einsum("rtk,tk->rt", p, s) * inv
    q = np.cross(s, e1)
    v = np.einsum("rk,tk->rt", dirs, q) * inv
    t = np.einsum("tk,tk->t", e2, q)[None] * inv
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-4)
    return np.where(hit, t, np.inf).min(1)


def bake(info, blob):
    pos, nrm, idx, uvs = mesh(info, blob, "Body")
    occ_tris = [pos[idx]]
    for name in OCCLUDERS[1:]:
        if name in info["parts"]:
            p, _, i, _ = mesh(info, blob, name)
            occ_tris.append(p[i])
    tris = np.concatenate(occ_tris)
    centres = tris.mean(1)
    radius = np.linalg.norm(tris - centres[:, None], axis=-1).max(1)
    tree = cKDTree(centres)
    rng = np.random.default_rng(7)
    open_sky = np.ones(len(pos))
    for k in range(len(pos)):
        n = nrm[k] / max(np.linalg.norm(nrm[k]), 1e-9)
        o = pos[k] + n * 2e-4
        near = tree.query_ball_point(o, REACH + radius.max())
        near = [j for j in near if np.linalg.norm(centres[j] - o) < REACH + radius[j]]
        d = first_hits(o, directions(n, CAST, rng), tris[near])
        # A hit at the surface hides that bit of sky; one near REACH barely.
        open_sky[k] = 1.0 - np.mean(np.clip(1.0 - d / REACH, 0.0, 1.0))
    return open_sky, idx, uvs


def draw(values, idx, uvs, size=SIZE):
    """Per-vertex `values` drawn into the uv layout (v down), with the
    islands grown GROW texels into the background."""
    img = np.zeros((size, size))
    got = np.zeros((size, size), bool)
    q = uvs * size
    for tri in idx:
        a, b, c = q[tri]
        x0, y0 = np.maximum(np.floor(np.minimum(np.minimum(a, b), c)).astype(int), 0)
        x1, y1 = np.minimum(np.ceil(np.maximum(np.maximum(a, b), c)).astype(int) + 1, size)
        if x1 <= x0 or y1 <= y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1), np.arange(y0, y1))
        p = np.stack([xs + 0.5, ys + 0.5], -1).reshape(-1, 2)
        v0, v1 = b - a, c - a
        den = v0[0] * v1[1] - v0[1] * v1[0]
        if abs(den) < 1e-12:
            continue
        w1 = ((p[:, 0] - a[0]) * v1[1] - (p[:, 1] - a[1]) * v1[0]) / den
        w2 = (v0[0] * (p[:, 1] - a[1]) - v0[1] * (p[:, 0] - a[0])) / den
        w0 = 1 - w1 - w2
        inside = (w0 >= -0.02) & (w1 >= -0.02) & (w2 >= -0.02)
        val = w0 * values[tri[0]] + w1 * values[tri[1]] + w2 * values[tri[2]]
        px, py = p[inside, 0].astype(int), p[inside, 1].astype(int)
        img[py, px] = val[inside]
        got[py, px] = True
    for _ in range(GROW):
        pad = np.pad(img * got, 1)
        cnt = np.pad(got.astype(float), 1)
        h, w = img.shape
        s = sum(pad[dy:dy + h, dx:dx + w] for dy in range(3) for dx in range(3))
        c = sum(cnt[dy:dy + h, dx:dx + w] for dy in range(3) for dx in range(3))
        new = ~got & (c > 0)
        img[new] = s[new] / c[new]
        got |= new
    img[~got] = 1.0
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default=os.path.join(ROOT, "game/assets/golfer/free_golfer_parts.olg"))
    ap.add_argument("--preview", default="")
    args = ap.parse_args()
    info, blob = golf_shoes.load(args.pack)
    if info.get("skin_occlusion"):
        sys.exit("the pack has the skin occlusion already")
    values, idx, uvs = bake(info, blob)
    print("open sky: min %.2f, median %.2f" % (values.min(), np.median(values)))
    img = Image.fromarray((np.clip(draw(values, idx, uvs), 0, 1) * 255).astype(np.uint8), "L")
    img = img.filter(ImageFilter.GaussianBlur(0.7))
    if args.preview:
        img.save(args.preview)
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    data = np.frombuffer(buf.getvalue(), np.uint8)
    while len(blob) % 4:
        blob.append(0)
    off = len(blob)
    blob.extend(data.tobytes())
    info["images"].append({"kind": "png", "data": [off, int(data.nbytes)]})
    info["materials"]["Skin"]["occlusion"] = len(info["images"]) - 1
    info["skin_occlusion"] = 1
    golf_shoes.save(args.pack, info, blob)
    print("added the skin occlusion (%d bytes)" % data.nbytes)


if __name__ == "__main__":
    main()
