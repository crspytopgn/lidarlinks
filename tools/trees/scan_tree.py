#!/usr/bin/env python3
"""Turns a Poly Haven photoscanned tree (glTF, CC0) into the compact
.oltree file that TreeFactory draws as a near tree and bakes its impostor
from.

    python3 tools/trees/scan_tree.py SPEC_NAME [--src DIR] [--out DIR]

The scans are far too heavy for a game (Poly Haven's fir_tree_01 is 7.8
million triangles for three trees), so each one is cut down:

- Every leaf or twig (a connected piece of the leaf material) becomes one
  quad: the affine map from its UVs to its 3D points is fitted by least
  squares and the quad spans the piece's UV box, so the texture's alpha
  draws the leaf exactly where the scan had it. A share of the pieces is
  kept (`cards`) and grown to hold the crown's cover.
- The bark is decimated (quadric) with fast_simplification.

Needs numpy, scipy and fast_simplification (pip). Only the result is
committed (game/assets/trees/*.oltree), with the textures fetched by
tools/fetch_free_assets.py. Format, little endian:

    "OLTREE1\\0", u32 raw size, zlib stream of:
    f32 crown centre xyz, f32 crown radii xyz,
    u32 bark vertex count, u32 bark index count,
      f16 xyz, i8 normal xyz + texture (0 trunk, 1 branch), f16 uv, u32 indices
    u32 card count,
      f16 centre xyz, f16 u axis xyz, f16 v axis xyz (half extents),
      u16 uv box x0 y0 x1 y1 (/65535), u8 random,
      u8 kind (0 scanned leaf, 1 needle sprig card, 2 needle core card),
    then the lite bark, laid out as the bark
"""

import argparse
import json
import os
import struct
import sys
import zlib

import numpy as np

# name: glTF asset, node, leaf materials {index: texture slot}, bark
# materials {index: texture slot}, and how many leaf cards to keep.
SPECS = {
    "fir_a": dict(asset="fir_tree_01", node=0, leaves={2: 0}, bark={0: 1, 1: 0, 3: 1}, cards=12000, needles=True),
    "fir_b": dict(asset="fir_tree_01", node=1, leaves={2: 0}, bark={0: 1, 4: 0, 3: 1}, cards=9000, needles=True),
    "fir_c": dict(asset="fir_tree_01", node=2, leaves={2: 0}, bark={0: 1, 5: 0, 3: 1}, cards=9000, needles=True),
    "jacaranda": dict(asset="jacaranda_tree", node=0, leaves={2: 0}, bark={1: 0, 0: 1}, cards=12000),
    "island_01": dict(asset="island_tree_01", node=0, leaves={1: 0}, bark={0: 0, 2: 1}, cards=6000),
    "island_02": dict(asset="island_tree_02", node=0, leaves={1: 0}, bark={0: 0, 2: 1}, cards=5000),
    # PlantCatalog's "Realistic HD Northern red oak (35/138)" on Sketchfab
    # (CC BY 4.0, a 17.7 m old summer oak; download the glTF into
    # SRC/red_oak/). Every one of its 100,000 leaves is a quad of its own:
    # far too many cards, so the leaves are gathered into clusters
    # (leaf_clusters) drawn from an atlas of real leaf sprays rendered from
    # the model itself (--atlas). Its 600,000 twig triangles mostly go.
    "red_oak": dict(asset="red_oak", file="scene.gltf", node="all", leaves={1: 0, 2: 0, 3: 0},
                    bark={0: 0, 4: 1, 5: 1}, cards=7000, clusters=0.55,
                    # Its roots reach 1.7 m under its own ground (y 0).
                    ground=0.0,
                    # Written with the atlas: {file: (material, map, size)}.
                    textures={"trunk.jpg": (0, "baseColorTexture", (256, 2048)),
                              "trunk_normal.jpg": (0, "normalTexture", (256, 2048)),
                              "bark.jpg": (4, "baseColorTexture", (128, 1024))}),
}
# Bark pieces (separate tubes) shorter than this (m) are dropped first.
MIN_PIECE = {"jacaranda": 3.0, "red_oak": 0.7}
# Leaf-spray sprites in a cluster atlas: columns x rows.
ATLAS = (4, 2)
ATLAS_SPRITE = 512
BARK_TRIANGLES = {"red_oak": 14000, "fir_a": 6000, "fir_b": 4500, "fir_c": 4500, "jacaranda": 7000, "island_01": 4000, "island_02": 3000}

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def load_gltf(path):
    g = json.load(open(path))
    d = os.path.dirname(path)
    bins = [np.memmap(os.path.join(d, b["uri"]), dtype=np.uint8, mode="r") for b in g["buffers"]]

    def acc(i):
        a = g["accessors"][i]
        v = g["bufferViews"][a["bufferView"]]
        dt, n = CT[a["componentType"]], NC[a["type"]]
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        isz = np.dtype(dt).itemsize * n
        stride = v.get("byteStride", 0)
        if stride and stride != isz:
            raw = np.lib.stride_tricks.as_strided(bins[v["buffer"]][off:], shape=(a["count"], isz), strides=(stride, 1))
            arr = np.ascontiguousarray(raw).view(dt).reshape(a["count"], n)
        else:
            arr = np.frombuffer(bins[v["buffer"]], dtype=dt, count=a["count"] * n, offset=off).reshape(a["count"], n)
        return np.array(arr)

    return g, acc


