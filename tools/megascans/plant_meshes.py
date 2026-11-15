#!/usr/bin/env python3
"""Bakes the 3D plants of the private Megascans pack (docs/megascans-pack.md):
the real scanned meshes of ferns, grasses, wildflowers and reeds, drawn by
the game near the camera round tees and greens (ScannedPlants), where the
flat plant cards (build_pack.py) read as cut-outs. Never commit the output.

    python3 plant_meshes.py MEGASCANS_DIR PACK_DIR [--only TITLE_WORD]

For each 3D plant in the download's catalogue.json that has LOD meshes, up
to four variants, each with two levels of detail picked from the
Megascans LODs: "near", the most detailed one under NEAR_TRIS triangles,
and "mid", the next one down (the camera-facing billboard LODs are left
out: the plant cards take over further off). Writes

    PACK/foliage/plants/<uid8>.olplant      meshes (see below)
    PACK/foliage/plants/<uid8>_albedo.png   colour, opacity in alpha
    PACK/foliage/plants/<uid8>_normal.png   normal map, translucency in alpha
    PACK/foliage/plants.json                the list ScannedPlants reads

.olplant: b"OLPLANT1", u32 size of the data, then the data deflated:
u32 variants; per variant u32 levels (2); per level u32 vertices, u32
indices, then per vertex 8 float32 (position x y z in metres, +y up, the
plant standing on the origin; normal x y z; uv u v, v down), then the
uint32 indices (triangles, counter-clockwise from the front).

Needs numpy and Pillow. Plants already baked are kept (delete one to redo it).
"""
import json
import os
import re
import struct
import sys
import zlib

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_pack  # noqa: E402
import fbx_mesh  # noqa: E402

NEAR_TRIS = 2600
MID_TRIS = 900
VARIANTS = 4
TEXTURE = 2048
# Plants that don't belong on a temperate course, or are logs, ivy or debris.
SKIP = build_pack.SKIP + ('boston', 'kikuyu', 'basket', 'red fountain', 'ribbon', 'giant reed', 'rubber', 'dead')


def _flat(pos):
    """True for a camera-facing billboard LOD (all in one plane)."""
    flat = pos.reshape(-1, 3)
    return float(np.ptp(flat[:, 2])) < 0.01 or float(np.ptp(flat[:, 0])) < 0.01


def _weld(pos, nor, uv):
    """Indexed vertices from the triangle soup."""
    v = np.concatenate([pos.reshape(-1, 3), nor.reshape(-1, 3), uv.reshape(-1, 2)], axis=1).astype(np.float32)
    key = np.round(v * np.array([1e4] * 3 + [1e3] * 3 + [1e4] * 2)).astype(np.int64)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return v[first], inverse.reshape(-1).astype(np.uint32)


def _levels(files):
    """[near, mid] (pos, nor, uv) of one variant from its LOD files."""
    meshes = []
    for f in sorted(files, key=lambda p: int(re.search(r'LOD(\d)', p).group(1))):
        try:
            m = fbx_mesh.load(f)
        except (ValueError, KeyError, AttributeError) as e:
            print('  skip', os.path.basename(f), e)
            continue
        if len(m[0]) >= 12 and not _flat(m[0]):
            meshes.append(m)
    if not meshes:
        return None
    near = next((m for m in meshes if len(m[0]) <= NEAR_TRIS), None)
    if near is None:
        return None
    rest = [m for m in meshes if len(m[0]) < len(near[0])]
    mid = next((m for m in rest if len(m[0]) <= MID_TRIS), rest[-1] if rest else near)
    return [near, mid]


def _texture(d, names, suffix):
    for n in names:
        if n.endswith('_' + suffix + '.jpg') and 'Billboard' not in n:
            return Image.open(os.path.join(d, n))
    return None


def albedo_luma(img):
    """Mean linear luminance of the opaque texels of an RGBA albedo: the
    scans are shot dark (about 0.03), and the game lifts each plant to the
    course's brightness by it (MegascansPlants)."""
    a = np.asarray(img.resize((256, 256), Image.BILINEAR), dtype=np.float64) / 255.0
    lin = np.where(a[..., :3] <= 0.04045, a[..., :3] / 12.92, ((a[..., :3] + 0.055) / 1.055) ** 2.4)
    y = lin @ np.array([0.2126, 0.7152, 0.0722])
    m = a[..., 3] > 0.5
    return float(y[m].mean()) if m.any() else 0.05


