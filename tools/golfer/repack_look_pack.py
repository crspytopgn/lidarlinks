#!/usr/bin/env python3
"""Deduplicates a built look pack (game/assets/golfer/free_golfer_parts.olg)
without rebuilding it from the MakeHuman sources, which are not in the repo.

    python3 tools/golfer/repack_look_pack.py [--in FILE] [--out FILE] [--check]

Two kinds of waste the builder leaves behind:

* byte-identical images (the cap's texture and normal are written twice,
  once for the MakeHuman cap and once for the realistic people's caps);
  the second copy is dropped and every index that named it is remapped.
* byte-identical array spans (blend shapes that move the same rows, and a
  few meshes that share their triangles); the second copy is dropped and
  the span is pointed at the first. Spans are only ever read through
  [offset, length], so sharing one is exact: the decoded arrays are
  byte-identical.

Nothing else changes: same format version, same gzip level, same header
layout. --check only reports what would be saved. The game loads the
result through GolferParts as before; game/tests/run_tests.gd
(OL_TEST_ONLY=free_golfer) is the check that it still plays.
"""

import argparse
import copy
import gzip
import hashlib
import json
import os
import struct
import sys

VERSION = 2

# Part arrays, in the order look_pack.py writes them; shape arrays likewise.
ARRAY_KEYS = ("positions", "normals", "uvs", "bones", "weights", "indices", "tangents")
SHAPE_ARRAY_KEYS = ("rows", "positions", "normals_u8")
# Material fields that name an image by index (plus the header's own).
IMAGE_INDEX_KEYS = ("texture", "normal", "regions", "occlusion")


def load(path):
    """(header, body) of a look pack."""
    with open(path, "rb") as f:
        raw = f.read()
    if raw[:4] != b"OLGL" or struct.unpack("<I", raw[4:8])[0] != VERSION:
        raise ValueError("%s is not a version %d look pack" % (path, VERSION))
    size = struct.unpack("<I", raw[8:12])[0]
    data = gzip.decompress(raw[12:])
    if len(data) != size:
        raise ValueError("%s did not inflate to its recorded size" % path)
    head_size = struct.unpack("<I", data[:4])[0]
    return json.loads(data[4:4 + head_size]), data[4 + head_size:]


def save(path, header, body):
    """Writes a look pack, laid out as look_pack.Pack.save() does."""
    head = json.dumps(header, separators=(",", ":"), sort_keys=True).encode()
    while len(head) % 4:
        head += b" "
    data = struct.pack("<I", len(head)) + head + bytes(body)
    with open(path, "wb") as f:
        f.write(b"OLGL" + struct.pack("<II", VERSION, len(data)))
        f.write(gzip.compress(data, 9, mtime=0))


def _dedupe_images(header, body):
    """Drops byte-identical images and remaps every index naming one.
    Returns (images kept, duplicated bytes dropped)."""
    seen = {}
    remap = {}
    kept = []
    dropped = 0
    for i, image in enumerate(header["images"]):
        off, size = image["data"]
        digest = hashlib.sha256(body[off:off + size]).digest()
        if digest in seen:
            remap[i] = seen[digest]
            dropped += size
        else:
            seen[digest] = len(kept)
            remap[i] = len(kept)
            kept.append(image)
    if dropped == 0:
        return len(kept), 0
    header["images"] = kept
    for material in header["materials"].values():
        for key in IMAGE_INDEX_KEYS:
            if key in material and material[key] >= 0:
                material[key] = remap[material[key]]
        detail = material.get("face_detail", {})
        for key in ("albedo", "normal"):
            if key in detail and detail[key] >= 0:
                detail[key] = remap[detail[key]]
    for name, index in header.get("eyes", {}).items():
        header["eyes"][name] = remap[index]
    if isinstance(header.get("skin_female"), int):
        header["skin_female"] = remap[header["skin_female"]]
    if isinstance(header.get("skin_regions"), int):
        header["skin_regions"] = remap[header["skin_regions"]]
    return len(kept), dropped


