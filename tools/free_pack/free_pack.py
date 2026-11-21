#!/usr/bin/env python3
"""The free pack (docs/free-pack.md): CC0 stand-ins, from Poly Haven and
ambientCG, for everything the private Megascans pack gives the desktop game
(docs/megascans-pack.md), in the same layout, so every desktop build has
scanned rocks, 3D plants round the tees and greens, woodland debris and
scanned surfaces. The game reads it from res://free_assets/pack/ wherever the
private pack lacks a part (FreeAssets.pack_dir).

Two steps:

    python3 tools/free_pack/free_pack.py bake [--godot GODOT] [--cache DIR]

downloads the models and cuts their meshes down with Godot's own simplifier
(tools/free_pack/bake_meshes.gd) into tools/free_pack/baked/: small mesh
files and the manifests, committed (they're CC0). Run it again only to
change what's in the pack. Then tools/fetch_free_assets.py calls fetch(),
which copies baked/ into the game and downloads and prepares the textures
the manifests name (not committed, like the other free textures).

Everything here is CC0, so it may be in the public repository and builds.
"""
import argparse
import io
import json
import os
import shutil
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
BAKED = os.path.join(HERE, "baked")
API = "https://api.polyhaven.com"
AMBIENTCG = "https://ambientcg.com"
USER_AGENT = "OpenLinks2003-asset-fetch (https://github.com/crspytopgn/openlinks2003)"

# Rocks for RockField (Poly Haven models): asset -> (kind, pieces). A set
# holds several rocks; up to `pieces` of them are kept, each its own rock
# sharing the set's textures. Kinds as RockField.STYLES reads them.
ROCKS = {
    "boulder_01": ("upland", 1),
    "rock_face_02": ("upland", 1),
    "rock_moss_set_01": ("woodland", 4),
    "rock_moss_set_02": ("woodland", 4),
    "namaqualand_boulder_02": ("sandstone", 1),
    "namaqualand_boulder_03": ("sandstone", 1),
    "namaqualand_boulder_04": ("sandstone", 1),
    "namaqualand_boulder_05": ("sandstone", 1),
    "namaqualand_boulder_06": ("sandstone", 1),
    "rock_face_01": ("dry_outcrop", 1),
    "namaqualand_cliff_01": ("dry_outcrop", 1),
    "coast_rocks_05": ("shore", 1),
    "sand_rocks_small_01": ("shore", 1),
    "coast_land_rocks_02": ("shore_outcrop", 1),
}
ROCK_TRIS = 3000  # the most detailed level; Godot makes the rest

# 3D plants for ScannedPlants: asset -> (title, kind, roles). The title
# picks the plant's group (MegascansPlants.GROUPS).
PLANTS = {
    "fern_02": ("Fern", "fern", ["woodland_edge"]),
    "grass_medium_01": ("Wild Grass", "grass", ["meadow", "deep_rough"]),
    "grass_bermuda_01": ("Bermuda Grass", "grass", ["meadow"]),
    "dandelion_01": ("Dandelion", "flower", ["meadow"]),
    "nettle_plant": ("Nettle", "flower", ["woodland_edge"]),
    "celandine_01": ("Celandine Buttercup", "flower", ["meadow", "woodland_edge"]),
    "shrub_sorrel_01": ("Wood Sorrel Clover", "flower", ["woodland_edge"]),
    "cheiridopsis_succulent": ("Succulent Cheiridopsis", "succulent", ["desert"]),
    "crystalline_iceplant": ("Succulent Iceplant", "succulent", ["desert", "dune"]),
    "flower_gazania": ("Desert Gazania", "succulent", ["desert"]),
}
NEAR_TRIS = 2400
MID_TRIS = 700
VARIANTS = 4

