#!/usr/bin/env python3
"""Re-encodes the PNG images of a look pack (free_golfer_parts.olg) as WebP,
in place: about 3.5 MB off every download, with no visible change.

    python3 tools/golfer/webp_images.py [game/assets/golfer/free_golfer_parts.olg]

Material textures (hair, eyes, brows, lashes and the realistic people's
hair-card "opacity" maps) become lossy WebP at quality 92 with lossless alpha,
so the alpha-scissor edges are exactly as before. Everything else (the
region masks the creator recolours by) becomes lossless WebP, pixel for
pixel. `exact` keeps the colour under transparent pixels, which the
mipmaps blend into the card edges. JPEGs are left alone: re-encoding them
would add a second generation of loss for about 25%.

Run it last, after any tool that adds or rewrites images in the pack (they
write PNGs); running it again changes nothing. GolferParts.texture() reads
"webp" entries.
"""

import gzip
import io
import json
import struct
import sys

from PIL import Image

LOSSY_QUALITY = 92


def material_textures(header):
    """Indices of images a material draws as its colour texture."""
    out = set()
    for mat in header.get("materials", {}).values():
        if int(mat.get("texture", -1)) >= 0:
            out.add(int(mat["texture"]))
    for index in header.get("eyes", {}).values():
        if isinstance(index, int):
            out.add(index)
    return out


def convert(path):
    raw = open(path, "rb").read()
    assert raw[:4] == b"OLGL", "not a look pack"
    version, size = struct.unpack("<II", raw[4:12])
    data = gzip.decompress(raw[12:])
    assert len(data) == size
    head_len = struct.unpack("<I", data[:4])[0]
    header = json.loads(data[4:4 + head_len])
    blob = data[4 + head_len:]
    colour = material_textures(header)
    # Each WebP goes where its PNG was and the rest of the PNG's bytes are
    # zeroed, so no other array moves; the zeros cost next to nothing once
    # the pack is gzipped.
    blob = bytearray(blob)
    before = after = count = 0
    for i, entry in enumerate(header["images"]):
        if entry["kind"] != "png":
            continue
        off, n = entry["data"]
        img = Image.open(io.BytesIO(bytes(blob[off:off + n])))
        img.load()
        buf = io.BytesIO()
        if i in colour:
            img.save(buf, "WEBP", quality=LOSSY_QUALITY, alpha_quality=100, method=6, exact=True)
        else:
            img.save(buf, "WEBP", lossless=True, quality=100, method=6, exact=True)
        webp = buf.getvalue()
        if len(webp) >= n:
            continue
        blob[off:off + n] = webp + bytes(n - len(webp))
        entry["kind"] = "webp"
        entry["data"] = [off, len(webp)]
        before += n
        after += len(webp)
        count += 1
    if count == 0:
        print(f"{path}: no PNG images to shrink, unchanged")
        return
    head = json.dumps(header, separators=(",", ":"), sort_keys=True).encode()
    while len(head) % 4:
        head += b" "
    out = struct.pack("<I", len(head)) + head + bytes(blob)
    with open(path, "wb") as f:
        f.write(b"OLGL" + struct.pack("<II", version, len(out)))
        f.write(gzip.compress(out, 9, mtime=0))
    print(f"{path}: {count} PNGs {before / 1e6:.2f} MB -> WebP {after / 1e6:.2f} MB")


if __name__ == "__main__":
    convert(sys.argv[1] if len(sys.argv) > 1 else "game/assets/golfer/free_golfer_parts.olg")