def components(tri, nverts):
    """Connected pieces of a triangle list: a label per triangle."""
    lab = np.arange(nverts)
    e = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]])
    while True:
        m = np.minimum(lab[e[:, 0]], lab[e[:, 1]])
        new = lab.copy()
        np.minimum.at(new, e[:, 0], m)
        np.minimum.at(new, e[:, 1], m)
        new = new[new]
        if np.array_equal(new, lab):
            break
        lab = new
    return np.unique(lab[tri[:, 0]], return_inverse=True)[1]


def leaf_cards(pos, uv, tri, slot, rng):
    """One quad per connected leaf piece: (centre, u half axis, v half axis,
    uv box, slot)."""
    comp = components(tri, len(pos))
    n = comp.max() + 1
    corners = tri.reshape(-1)
    c = np.repeat(comp, 3)
    a = np.concatenate([uv[corners], np.ones((len(corners), 1))], axis=1)  # (k, 3)
    p = pos[corners]
    m = np.zeros((n, 3, 3))
    b = np.zeros((n, 3, 3))
    np.add.at(m, c, a[:, :, None] * a[:, None, :])
    np.add.at(b, c, a[:, :, None] * p[:, None, :])
    m += np.eye(3) * 1e-9
    lo = np.full((n, 2), np.inf)
    hi = np.full((n, 2), -np.inf)
    np.minimum.at(lo, c, uv[corners])
    np.maximum.at(hi, c, uv[corners])
    ok = np.all(hi - lo > 1e-4, axis=1) & (np.linalg.cond(m) < 1e9)
    m, b, lo, hi = m[ok], b[ok], lo[ok], hi[ok]
    aff = np.linalg.solve(m, b)  # rows: d/du, d/dv, offset
    mid = (lo + hi) * 0.5
    half = (hi - lo) * 0.5
    centre = mid[:, :1] * aff[:, 0] + mid[:, 1:] * aff[:, 1] + aff[:, 2]
    ua = aff[:, 0] * half[:, :1]
    va = aff[:, 1] * half[:, 1:]
    return dict(centre=centre, u=ua, v=va, lo=lo, hi=hi, slot=np.full(len(centre), slot, np.uint8))


def needle_cards(pos, tri, rng, cell=0.36):
    """For a conifer whose scan models every needle (Poly Haven's fir has
    millions of 1.5 cm needles): one sprig card per `cell` of needles,
    laid in the plane the needles there fill (PCA), its long side along
    the spray. The card's UV covers it whole, and the needle shader draws
    photo sprigs on it (TreeFactory's own conifer cards). No solid core
    cards (kind 2): between the scan's open branches they showed as flat
    discs."""
    p = pos[tri].mean(axis=1)
    out = []
    for size, slot in ((cell, 1),):
        key = np.floor(p / size).astype(np.int64)
        _, inv, counts = np.unique(key, axis=0, return_inverse=True, return_counts=True)
        inv = inv.reshape(-1)
        n = counts.size
        mean = np.zeros((n, 3))
        np.add.at(mean, inv, p)
        mean /= counts[:, None]
        d = p - mean[inv]
        cov = np.zeros((n, 3, 3))
        np.add.at(cov, inv, d[:, :, None] * d[:, None, :])
        cov /= counts[:, None, None]
        w, vec = np.linalg.eigh(cov)  # ascending
        w = np.maximum(w, 0.0)
        major = vec[:, :, 2]
        minor = vec[:, :, 1]
        ok = counts >= 10
        half_major = np.clip(np.sqrt(w[:, 2]) * 2.2, size * 0.45, size * 0.9)
        half_minor = np.clip(np.sqrt(w[:, 1]) * 2.2, size * 0.3, size * 0.7)
        u = minor * half_minor[:, None]
        v = major * half_major[:, None]
        k = ok.sum()
        out.append(dict(centre=mean[ok], u=u[ok], v=v[ok], lo=np.zeros((k, 2)), hi=np.ones((k, 2)),
                        slot=np.full(k, slot, np.uint8)))
    return {key: np.concatenate([o[key] for o in out]) for key in out[0]}


