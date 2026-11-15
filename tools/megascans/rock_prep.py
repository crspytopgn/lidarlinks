#!/usr/bin/env python3
"""Pick Megascans rock scans and shrink their maps for rock_pack.gd.

    python3 rock_prep.py MEGASCANS_DIR OUT_DIR

Takes a few of each kind from MEGASCANS_DIR/rocks/3d-model (WANT below) and
writes OUT_DIR/<folder>/ with mesh.fbx (the _High FBX), albedo.jpg,
normal.jpg and rough.jpg at 2048 px, and meta.json with the scan's size.
Private pack only (docs/megascans-pack.md): never commit the output.
"""
import glob
import json
import os
import re
import shutil
import sys

from PIL import Image

Image.MAX_IMAGE_PIXELS = None
WANT = {"Sandstone_Boulder": 6, "Beach_Boulder": 5, "Mossy_Forest_Boulder": 5, "Forest_Boulder": 2,
        "Lichened_Forest_Boulder": 2, "Mossy_Boulder": 2, "Small_Forest_Boulder": 1,
        "Beach_Rock_Formation": 2, "Beach_Cliff": 2, "Huge_Layered_Boulder": 1,
        "Grassland_Pakistani_Rock_Boulder_Stone_Large_20": 1,
        "Grassland_Pakistani_Rock_Boulder_Stone_Medium_09": 1,
        "Grassland_Pakistani_Rock_Boulder_Stone_Small_10": 1, "Scattered_Beach_Rocks": 1}
MAPS = (("BaseColor", "albedo", "RGB"), ("Normal", "normal", "RGB"), ("Roughness", "rough", "L"))


def main():
    src, out = sys.argv[1], sys.argv[2]
    done = {}
    for d in sorted(glob.glob(os.path.join(src, "rocks", "3d-model", "*"))):
        title = re.sub(r"_[0-9a-f]{8}$", "", os.path.basename(d))
        fbx = sorted((f for f in os.listdir(d) if f.endswith(".fbx")), key=lambda f: ("High" not in f, f))
        if done.get(title, 0) >= WANT.get(title, 0) or not fbx:
            continue
        o = os.path.join(out, os.path.basename(d))
        os.makedirs(o, exist_ok=True)
        meta = json.load(open(glob.glob(os.path.join(d, "*.json"))[0]))
        dims = {m["key"]: m["value"] for m in meta.get("meta", []) if m.get("key") in ("height", "width", "length")}
        json.dump({"title": title, "dims": dims, "fbx": fbx[0]}, open(os.path.join(o, "meta.json"), "w"))
        shutil.copy(os.path.join(d, fbx[0]), os.path.join(o, "mesh.fbx"))
        for key, name, mode in MAPS:
            hit = [f for f in os.listdir(d) if f.endswith("_%s.jpg" % key) and "LOD" not in f]
            if hit:
                img = Image.open(os.path.join(d, hit[0])).convert(mode).resize((2048, 2048), Image.LANCZOS)
                img.save(os.path.join(o, name + ".jpg"), quality=90)
        done[title] = done.get(title, 0) + 1
        print(os.path.basename(d), dims)


if __name__ == "__main__":
    main()