def _span_refs(header):
    """Every [offset, length] in the pack, as (holder, key) pairs, in a
    fixed order: images first, then parts (sorted), then the shared cap
    arrays. Only the format's own span fields, never lookalikes such as
    the Shoes material's golf_source."""
    refs = []
    for image in header["images"]:
        refs.append((image, "data"))
    for name in sorted(header["parts"]):
        part = header["parts"][name]
        for key in ARRAY_KEYS:
            if key in part:
                refs.append((part, key))
        for shape in sorted(part.get("shapes", {})):
            entry = part["shapes"][shape]
            for key in SHAPE_ARRAY_KEYS:
                if key in entry:
                    refs.append((entry, key))
    shared = header.get("person_cap_shared", {})
    for key in ("bones", "uvs", "weights"):
        if key in shared:
            refs.append((shared, key))
    return refs


def _dedupe_spans(header, body):
    """Rebuilds the body with each distinct byte string kept once, and
    points every span at its copy. Returns (new body, spans kept,
    duplicated bytes dropped)."""
    refs = _span_refs(header)
    seen = {}  ## digest -> (span in the new body, offset in the old one)
    blob = bytearray()
    dropped = 0
    for holder, key in refs:
        off, size = holder[key]
        chunk = body[off:off + size]
        digest = hashlib.sha256(chunk).digest()
        if digest in seen:
            span, kept_off = seen[digest]
            holder[key] = span
            # Only bytes at a different offset were really stored twice:
            # several parts already share one span (the caps' bones, uvs
            # and weights), and pointing them at it again saves nothing.
            if off != kept_off:
                dropped += size
            continue
        while len(blob) % 4:
            blob.append(0)
        span = [len(blob), len(chunk)]
        blob.extend(chunk)
        seen[digest] = (span, off)
        holder[key] = span
    return bytes(blob), len(seen), dropped


def repack(src, dst):
    """Deduplicates the pack at `src` into `dst`; returns a summary."""
    header, body = load(src)
    before = os.path.getsize(src)
    images, image_bytes = _dedupe_images(header, body)
    new_body, spans, span_bytes = _dedupe_spans(header, body)
    save(dst, header, new_body)
    return {
        "images_kept": images,
        "image_bytes_dropped": image_bytes,
        "spans_kept": spans,
        "span_bytes_dropped": span_bytes,
        "before": before,
        "after": os.path.getsize(dst),
    }


def check(src):
    """What repack() would save, without writing anything."""
    header, body = load(src)
    header = copy.deepcopy(header)
    images, image_bytes = _dedupe_images(header, body)
    _new_body, spans, span_bytes = _dedupe_spans(header, body)
    return {
        "images_kept": images,
        "image_bytes_dropped": image_bytes,
        "spans_kept": spans,
        "span_bytes_dropped": span_bytes,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--in", dest="src", default="game/assets/golfer/free_golfer_parts.olg")
    ap.add_argument("--out", dest="dst", default=None, help="default: overwrite --in")
    ap.add_argument("--check", action="store_true", help="report what would be saved, without writing")
    args = ap.parse_args()
    if args.check:
        summary = check(args.src)
        print("images kept: %d (%d duplicated bytes would go)" % (summary["images_kept"], summary["image_bytes_dropped"]))
        print("spans kept: %d (%d duplicated bytes would go)" % (summary["spans_kept"], summary["span_bytes_dropped"]))
        return 0
    summary = repack(args.src, args.dst or args.src)
    print("images kept: %d (%d duplicated bytes dropped)" % (summary["images_kept"], summary["image_bytes_dropped"]))
    print("spans kept: %d (%d duplicated bytes dropped)" % (summary["spans_kept"], summary["span_bytes_dropped"]))
    print("file: %d -> %d bytes (%.1f%% smaller)" % (
        summary["before"], summary["after"],
        100.0 * (summary["before"] - summary["after"]) / summary["before"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