def primitives(g, spec):
    """(primitive, 4x4 world matrix) of the spec's node, or of every node
    with a mesh when its node is "all" (the Sketchfab exports nest their
    meshes under Z-up converting nodes)."""
    if spec["node"] != "all":
        node = g["nodes"][spec["node"]]
        for prim in g["meshes"][node["mesh"]]["primitives"]:
            yield prim, np.eye(4)
        return

    def local(n):
        if "matrix" in n:
            return np.array(n["matrix"], np.float64).reshape(4, 4).T
        m = np.eye(4)
        if "rotation" in n:
            x, y, z, w = n["rotation"]
            m[:3, :3] = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
        if "scale" in n:
            m[:3, :3] = m[:3, :3] * np.array(n["scale"])
        if "translation" in n:
            m[:3, 3] = n["translation"]
        return m

    stack = [(i, np.eye(4)) for i in g["scenes"][g.get("scene", 0)]["nodes"]]
    while stack:
        i, parent = stack.pop()
        n = g["nodes"][i]
        world = parent @ local(n)
        if "mesh" in n:
            for prim in g["meshes"][n["mesh"]]["primitives"]:
                yield prim, world
        stack.extend((c, world) for c in n.get("children", []))


def _leaf_quads(leaves):
    """Every leaf quad of a clustered scan: centres (n, 3) and, per leaf,
    its corner points, corner uvs and material."""
    pts, uvs, mats = [], [], []
    for pos, uv, tri, mat in leaves:
        # Each leaf is its own 4-vertex quad (two triangles).
        n = len(pos) // 4
        pts.append(pos[: n * 4].reshape(n, 4, 3))
        uvs.append(uv[: n * 4].reshape(n, 4, 2))
        mats.append(np.full(n, mat))
    pts, uvs, mats = np.concatenate(pts), np.concatenate(uvs), np.concatenate(mats)
    return pts.mean(axis=1), pts, uvs, mats


def _cells(centres, cell):
    key = np.floor(centres / cell).astype(np.int64)
    _, inv, counts = np.unique(key, axis=0, return_inverse=True, return_counts=True)
    inv = inv.reshape(-1)
    n = counts.size
    mean = np.zeros((n, 3))
    np.add.at(mean, inv, centres)
    mean /= counts[:, None]
    d = centres - mean[inv]
    cov = np.zeros((n, 3, 3))
    np.add.at(cov, inv, d[:, :, None] * d[:, None, :])
    cov /= counts[:, None, None]
    w, vec = np.linalg.eigh(cov)  # ascending
    return inv, counts, mean, vec


