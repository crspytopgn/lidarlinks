"""Seals the seams in the clothing masks of the Rocketbox people already in
the look pack (rocketbox.seal_seams): where a dyed garment meets cloth the
dye leaves alone (a contrast neckband, cuffs), its source colour no
longer shows through as a halo along the seam.

    python3 tools/golfer/seal_regions.py [--pack game/assets/golfer/free_golfer_parts.olg]

New packs get this from rocketbox.py itself; this updates one built
before it. It refuses a pack it has already been run on.
"""

import argparse
import io
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from golf_shoes import load, save  # noqa: E402
from upgrade_pack import compact  # noqa: E402
from rocketbox import ROOT, linear, seal_seams, skin_texels  # noqa: E402


def image(info, blob, index):
    off, size = info["images"][index]["data"]
    return Image.open(io.BytesIO(bytes(blob[off:off + size])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default=os.path.join(ROOT, "game/assets/golfer/free_golfer_parts.olg"))
    args = ap.parse_args()
    info, blob = load(args.pack)
    if info.get("regions_sealed"):
        sys.exit("already sealed")
    for name, mat in info["materials"].items():
        if "regions" not in mat or mat.get("tint") != "person":
            continue
        head = info["materials"].get(name[:-len("_body")] + "_head") if name.endswith("_body") else None
        if head is None or int(head.get("texture", -1)) < 0:
            continue
        mask = np.asarray(image(info, blob, mat["regions"]).convert("RGB")) > 127
        tex = linear(np.asarray(image(info, blob, mat["texture"]).convert("RGB").resize(mask.shape[1::-1], Image.BILINEAR)) / 255.0)
        face = linear(np.asarray(image(info, blob, head["texture"]).convert("RGB").resize((512, 512))) / 255.0)
        skin = np.median(face[200:300, 200:310].reshape(-1, 3), axis=0)  # the cheeks and nose, as rocketbox.py
        sealed = seal_seams(mask, skin_texels(tex, skin))
        img = Image.fromarray((sealed * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
        buf = io.BytesIO()
        kind = info["images"][mat["regions"]]["kind"]
        if kind == "webp":  # as webp_images.py: lossless
            img.save(buf, "WEBP", lossless=True, quality=100, method=6, exact=True)
        else:
            kind = "png"
            img.save(buf, "PNG", optimize=True)
        data = buf.getvalue()
        info["images"][mat["regions"]]["kind"] = kind
        while len(blob) % 4:
            blob.append(0)
        info["images"][mat["regions"]]["data"] = [len(blob), len(data)]
        blob.extend(data)
        print("%s: %d texels added" % (name, int(sealed.sum() - mask.sum())))
    info["regions_sealed"] = True
    save(args.pack, info, compact(info, blob))


if __name__ == "__main__":
    main()
