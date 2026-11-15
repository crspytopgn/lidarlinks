#!/usr/bin/env python3
"""Bake a Megascans lawn scan into blade detail for the mown turf.

    python3 turf_detail.py SCAN_DIR PACK_DIR [--blur-cm 3] [--size 2048]

SCAN_DIR holds a scan's *_BaseColor.jpg and *_Normal.jpg (1 x 1 m tiles).
Writes PACK_DIR/ground/turf_detail.jpg and turf_normal.jpg, which
terrain.gdshader multiplies over the course's own grass colour, mowing
stripes and patches (has_scan). Both are high-passed: the scan's colour
divided by a blur of itself a few centimetres across, and its normal with
the same blur taken out, so only the blades are left and none of the
clumps, bare patches or lighting baked into the photo. Private pack only
(docs/megascans-pack.md): never commit the output.
"""
import argparse
import glob
import os

import numpy as np
from PIL import Image


def _find(d, word):
    hits = sorted(glob.glob(os.path.join(d, "*_%s.jpg" % word)))
    if not hits:
        raise SystemExit("no *_%s.jpg in %s" % (word, d))
    return hits[0]


def _blur_wrap(a, sigma):
    """A Gaussian blur of a tiling image (H, W, C floats) that wraps (by FFT)."""
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    return np.stack([np.fft.irfft2(np.fft.rfft2(a[:, :, c]) * g, s=(h, w))
                     for c in range(a.shape[2])], axis=2).astype(np.float32)


def bake(scan_dir, size, blur_cm, chroma):
    base = Image.open(_find(scan_dir, "BaseColor")).convert("RGB").resize((size, size), Image.LANCZOS)
    norm = Image.open(_find(scan_dir, "Normal")).convert("RGB").resize((size, size), Image.LANCZOS)
    sigma = blur_cm / 100.0 * size
    lin = (np.asarray(base, np.float32) / 255.0) ** 2.2
    ratio = lin / np.maximum(_blur_wrap(lin, sigma), 1e-3)
    luma = ratio @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    ratio = luma[:, :, None] + chroma * (ratio - luma[:, :, None])
    ratio /= ratio.reshape(-1, 3).mean(0)
    # Stored as half the ratio in sRGB-free linear bytes: the shader reads
    # it as a non-colour texture and doubles it.
    detail = np.clip(ratio * 0.5, 0.0, 1.0)
    n = np.asarray(norm, np.float32) / 255.0 * 2.0 - 1.0
    n = n - _blur_wrap(n, sigma) + np.array([0.0, 0.0, 1.0], np.float32)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return (Image.fromarray((detail * 255.0 + 0.5).astype(np.uint8)),
            Image.fromarray(((n * 0.5 + 0.5) * 255.0 + 0.5).astype(np.uint8)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("scan_dir")
    ap.add_argument("pack_dir")
    ap.add_argument("--size", type=int, default=2048)
    ap.add_argument("--blur-cm", type=float, default=3.0)
    ap.add_argument("--chroma", type=float, default=0.4, help="how much of the scan's hue shifts to keep")
    a = ap.parse_args()
    detail, normal = bake(a.scan_dir, a.size, a.blur_cm, a.chroma)
    out = os.path.join(a.pack_dir, "ground")
    os.makedirs(out, exist_ok=True)
    detail.save(os.path.join(out, "turf_detail.jpg"), quality=92)
    normal.save(os.path.join(out, "turf_normal.jpg"), quality=95)
    print("wrote", out)


if __name__ == "__main__":
    main()