def leaf_clusters(leaves, cell, rng):
    """One card per `cell` of leaves, laid in the plane the leaves there
    fill (PCA), carrying one of the atlas's leaf sprays (cluster_atlas). A
    spray sprite spans a square of 1.5 cells, so neighbouring cards overlap
    as the leaves themselves do."""
    centres, _, _, _ = _leaf_quads(leaves)
    inv, counts, mean, vec = _cells(centres, cell)
    ok = counts >= 3
    half = cell * 0.75 * np.clip(np.sqrt(counts / 20.0), 0.7, 1.15)
    major, minor = vec[:, :, 2], vec[:, :, 1]
    k = int(ok.sum())
    cols, rows = ATLAS
    pick = rng.integers(0, cols * rows, k)
    lo = np.stack([(pick % cols) / cols, (pick // cols) / rows], axis=1)
    hi = lo + np.array([1.0 / cols, 1.0 / rows])
    # Mirrored at random (the uv box flipped) for more variety.
    flip = rng.random(k) < 0.5
    lo[flip, 0], hi[flip, 0] = hi[flip, 0].copy(), lo[flip, 0].copy()
    return dict(centre=mean[ok], u=minor[ok] * half[ok, None], v=major[ok] * half[ok, None], lo=lo, hi=hi,
                slot=np.zeros(k, np.uint8))


def cluster_atlas(name, leaves, cell, g, src_dir, out_dir):
    """Renders the leaf-spray atlas from the scan's own leaves: for a few
    well-filled cells, every leaf there projected onto the cell's plane and
    painted with its own photo texture, back to front. Writes
    scan_<name>_leaves.jpg (colour) and scan_<name>_leaves_alpha.png."""
    from PIL import Image

    centres, pts, uvs, mats = _leaf_quads(leaves)
    inv, counts, mean, vec = _cells(centres, cell)
    tex = {}
    for m in set(mats.tolist()):
        img = g["images"][g["textures"][g["materials"][m]["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]]
        tex[m] = Image.open(os.path.join(src_dir, img["uri"])).convert("RGBA")
    cols, rows = ATLAS
    size = ATLAS_SPRITE
    atlas = Image.new("RGBA", (cols * size, rows * size), (0, 0, 0, 0))
    # Well-filled cells, spread through the crown.
    order = np.argsort(counts)
    cand = order[int(len(order) * 0.86): int(len(order) * 0.99)]
    picks = cand[np.linspace(0, len(cand) - 1, cols * rows).astype(int)]
    span = cell * 0.75 * 2.0
    for s, c in enumerate(picks):
        major, minor, normal = vec[c, :, 2], vec[c, :, 1], vec[c, :, 0]
        sel = np.nonzero(inv == c)[0]
        # Back to front along the cell's normal.
        sel = sel[np.argsort((centres[sel] - mean[c]) @ normal)]
        sprite = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        for i in sel:
            # The leaf drawn whole and face on (projected, most leaves
            # would be edge-on slivers), where it hangs and turned the way
            # its stem points across the plane.
            img = tex[mats[i]]
            w, h = img.size
            uv = uvs[i]
            su = np.sign(uv[:, 0] - uv[:, 0].mean())
            sv = np.sign(uv[:, 1] - uv[:, 1].mean())
            if np.any(su == 0) or np.any(sv == 0):
                continue
            u3 = (pts[i][su > 0].mean(axis=0) - pts[i][su < 0].mean(axis=0)) * 0.5
            v3 = (pts[i][sv > 0].mean(axis=0) - pts[i][sv < 0].mean(axis=0)) * 0.5
            v2 = np.array([v3 @ minor, v3 @ major])
            lv = np.linalg.norm(v3)
            if np.linalg.norm(v2) < 1e-6 or lv < 1e-6:
                continue
            leaf_n = np.cross(u3, v3)
            facing = abs(leaf_n @ normal) / max(np.linalg.norm(leaf_n), 1e-9)
            v2 = v2 / np.linalg.norm(v2) * lv * (0.75 + 0.25 * np.linalg.norm(v2) / lv)
            side = 1.0 if (np.array([u3 @ minor, u3 @ major]) @ np.array([v2[1], -v2[0]])) >= 0 else -1.0
            u2 = np.array([v2[1], -v2[0]]) / lv * np.linalg.norm(u3) * side * (0.6 + 0.4 * facing)
            c2 = np.array([(centres[i] - mean[c]) @ minor, (centres[i] - mean[c]) @ major])
            dst = ((c2 + su[:, None] * u2 + sv[:, None] * v2) / span + 0.5) * size
            u0 = uv[:, 0].min()
            src = np.stack([(uv[:, 0] - np.floor(u0)) * w, uv[:, 1] * h], axis=1)
            # Affine from sprite pixels to texture pixels (corners 0, 1, 2).
            a = np.concatenate([dst[:3], np.ones((3, 1))], axis=1)
            if abs(np.linalg.det(a)) < 1e-6:
                continue
            coef = np.linalg.solve(a, src[:3])  # 3 x 2
            leaf = img.transform((size, size), Image.AFFINE, tuple(coef[:, 0]) + tuple(coef[:, 1]),
                                 resample=Image.BILINEAR)
            # Only inside the leaf's own quad.
            mask = Image.new("L", (size, size), 0)
            from PIL import ImageDraw
            order_q = np.argsort(np.arctan2(dst[:, 1] - dst[:, 1].mean(), dst[:, 0] - dst[:, 0].mean()))
            ImageDraw.Draw(mask).polygon([tuple(dst[j]) for j in order_q], fill=255)
            r, gg, b, al = leaf.split()
            from PIL import ImageChops
            # Leaves further back a little darker: the spray's own depth.
            depth = float((centres[i] - mean[c]) @ normal) / cell + 0.5
            shade = int(255 * np.clip(0.72 + 0.28 * depth, 0.6, 1.0))
            leaf = Image.merge("RGBA", [ch.point(lambda x, k=shade: x * k // 255) for ch in (r, gg, b)] + [ImageChops.multiply(al, mask)])
            sprite.alpha_composite(leaf)
        atlas.paste(sprite, ((s % cols) * size, (s // cols) * size))
    os.makedirs(out_dir, exist_ok=True)
    rgb = Image.new("RGB", atlas.size, (60, 72, 40))
    # Colour bled out under the transparent parts, so mipmaps don't darken
    # the leaf edges.
    bleed = atlas.resize((atlas.width // 16, atlas.height // 16), Image.BOX).resize(atlas.size, Image.BILINEAR)
    rgb.paste(bleed.convert("RGB"))
    rgb.paste(atlas.convert("RGB"), mask=atlas.split()[3])
    rgb.resize((rgb.width // 2, rgb.height // 2), Image.LANCZOS).save(os.path.join(out_dir, f"scan_{name}_leaves.jpg"), quality=88)
    atlas.split()[3].resize((rgb.width // 2, rgb.height // 2), Image.LANCZOS).save(os.path.join(out_dir, f"scan_{name}_leaves_alpha.png"), optimize=True)
    write_import(os.path.join(out_dir, f"scan_{name}_leaves.jpg"))
    write_import(os.path.join(out_dir, f"scan_{name}_leaves_alpha.png"))
    # The full-size atlas for Ultra on desktop (ScannedTree.hd; not in the
    # web build), so close crowns stay crisp.
    rgb.save(os.path.join(out_dir, f"scan_{name}_leaves_hd.jpg"), quality=88)
    atlas.split()[3].save(os.path.join(out_dir, f"scan_{name}_leaves_hd_alpha.png"), optimize=True)
    write_import(os.path.join(out_dir, f"scan_{name}_leaves_hd.jpg"))
    write_import(os.path.join(out_dir, f"scan_{name}_leaves_hd_alpha.png"))
    print(f"{name}: leaf atlas from {len(picks)} cells")


# Godot import settings for the committed textures (as
# tools/fetch_free_assets.py writes for the fetched ones): mipmapped, the
# opacity lossless. Committed with them.
TEXTURE_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode={mode}
compress/lossy_quality=0.85
mipmaps/generate=true
"""


def write_import(path):
    with open(path + ".import", "w") as f:
        f.write(TEXTURE_IMPORT.format(mode=0 if path.endswith(".png") else 1))


def scan_textures(name, spec, g, src_dir, out_dir):
    """The bark textures of a scan whose textures are committed (not
    fetched by tools/fetch_free_assets.py), as scan_<name>_<file>."""
    from PIL import Image

    for file, (mat, key, size) in spec.get("textures", {}).items():
        m = g["materials"][mat]
        ref = m.get(key) or m["pbrMetallicRoughness"][key]
        img = g["images"][g["textures"][ref["index"]]["source"]]
        im = Image.open(os.path.join(src_dir, img["uri"])).convert("RGB").resize(size, Image.LANCZOS)
        im.save(os.path.join(out_dir, f"scan_{name}_{file}"), quality=85)
        write_import(os.path.join(out_dir, f"scan_{name}_{file}"))


def thin(cards, count, rng):
    n = len(cards["centre"])
    keep = min(1.0, count / n)
    pick = rng.random(n) < keep
    # Cover held up to a point: grown much more, leaves turn into blobs.
    grow = min(1.0 / np.sqrt(keep), 2.0)
    out = {k: v[pick] for k, v in cards.items()}
    # Grown about each card's own middle, so the crown keeps its cover.
    out["u"] = out["u"] * grow
    out["v"] = out["v"] * grow
    return out


def decimate(pos, nrm, uv, tex, tri, target, min_piece=0.4):
    import fast_simplification
    from scipy.spatial import cKDTree

    if len(tri) <= target:
        return pos, nrm, uv, tex, tri
    # The finest twigs (thousands of loose little tubes) can't be reduced
    # below a few triangles each and vanish in the leaves anyway: drop the
    # short pieces (40 cm unless MIN_PIECE says otherwise). The jacaranda's
    # 33,000 twig tubes alone are a million triangles that no decimation
    # can bring down.
    comp = components(tri, len(pos))
    lo = np.full((comp.max() + 1, 3), np.inf)
    hi = np.full((comp.max() + 1, 3), -np.inf)
    np.minimum.at(lo, comp, pos[tri[:, 0]])
    np.maximum.at(hi, comp, pos[tri[:, 0]])
    tri = tri[np.linalg.norm(hi - lo, axis=1)[comp] >= min_piece]
    if len(tri) <= target:
        used, tri = np.unique(tri, return_inverse=True)
        return pos[used], nrm[used], uv[used], tex[used], tri.reshape(-1, 3)
    # Welded first: the scans split vertices along UV seams, and decimating
    # those as open borders tore holes in the trunks.
    welded, inv = np.unique(np.round(pos, 4), axis=0, return_inverse=True)
    wt = inv.reshape(-1)[tri]
    wt = wt[(wt[:, 0] != wt[:, 1]) & (wt[:, 1] != wt[:, 2]) & (wt[:, 0] != wt[:, 2])]
    p2, t2 = fast_simplification.simplify(welded.astype(np.float64), wt.astype(np.int32), target_count=target, agg=5.0)
    # Attributes from the nearest original vertex.
    _, near = cKDTree(pos).query(p2)
    return p2.astype(np.float32), nrm[near], uv[near], tex[near], t2


def cylinder_uv(pos):
    ang = np.arctan2(pos[:, 2], pos[:, 0]) / (2 * np.pi) + 0.5
    return np.stack([ang * 2.0, pos[:, 1] / 1.5], axis=1).astype(np.float32)


def build(name, src, out_dir, atlas_dir=None):
    spec = SPECS[name]
    g, acc = load_gltf(os.path.join(src, spec["asset"], spec.get("file", spec["asset"] + ".gltf")))
    rng = np.random.default_rng(7)
    bark_parts, cards = [], []
    leaves = []
    for prim, xf in primitives(g, spec):
        mat = prim["material"]
        at = prim["attributes"]
        pos = acc(at["POSITION"]).astype(np.float64) @ xf[:3, :3].T + xf[:3, 3]
        pos = pos.astype(np.float32)
        tri = acc(prim["indices"]).reshape(-1, 3).astype(np.int64)
        if mat in spec["leaves"] and spec.get("clusters"):
            leaves.append((pos, acc(at["TEXCOORD_0"]).astype(np.float64), tri, mat))
        elif mat in spec["leaves"] and spec.get("needles"):
            cards.append(needle_cards(pos.astype(np.float64), tri, rng))
        elif mat in spec["leaves"]:
            uv = acc(at["TEXCOORD_0"]).astype(np.float64)
            cards.append(leaf_cards(pos.astype(np.float64), uv, tri, spec["leaves"][mat], rng))
        elif mat in spec["bark"]:
            nrm = (acc(at["NORMAL"]).astype(np.float64) @ xf[:3, :3].T).astype(np.float32)
            uv = acc(at["TEXCOORD_0"]).astype(np.float32) if "TEXCOORD_0" in at else cylinder_uv(pos)
            tex = np.full(len(pos), spec["bark"][mat], np.int8)
            bark_parts.append((pos, nrm, uv, tex, tri))
    if leaves:
        cards.append(leaf_clusters(leaves, spec["clusters"], rng))
        if atlas_dir:
            cluster_atlas(name, leaves, spec["clusters"], g, os.path.join(src, spec["asset"]), atlas_dir)
            scan_textures(name, spec, g, os.path.join(src, spec["asset"]), atlas_dir)
    cards = {k: np.concatenate([c[k] for c in cards]) for k in cards[0]}
    cards = thin(cards, spec["cards"], rng)
    # Bark: merged, then decimated.
    off = 0
    pos, nrm, uv, tex, tri = [], [], [], [], []
    for p, n_, u, t, f in bark_parts:
        pos.append(p); nrm.append(n_); uv.append(u); tex.append(t); tri.append(f + off)
        off += len(p)
    pos, nrm, uv, tex, tri = (np.concatenate(x) for x in (pos, nrm, uv, tex, tri))
    if "ground" in spec:
        # Roots modelled under the scan's ground would stand in the air.
        tri = tri[pos[tri][:, :, 1].max(axis=1) > spec["ground"] - 0.25]
    full_bark = (pos, nrm, uv, tex, tri)
    pos, nrm, uv, tex, tri = decimate(pos, nrm, uv, tex, tri, BARK_TRIANGLES[name], MIN_PIECE.get(name, 0.4))
    # The lite bark (the tree between TreeFactory's lite and impostor
    # distances, unshadowed): a tenth of the triangles, only the limbs.
    tall = float(np.ptp(full_bark[0][:, 1]))
    lite = decimate(*full_bark, BARK_TRIANGLES[name] // 10, min(MIN_PIECE.get(name, 0.4) * 6.0, 6.0, tall * 0.3))
    # The tree stands at the origin: its trunk foot (lowest bark, or where
    # the trunk meets the scan's own ground) centred.
    ground = spec.get("ground", float(pos[:, 1].min()))
    foot = pos[np.abs(pos[:, 1] - ground - 0.15) < 0.15]
    shift = np.array([foot[:, 0].mean(), ground, foot[:, 2].mean()], np.float32)
    pos = pos - shift
    cards["centre"] = cards["centre"] - shift
    cc = cards["centre"]
    crown_c = (np.percentile(cc, 2, axis=0) + np.percentile(cc, 98, axis=0)) * 0.5
    crown_r = (np.percentile(cc, 98, axis=0) - np.percentile(cc, 2, axis=0)) * 0.5
    raw = bytearray()
    raw += struct.pack("<6f", *crown_c, *crown_r)
    raw += struct.pack("<II", len(pos), tri.size)
    vert = np.zeros(len(pos), dtype=[("p", "<f2", 3), ("n", "i1", 3), ("t", "i1"), ("uv", "<f2", 2)])
    vert["p"] = pos
    nn = nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-6)
    vert["n"] = np.clip(np.round(nn * 127), -127, 127)
    vert["t"] = tex
    vert["uv"] = uv
    raw += vert.tobytes() + tri.astype("<u4").tobytes()
    n = len(cc)
    card = np.zeros(n, dtype=[("c", "<f2", 3), ("u", "<f2", 3), ("v", "<f2", 3), ("box", "<u2", 4), ("r", "u1"), ("s", "u1")])
    card["c"] = cc
    card["u"] = cards["u"]
    card["v"] = cards["v"]
    card["box"] = np.clip(np.round(np.concatenate([cards["lo"], cards["hi"]], axis=1) * 65535), 0, 65535)
    card["r"] = rng.integers(0, 256, n)
    card["s"] = cards["slot"]
    raw += struct.pack("<I", n) + card.tobytes()
    lp, ln_, lu, lt, ltri = lite
    raw += struct.pack("<II", len(lp), ltri.size)
    lvert = np.zeros(len(lp), dtype=vert.dtype)
    lvert["p"] = lp - shift
    lnn = ln_ / np.maximum(np.linalg.norm(ln_, axis=1, keepdims=True), 1e-6)
    lvert["n"] = np.clip(np.round(lnn * 127), -127, 127)
    lvert["t"] = lt
    lvert["uv"] = lu
    raw += lvert.tobytes() + ltri.astype("<u4").tobytes()
    data = b"OLTREE1\0" + struct.pack("<I", len(raw)) + zlib.compress(bytes(raw), 9)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name + ".oltree")
    with open(path, "wb") as f:
        f.write(data)
    h = pos[:, 1].max()
    print(f"{name}: {len(tri)} bark triangles ({len(ltri)} lite), {n} leaf cards, height {h:.1f} m, {len(data) / 1e6:.2f} MB")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", default=list(SPECS))
    ap.add_argument("--src", required=True, help="folder of Poly Haven glTF downloads, one subfolder per asset")
    ap.add_argument("--out", default=os.path.join(here, "..", "..", "game", "assets", "trees"))
    ap.add_argument("--atlas", help="for the clustered trees, also write their leaf atlas and textures here "
                    "(game/assets/trees/textures)")
    args = ap.parse_args()
    for name in args.names:
        build(name, args.src, args.out, args.atlas)


if __name__ == "__main__":
    sys.exit(main())