# Woodland-floor props for DebrisField: asset -> (kind, under, tris, max_h).
DEBRIS = {
    "tree_stump_01": ("stump", "conifer", 2500, 0.9),
    "tree_stump_02": ("stump", "any", 2500, 0.9),
    "dead_tree_trunk": ("log", "any", 2500, 0.7),
    "dead_tree_trunk_02": ("log", "broadleaf", 2500, 0.7),
    "dry_branches_medium_01": ("pine_branches", "conifer", 2000, 0.0),
    "bark_debris_01": ("twigs", "any", 800, 0.0),
}
# The litter atlases (Poly Haven textures, with their real size in m).
LITTER = {
    "leaves": [("forest_leaves_03", 2.3), ("forest_leaves_04", 1.5), ("dry_decay_leaves", 2.0), ("forest_leaves_02", 3.0)],
    "needles": [("forrest_ground_03", 2.0), ("forrest_ground_03", 2.0), ("forrest_sand_01", 2.0), ("forrest_ground_03", 2.0)],
}
LITTER_CELL = 512

# Scanned surfaces for ScannedSurfaces: slot -> (source, asset, size_m).
SURFACES = {
    "path": ("polyhaven", "clean_asphalt", 2.1),
    "path@us": ("ambientcg", "Concrete034", 2.0),
    "path@desert": ("ambientcg", "Concrete034", 2.0),
    "path@tropical": ("ambientcg", "Concrete034", 2.0),
    "deck": ("ambientcg", "Planks023A", 0.85),
    "timber": ("ambientcg", "Planks023A", 0.85),
    "deck@us": ("ambientcg", "Planks011", 2.24),
    "timber@us": ("ambientcg", "Planks011", 2.24),
    "deck@tropical": ("ambientcg", "Planks037A", 2.2),
    "timber@tropical": ("ambientcg", "Planks037A", 2.2),
    "bench": ("ambientcg", "Wood060", 0.5),
}

# Texture sizes in the pack (px): the desktop download stays small.
ALBEDO_PX = 1024
NORMAL_PX = 512
ROUGH_PX = 256


def get(url, retries=4):
    import time
    import urllib.request
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 - network errors of every kind are retried
            if attempt == retries - 1:
                raise
            print(f"  retrying {url}: {e}")
            time.sleep(2 ** (attempt + 1))
    return b""


def get_json(url):
    return json.loads(get(url))


def download_model(cache, asset):
    """The asset's glTF (1k) and its buffers into cache/<asset>/, with the
    images and materials taken out (only the meshes are baked). Returns the
    .gltf path."""
    d = os.path.join(cache, asset)
    path = os.path.join(d, asset + ".gltf")
    if os.path.exists(path):
        return path
    os.makedirs(d, exist_ok=True)
    entry = get_json(f"{API}/files/{asset}")["gltf"]["1k"]["gltf"]
    for name, inc in entry.get("include", {}).items():
        if name.endswith(".bin"):
            print(f"  {asset}: {name}")
            with open(os.path.join(d, name), "wb") as f:
                f.write(get(inc["url"]))
    g = json.loads(get(entry["url"]))
    for key in ("images", "textures", "samplers", "materials"):
        g.pop(key, None)
    for m in g.get("meshes", []):
        for p in m.get("primitives", []):
            p.pop("material", None)
    with open(path, "w") as f:
        json.dump(g, f)
    return path


# ---------------------------------------------------------------- bake


