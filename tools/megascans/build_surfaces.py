#!/usr/bin/env python3
"""Bake scanned surfaces into the private Megascans pack's surfaces/ folder
(docs/megascans-pack.md), read in the game by ScannedSurfaces.

    python3 build_surfaces.py PACK_DIR SLOT=SOURCE_DIR[@SIZE_M] ...

SLOT is one of path, deck, timber, bench, optionally for one region of
the world as SLOT@REGION (uk, europe, us, desert, tropical, south; see
ScannedSurfaces.REGION_BOXES), which wins over the plain slot there.
SOURCE_DIR is a Megascans
surface folder (its JSON gives the scan's real size) or any folder of PBR
maps named *_BaseColor/*_Color, *_Normal/*_NormalGL and *_Roughness (such as
an ambientCG download, whose real size you give as @SIZE_M). Normal maps
must be OpenGL style (green up): Megascans' and ambientCG's NormalGL are.
For deck and timber the boards must run along the image's x, and for bench
the grain. Each map is written at 1024 px, the size in metres to
surfaces.json. Needs Pillow. The output is never to be committed or shared.
"""

import glob
import json
import os
import re
import sys

from PIL import Image

Image.MAX_IMAGE_PIXELS = None
SLOTS = ("path", "deck", "timber", "bench")
REGIONS = ("uk", "europe", "us", "desert", "tropical", "south")
SIZE = 1024
MAPS = {  # pack map -> source suffixes, best first
    "albedo": ("_BaseColor.jpg", "_Basecolor.jpg", "_Color.jpg"),
    "normal": ("_NormalGL.jpg", "_Normal.jpg"),
    "roughness": ("_Roughness.jpg",),
}


def find(src, suffixes):
    for suf in suffixes:
        hits = sorted(glob.glob(os.path.join(src, "*" + suf)))
        if hits:
            return hits[0]
    return None


def scan_size(src):
    """The real width in metres of a Megascans scan, from its JSON."""
    for j in glob.glob(os.path.join(src, "*.json")):
        try:
            data = json.load(open(j))
        except (OSError, ValueError):
            continue
        for m in data.get("maps", []):
            size = str(m.get("physicalSize", ""))
            hit = re.match(r"([\d.]+)x", size)
            if hit:
                return float(hit.group(1))
    return None


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    pack = sys.argv[1]
    out_dir = os.path.join(pack, "surfaces")
    os.makedirs(out_dir, exist_ok=True)
    manifest = os.path.join(out_dir, "surfaces.json")
    slots = json.load(open(manifest)).get("slots", {}) if os.path.exists(manifest) else {}
    for arg in sys.argv[2:]:
        slot, _, spec = arg.partition("=")
        base, _, region = slot.partition("@")
        if base not in SLOTS or (region and region not in REGIONS) or not spec:
            sys.exit("bad slot: " + arg)
        src, _, size_m = spec.partition("@")
        size = float(size_m) if size_m else scan_size(src)
        if not size:
            sys.exit("no real size for %s: give it as @SIZE_M" % src)
        entry = {"title": os.path.basename(os.path.normpath(src)), "size_m": round(size, 3)}
        for key, suffixes in MAPS.items():
            path = find(src, suffixes)
            if path is None:
                if key == "albedo":
                    sys.exit("no colour map in " + src)
                continue
            im = Image.open(path)
            im.draft(im.mode, (SIZE, SIZE))
            im = im.convert("L" if key == "roughness" else "RGB").resize((SIZE, SIZE), Image.LANCZOS)
            name = "%s_%s.jpg" % (slot.replace("@", "-"), key)
            im.save(os.path.join(out_dir, name), quality=92)
            entry[key] = name
        slots[slot] = entry
        print("%-7s %-40s %.2f m" % (slot, entry["title"], size))
    with open(manifest, "w") as f:
        json.dump({"source": "Quixel Megascans and ambientCG scans (private pack, never redistribute)",
                   "slots": slots}, f, indent=1)


if __name__ == "__main__":
    main()