def bake(rec, d, out_dir):
    names = os.listdir(d)
    groups = {}
    for n in names:
        m = re.search(r'_Var([A-Z])_LOD(\d)\.fbx$', n)
        if m:
            groups.setdefault(m.group(1), []).append(os.path.join(d, n))
    variants = []
    for var in sorted(groups)[:VARIANTS * 2]:
        lv = _levels(groups[var])
        if lv is not None:
            variants.append(lv)
        if len(variants) == VARIANTS:
            break
    col = _texture(d, names, 'BaseColor')
    alpha = _texture(d, names, 'Opacity')
    if not variants or col is None or alpha is None:
        return None
    uid8 = rec['uid'][:8]
    blob = bytearray(struct.pack('<I', len(variants)))
    heights, tris = [], []
    for levels in variants:
        blob += struct.pack('<I', len(levels))
        for pos, nor, uv in levels:
            v, idx = _weld(pos, nor, uv)
            blob += struct.pack('<II', len(v), len(idx)) + v.tobytes() + idx.tobytes()
        heights.append(float(levels[0][0][..., 1].max()))
        tris.append([len(levels[0][0]), len(levels[1][0])])
    with open(os.path.join(out_dir, uid8 + '.olplant'), 'wb') as f:
        f.write(b'OLPLANT1' + struct.pack('<I', len(blob)) + zlib.compress(bytes(blob), 9))
    size = (TEXTURE, TEXTURE)
    a = col.convert('RGB').resize(size, Image.LANCZOS)
    # Megascans keeps the opacity mask in one channel (red) of an RGB jpg.
    mask = Image.fromarray(np.asarray(alpha.convert('RGB')).max(axis=2))
    a.putalpha(mask.resize(size, Image.LANCZOS))
    a.save(os.path.join(out_dir, uid8 + '_albedo.png'), optimize=True)
    luma = albedo_luma(a)
    nrm = _texture(d, names, 'Normal')
    tr = _texture(d, names, 'Translucency')
    if nrm is not None:
        n = nrm.convert('RGB').resize(size, Image.LANCZOS)
        t = Image.fromarray(np.asarray(tr.convert('RGB')).max(axis=2)) if tr is not None else Image.new('L', nrm.size, 128)
        n.putalpha(t.resize(size, Image.LANCZOS))
        n.save(os.path.join(out_dir, uid8 + '_normal.png'), optimize=True)
    kind, _h, roles = build_pack.describe(rec)
    return {'uid': uid8, 'title': rec['title'], 'kind': kind, 'height_m': round(float(np.median(heights)), 2),
            'roles': roles, 'variants': len(variants), 'tris': tris, 'file': 'plants/' + uid8,
            'normal': nrm is not None, 'luma': round(luma, 4)}


def main():
    src, pack = sys.argv[1], sys.argv[2]
    only = sys.argv[4].lower() if len(sys.argv) > 4 and sys.argv[3] == '--only' else None
    cat = json.load(open(os.path.join(src, 'catalogue.json')))
    out_dir = os.path.join(pack, 'foliage', 'plants')
    os.makedirs(out_dir, exist_ok=True)
    listing = os.path.join(pack, 'foliage', 'plants.json')
    known = {}
    if os.path.exists(listing):
        known = {p['uid']: p for p in json.load(open(listing)).get('plants', [])}
    plants = []
    for rec in cat:
        title = rec['title'].lower()
        if rec.get('use') != 'plant_mesh' or any(w in title for w in SKIP):
            continue
        if only and only not in title:
            continue
        d = os.path.join(src, rec['dir'])
        if not os.path.isdir(d):
            continue
        uid8 = rec['uid'][:8]
        if uid8 in known and os.path.exists(os.path.join(out_dir, uid8 + '.olplant')):
            p = known[uid8]
            if 'luma' not in p:
                p['luma'] = round(albedo_luma(Image.open(os.path.join(out_dir, uid8 + '_albedo.png'))), 4)
            plants.append(p)
            continue
        p = bake(rec, d, out_dir)
        if p is None:
            print('no meshes:', rec['title'])
            continue
        plants.append(p)
        print('%-24s %-6s %.2f m  %d variants  tris %s' % (p['title'], p['kind'], p['height_m'], p['variants'], p['tris']))
    with open(listing, 'w') as f:
        json.dump({'source': 'Quixel Megascans (private pack, never redistribute)', 'plants': plants}, f, indent=1)
    print(len(plants), 'plants')


if __name__ == '__main__':
    main()