def bake(godot, cache):
    """Downloads the models, cuts their meshes into baked/ and writes the
    manifests there."""
    jobs = []
    for asset, (kind, pieces) in ROCKS.items():
        jobs.append({"kind": "rock", "asset": asset, "gltf": download_model(cache, asset), "pieces": pieces, "tris": ROCK_TRIS})
    for asset in PLANTS:
        jobs.append({"kind": "plant", "asset": asset, "gltf": download_model(cache, asset), "variants": VARIANTS,
                     "near": NEAR_TRIS, "mid": MID_TRIS})
    for asset, (kind, under, tris, max_h) in DEBRIS.items():
        jobs.append({"kind": "debris", "asset": asset, "gltf": download_model(cache, asset), "tris": tris, "max_h": max_h})
    if os.path.isdir(BAKED):
        shutil.rmtree(BAKED)
    os.makedirs(BAKED)
    jobs_path = os.path.join(cache, "jobs.json")
    with open(jobs_path, "w") as f:
        json.dump(jobs, f)
    run = subprocess.run([godot, "--headless", "-s", os.path.join(HERE, "bake_meshes.gd"), "--", jobs_path, BAKED],
                         capture_output=True, text=True)
    baked = [json.loads(line[6:]) for line in run.stdout.splitlines() if line.startswith("BAKED ")]
    if not baked:
        sys.exit(run.stdout + run.stderr)
    rocks, plants, props = [], [], []
    for b in baked:
        a = b["asset"]
        if b["kind"] == "rock":
            rocks.append({"id": b["id"], "title": a, "size": [round(v, 3) for v in b["size"]], "kind": ROCKS[a][0], "tex": a,
                          "ext": "webp"})
        elif b["kind"] == "plant":
            title, kind, roles = PLANTS[a]
            plants.append({"uid": a, "title": title, "kind": kind, "height_m": round(b["height_m"], 3), "roles": roles,
                           "variants": b["variants"], "file": "plants/" + a, "ext": "webp", "normal": True,
                           "luma": round(plant_luma(a), 4)})
        else:
            kind, under, _, _ = DEBRIS[a]
            cut = "Alpha" in model_maps(a)
            props.append({"uid": a, "title": a, "kind": kind, "under": under, "mesh": "debris/%s.olmesh" % a,
                          "albedo": "debris/%s.webp" % a, "normal": "debris/%s_n.webp" % a,
                          "cutout": cut})
        print("  baked", b)
    source = "Poly Haven and ambientCG (CC0), see docs/free-pack.md"
    write_json(os.path.join(BAKED, "rocks", "rocks.json"), {"source": source, "rocks": rocks})
    write_json(os.path.join(BAKED, "foliage", "plants.json"), {"source": source, "plants": plants})
    litter = {k: {"albedo": "debris/litter_%s.webp" % k, "normal": "debris/litter_%s_n.webp" % k, "size_m": 2.5} for k in LITTER}
    write_json(os.path.join(BAKED, "debris", "debris.json"), {"source": source, "litter": litter, "props": props})
    slots = {}
    for slot, (src, asset, size) in SURFACES.items():
        slots[slot] = {"title": asset, "size_m": size, "albedo": asset + "_albedo.webp", "normal": asset + "_normal.webp",
                       "roughness": asset + "_roughness.webp"}
    write_json(os.path.join(BAKED, "surfaces", "surfaces.json"), {"source": source, "slots": slots})


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=1)


_maps = {}


def model_maps(asset):
    """Poly Haven's files list for an asset (cached)."""
    if asset not in _maps:
        _maps[asset] = get_json(f"{API}/files/{asset}")
    return _maps[asset]


def ph_map(asset, key, res="1k"):
    """One of an asset's maps (Diffuse, nor_gl, Rough, AO, Alpha...) as a
    Pillow image, or None when it has none."""
    from PIL import Image
    files = model_maps(asset).get(key)
    if not files:
        return None
    entry = files.get(res) or files[sorted(files)[0]]
    fmt = "png" if "png" in entry else "jpg"
    return Image.open(io.BytesIO(get(entry[fmt]["url"])))


def plant_luma(asset):
    """Mean linear luminance of a plant's leaves (where opaque), as
    MegascansPlants evens the scans' exposure by it."""
    import numpy as np
    col = np.asarray(ph_map(asset, "Diffuse").convert("RGB").resize((256, 256)), np.float32) / 255.0
    alpha = ph_map(asset, "Alpha")
    a = np.asarray(alpha.convert("L").resize((256, 256)), np.float32) / 255.0 if alpha else np.ones((256, 256), np.float32)
    lin = np.where(col <= 0.04045, col / 12.92, ((col + 0.055) / 1.055) ** 2.4)
    lum = lin @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    return float((lum * a).sum() / max(a.sum(), 1.0))


# ---------------------------------------------------------------- fetch

# Written next to every pack file before the project is imported: exported
# as it is (the game reads the files itself, as it does the private pack's).
KEEP_IMPORT = '[remap]\n\nimporter="keep"\n'


