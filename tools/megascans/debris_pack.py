#!/usr/bin/env python3
"""Bakes the woodland-floor debris of the private Megascans pack
(docs/megascans-pack.md): leaf and needle litter patches, leaf piles, fallen
pine branches, cones, twigs, logs and stumps for the ground under tree lines
(DebrisField). Never commit the output.

    python3 debris_pack.py MEGASCANS_DIR PACK_DIR
    godot --headless --path game -s tools/megascans/debris_meshes.gd -- PACK_DIR

The first step writes the textures and PACK/debris/debris.json; the second
reads the scans' FBX meshes (the list in PACK/debris/mesh_jobs.json), cuts
them down to a game-sized triangle count and writes PACK/debris/<id>.olmesh.
MEGASCANS_DIR is the Megascans download with its catalogue.json (or any
folder holding the same <Title>_<uid8> asset folders, found by name). Needs
numpy and Pillow.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
CELL = 1024  # px per litter patch in the 2 x 2 atlases
PROP_TEX = 1024  # px per prop texture
# The litter atlases: four patches each, from these surface scans (title,
# uid8, the scan's size in metres). A patch is PATCH_M across.
PATCH_M = 2.5
LITTER_LUMA = 0.32
LITTER = {
    'leaves': [('Dry Fallen Leaves', '6984772c', 2.0), ('Fallen Leaves', 'ba04f3c3', 1.0),
               ('Fallen Oak Leaves', 'ef487f44', 4.0), ('Dry Fallen Leaves', '6984772c', 2.0)],
    'needles': [('Pine Forest Floor', '470a0512', 2.0), ('Fallen Pine Needles', '7603ba66', 2.0),
                ('Pine Forest Floor', '470a0512', 2.0), ('Fallen Pine Needles', '7603ba66', 2.0)],
}
# The props, by title: kind, the trees it lies under (broadleaf, conifer
# or any) and the triangle count it is cut down to. Every scan with the
# title is used. Picked by eye from the download; Tree Log (a bark strip),
# the burnt, snowy and Australian ones are left out.
PROPS = {
    'Dead Leaves': ('leaves', 'broadleaf', 700),
    'Fallen Pine Branches': ('pine_branches', 'conifer', 3000),
    'Pine Wood Debris': ('twigs', 'conifer', 500),
    'Small Pine Cones': ('cones', 'conifer', 220),
    'Dead Oak Branch': ('twigs', 'broadleaf', 900),
    'Oak Branch': ('twigs', 'broadleaf', 900),
    'Dead Pine Branch': ('twigs', 'conifer', 900),
    'Fallen Log': ('log', 'any', 2500),
    'Mossy Log': ('log', 'broadleaf', 1500),
    'Rotten Log': ('log', 'any', 1800),
    'Oak Tree Log': ('log', 'broadleaf', 2500),
    'Eroded Pine Log': ('log', 'conifer', 1500),
    'Mossy Tree Log': ('log', 'broadleaf', 3000),
    'Mossy Stump': ('stump', 'broadleaf', 2500),
    'Old Tree Stump': ('stump', 'broadleaf', 2500),
    'Pine Tree Stump': ('stump', 'conifer', 2500),
    'Rotten Tree Stump': ('stump', 'any', 2500),
    'Spruce Tree Stump': ('stump', 'conifer', 2500),
    'Tree Stump': ('stump', 'any', 3000),
    'Broken Pine Stump': ('stump', 'conifer', 2500),
    'Mossy Pine Stump': ('stump', 'conifer', 2500),
}


# The tallest a prop of a kind may stand (m); taller scans are scaled down.
MAX_H = {'stump': 0.9, 'log': 0.7}


def find_map(d, name):
    for n in sorted(os.listdir(d)):
        if n.endswith('_%s.jpg' % name) and 'Billboard' not in n:
            return os.path.join(d, n)
    return None


def load(path, size, mode):
    im = Image.open(path)
    im.draft(None, (size, size))
    return np.asarray(im.convert(mode).resize((size, size), Image.LANCZOS), dtype=np.float32) / 255.0


def asset_dirs(src):
    """{(title, uid8): dir} for every asset folder in the download."""
    out = {}
    cat = os.path.join(src, 'catalogue.json')
    if os.path.exists(cat):
        for rec in json.load(open(cat)):
            out[(rec['title'], rec['uid'][:8])] = os.path.join(src, rec['dir'])
    else:
        for root, dirs, _ in os.walk(src):
            for d in dirs:
                title, _, uid8 = d.rpartition('_')
                out[(title.replace('_', ' '), uid8)] = os.path.join(root, d)
    return {k: v for k, v in out.items() if os.path.isdir(v)}


def noise(rng, size, octaves=4):
    """Smooth value noise in 0..1, size x size."""
    acc = np.zeros((size, size), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = 4 * 2 ** o
        g = Image.fromarray((rng.random((n, n)) * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
        acc += amp * np.asarray(g, np.float32) / 255.0
        total += amp
        amp *= 0.5
    return acc / total


def litter_cell(d, tile_m, rng):
    """One patch: RGBA albedo and its normal map, PATCH_M across. The scan is
    tiled to scale; the patch's edge is a ragged blob whose border follows
    the scan's displacement, so only the top leaves or needles reach out
    and the edge breaks up along leaf shapes, as real litter thins out."""
    reps = PATCH_M / tile_m
    n = max(1, int(np.ceil(reps)))
    def tiled(name, mode):
        img = load(find_map(d, name), CELL, mode)
        big = np.tile(img, (n, n, 1) if img.ndim == 3 else (n, n))
        px = int(round(CELL * reps))
        ox, oy = rng.integers(0, max(1, big.shape[1] - px + 1)), rng.integers(0, max(1, big.shape[0] - px + 1))
        cut = big[oy:oy + px, ox:ox + px]
        cut = np.clip(cut * 255, 0, 255).astype(np.uint8)
        return np.asarray(Image.fromarray(cut).resize((CELL, CELL), Image.LANCZOS), np.float32) / 255.0
    col = tiled('BaseColor', 'RGB')
    # Every patch to the same mean brightness, so a dark scan (Fallen Oak
    # Leaves) doesn't read as a hole in the shade.
    col = np.clip(col * (LITTER_LUMA / max(float((col @ [0.2126, 0.7152, 0.0722]).mean()), 1e-3)), 0.0, 1.0)
    nrm = tiled('Normal', 'RGB')
    disp = tiled('Displacement', 'L') if find_map(d, 'Displacement') else np.full((CELL, CELL), 0.5, np.float32)
    disp = (disp - disp.mean()) / max(disp.std(), 1e-3)
    y, x = (np.mgrid[0:CELL, 0:CELL] + 0.5) / CELL * 2.0 - 1.0
    stretch = rng.uniform(1.0, 1.25)
    r = np.sqrt((x * stretch) ** 2 + (y / stretch) ** 2)
    ang = np.arctan2(y, x)
    # A lumpy outline: the radius wobbles with angle, then fine noise.
    wob = sum(rng.uniform(0.05, 0.12) * np.cos(k * ang + rng.uniform(0, 6.3)) for k in (2, 3, 5, 7))
    edge = 0.72 + wob + (noise(rng, CELL) - 0.5) * 0.6
    inside = (edge - r) / 0.3  # 1 well inside, 0 at the outline
    # Thin in places inside too, so the turf shows through in gaps.
    holes = (noise(rng, CELL, 5) - 0.5) * 2.0
    # Fine-grained too: single leaves and needles stand apart near the edge.
    alpha = np.clip(inside * 1.3 + disp * 0.8 + holes * 0.6 - 0.45, 0.0, 1.0)
    alpha[r > 0.98] = 0.0
    return np.dstack([col, alpha]), nrm


def bake_litter(src_dirs, pack):
    out = {}
    for kind, cells in LITTER.items():
        rng = np.random.default_rng(len(kind) * 7919)
        atlas = np.zeros((CELL * 2, CELL * 2, 4), np.float32)
        natlas = np.zeros((CELL * 2, CELL * 2, 3), np.float32)
        natlas[..., 0:2] = 0.5
        natlas[..., 2] = 1.0
        ok = 0
        for i, (title, uid8, tile_m) in enumerate(cells):
            d = src_dirs.get((title, uid8))
            if d is None or not find_map(d, 'BaseColor') or not find_map(d, 'Normal'):
                print('litter: missing', title, uid8)
                continue
            c, n = litter_cell(d, tile_m, rng)
            y0, x0 = (i // 2) * CELL, (i % 2) * CELL
            atlas[y0:y0 + CELL, x0:x0 + CELL] = c
            natlas[y0:y0 + CELL, x0:x0 + CELL] = n
            ok += 1
        if ok == 0:
            continue
        a = 'debris/litter_%s.png' % kind
        nm = 'debris/litter_%s_n.jpg' % kind
        Image.fromarray((atlas * 255).astype(np.uint8), 'RGBA').save(os.path.join(pack, a))
        Image.fromarray((natlas * 255).astype(np.uint8), 'RGB').save(os.path.join(pack, nm), quality=92)
        out[kind] = {'albedo': a, 'normal': nm, 'size_m': PATCH_M}
        print('litter', kind, ok, 'patches')
    return out


def bake_prop_textures(d, uid8, pack):
    """The prop's albedo (AO multiplied in, opacity as alpha where the scan
    has one) and normal map, PROP_TEX square."""
    col = load(find_map(d, 'BaseColor'), PROP_TEX, 'RGB')
    ao_p = find_map(d, 'AO')
    if ao_p:
        col *= (0.65 + 0.35 * load(ao_p, PROP_TEX, 'L'))[..., None]
    op_p = find_map(d, 'Opacity')
    albedo = 'debris/%s.png' % uid8 if op_p else 'debris/%s.jpg' % uid8
    if op_p:
        rgba = np.dstack([col, load(op_p, PROP_TEX, 'L')])
        Image.fromarray((rgba * 255).astype(np.uint8), 'RGBA').save(os.path.join(pack, albedo))
    else:
        Image.fromarray((col * 255).astype(np.uint8), 'RGB').save(os.path.join(pack, albedo), quality=92)
    normal = 'debris/%s_n.jpg' % uid8
    Image.open(find_map(d, 'Normal')).convert('RGB').resize((PROP_TEX, PROP_TEX), Image.LANCZOS).save(os.path.join(pack, normal), quality=92)
    return albedo, normal, bool(op_p)


def main():
    src, pack = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(pack, 'debris'), exist_ok=True)
    dirs = asset_dirs(src)
    litter = bake_litter(dirs, pack)
    props, jobs = [], []
    for (title, uid8), d in sorted(dirs.items()):
        if title not in PROPS:
            continue
        kind, under, tris = PROPS[title]
        fbx = sorted(n for n in os.listdir(d) if n.endswith('.fbx'))
        # Plant scans ship LOD meshes per variant: take LOD1 of each.
        lods = [n for n in fbx if 'LOD1' in n]
        fbx = lods or [n for n in fbx if 'LOD' not in n]
        if not fbx or not find_map(d, 'BaseColor') or not find_map(d, 'Normal'):
            continue
        albedo, normal, cutout = bake_prop_textures(d, uid8, pack)
        for i, name in enumerate(fbx):
            mesh = 'debris/%s_%d.olmesh' % (uid8, i)
            jobs.append({'fbx': os.path.abspath(os.path.join(d, name)), 'out': mesh, 'tris': tris,
                         'split': kind == 'cones', 'max_h': MAX_H.get(kind, 0.0)})
            props.append({'uid': '%s_%d' % (uid8, i), 'title': title, 'kind': kind, 'under': under,
                          'mesh': mesh, 'albedo': albedo, 'normal': normal, 'cutout': cutout})
        print('%-22s %-13s %-9s %d mesh(es)' % (title, kind, under, len(fbx)))
    with open(os.path.join(pack, 'debris', 'mesh_jobs.json'), 'w') as f:
        json.dump(jobs, f, indent=1)
    with open(os.path.join(pack, 'debris', 'debris.json'), 'w') as f:
        json.dump({'source': 'Quixel Megascans (private pack, never redistribute)',
                   'litter': litter, 'props': props}, f, indent=1)
    print(len(props), 'props; now run debris_meshes.gd on', pack)


if __name__ == '__main__':
    main()