def _save(img, path, size, kind="webp"):
    """`img` at `size` px wide (square maps) as WebP (alpha kept), or JPEG."""
    from PIL import Image
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if img.width != size:
        img = img.resize((size, size * img.height // img.width), Image.LANCZOS)
    if kind == "webp":
        img.save(path, "WEBP", quality=82, method=6)
    else:
        img.convert("RGB" if img.mode not in ("L",) else "L").save(path, "JPEG", quality=85, optimize=True)


def _with_alpha(col, alpha):
    from PIL import Image
    col = col.convert("RGB")
    if alpha is None:
        return col
    a = alpha.convert("L")
    if a.size != col.size:
        a = a.resize(col.size, Image.LANCZOS)
    out = col.copy()
    out.putalpha(a)
    return out


def _ao(col, ao):
    """The colour with the scan's ambient occlusion multiplied in (softly)."""
    import numpy as np
    from PIL import Image
    if ao is None:
        return col
    c = np.asarray(col.convert("RGB"), np.float32) / 255.0
    a = np.asarray(ao.convert("L").resize(col.size, Image.LANCZOS), np.float32) / 255.0
    return Image.fromarray(np.clip(c * (0.65 + 0.35 * a)[..., None] * 255.0, 0, 255).astype(np.uint8))


def fetch(out_dir):
    """The free pack in `out_dir` (res://free_assets/pack/): baked/ copied
    in, and the textures its manifests name downloaded and prepared.
    Returns the credit lines. Needs numpy and Pillow."""
    if not os.path.isdir(BAKED):
        raise RuntimeError("no baked free pack (run free_pack.py bake)")
    marker = os.path.join(out_dir, ".done")
    stamp = json.dumps(sorted(os.path.relpath(os.path.join(r, f), BAKED) for r, _, fs in os.walk(BAKED) for f in fs))
    if not (os.path.exists(marker) and open(marker).read() == stamp):
        if os.path.isdir(out_dir):
            shutil.rmtree(out_dir)
        shutil.copytree(BAKED, out_dir)
        _fetch_rocks(out_dir)
        _fetch_plants(out_dir)
        _fetch_debris(out_dir)
        _fetch_surfaces(out_dir)
        with open(marker, "w") as f:
            f.write(stamp)
    for root, _, files in os.walk(out_dir):
        for name in files:
            if not name.endswith((".import", ".res")) and not name.startswith("."):
                with open(os.path.join(root, name) + ".import", "w") as f:
                    f.write(KEEP_IMPORT)
    credits = []
    for asset in list(ROCKS) + list(PLANTS) + list(DEBRIS) + sorted({a for cells in LITTER.values() for a, _ in cells}):
        credits.append(f"- **free pack**: [{asset}](https://polyhaven.com/a/{asset}) by Poly Haven, CC0")
    for src, asset in sorted({(v[0], v[1]) for v in SURFACES.values()}):
        url = f"https://polyhaven.com/a/{asset}" if src == "polyhaven" else f"{AMBIENTCG}/view?id={asset}"
        credits.append(f"- **free pack surface**: [{asset}]({url}) by {'Poly Haven' if src == 'polyhaven' else 'ambientCG'}, CC0")
    return credits


def _fetch_rocks(out):
    for asset in ROCKS:
        print(f"  free pack: rock {asset}")
        d = os.path.join(out, "rocks", asset)
        _save(ph_map(asset, "Diffuse").convert("RGB"), d + "_albedo.webp", ALBEDO_PX)
        _save(ph_map(asset, "nor_gl").convert("RGB"), d + "_normal.webp", NORMAL_PX)
        rough = ph_map(asset, "Rough")
        if rough is not None:
            _save(rough.convert("RGB"), d + "_rough.webp", ROUGH_PX)


def _fetch_plants(out):
    for asset in PLANTS:
        print(f"  free pack: plant {asset}")
        d = os.path.join(out, "foliage", "plants", asset)
        _save(_with_alpha(ph_map(asset, "Diffuse"), ph_map(asset, "Alpha")), d + "_albedo.webp", ALBEDO_PX, "webp")
        _save(ph_map(asset, "nor_gl").convert("RGB"), d + "_normal.webp", NORMAL_PX, "webp")


def _fetch_debris(out):
    for asset in DEBRIS:
        print(f"  free pack: debris {asset}")
        d = os.path.join(out, "debris", asset)
        alpha = ph_map(asset, "Alpha")
        col = _ao(ph_map(asset, "Diffuse"), ph_map(asset, "AO"))
        _save(_with_alpha(col, alpha), d + ".webp", ALBEDO_PX)
        _save(ph_map(asset, "nor_gl").convert("RGB"), d + "_n.webp", NORMAL_PX)
    _fetch_litter(out)


def _fetch_litter(out):
    """The two litter atlases, as the Megascans baker makes them
    (tools/megascans/debris_pack.py litter_cell): 2 x 2 patches 2.5 m
    across, each with a ragged edge that follows the scan's height."""
    import tempfile
    import numpy as np
    from PIL import Image
    sys.path.insert(0, os.path.join(HERE, "..", "megascans"))
    import debris_pack  # noqa: E402 - numpy and Pillow, only here
    debris_pack.CELL = LITTER_CELL
    cell = LITTER_CELL
    with tempfile.TemporaryDirectory() as tmp:
        for kind, cells in LITTER.items():
            print(f"  free pack: {kind} litter")
            rng = np.random.default_rng(len(kind) * 7919)
            atlas = np.zeros((cell * 2, cell * 2, 4), np.float32)
            natlas = np.zeros((cell * 2, cell * 2, 3), np.float32)
            for i, (asset, tile_m) in enumerate(cells):
                d = os.path.join(tmp, asset)
                if not os.path.isdir(d):
                    os.makedirs(d)
                    files = get_json(f"{API}/files/{asset}")
                    for key, name in (("Diffuse", "BaseColor"), ("nor_gl", "Normal"), ("Displacement", "Displacement")):
                        if key in files:
                            with open(os.path.join(d, f"{asset}_{name}.jpg"), "wb") as f:
                                f.write(get(files[key]["1k"]["jpg"]["url"]))
                c, n = debris_pack.litter_cell(d, tile_m, rng)
                y0, x0 = (i // 2) * cell, (i % 2) * cell
                atlas[y0:y0 + cell, x0:x0 + cell] = c
                natlas[y0:y0 + cell, x0:x0 + cell] = n
            base = os.path.join(out, "debris", "litter_" + kind)
            Image.fromarray((atlas * 255).astype(np.uint8), "RGBA").save(base + ".webp", "WEBP", quality=82, method=6)
            Image.fromarray((natlas * 255).astype(np.uint8), "RGB").save(base + "_n.webp", "WEBP", quality=82, method=6)


def _fetch_surfaces(out):
    from PIL import Image
    got = {}
    for slot, (src, asset, _) in SURFACES.items():
        if asset not in got:
            print(f"  free pack: surface {asset}")
            if src == "polyhaven":
                got[asset] = {"albedo": ph_map(asset, "Diffuse"), "normal": ph_map(asset, "nor_gl"), "roughness": ph_map(asset, "Rough")}
            else:
                maps = {}
                with zipfile.ZipFile(io.BytesIO(get(f"{AMBIENTCG}/get?file={asset}_1K-JPG.zip"))) as z:
                    for key, suffix in (("albedo", "_Color.jpg"), ("normal", "_NormalGL.jpg"), ("roughness", "_Roughness.jpg")):
                        member = next((m for m in z.namelist() if m.endswith(suffix)), None)
                        if member:
                            maps[key] = Image.open(io.BytesIO(z.read(member)))
                got[asset] = maps
        for key, px in (("albedo", ALBEDO_PX), ("normal", NORMAL_PX), ("roughness", ROUGH_PX)):
            img = got[asset].get(key)
            path = os.path.join(out, "surfaces", f"{asset}_{key}.webp")
            if img is not None and not os.path.exists(path):
                _save(img.convert("RGB"), path, px)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", choices=["bake", "fetch"])
    ap.add_argument("--godot", default=shutil.which("godot") or "godot")
    ap.add_argument("--cache", default=os.path.join(HERE, ".cache"))
    ap.add_argument("--out", default=os.path.join(HERE, "..", "..", "game", "free_assets", "pack"))
    args = ap.parse_args()
    if args.step == "bake":
        bake(args.godot, args.cache)
    else:
        print("\n".join(fetch(args.out)))


if __name__ == "__main__":
    main()
