#!/usr/bin/env python3
"""Cuts a Movie Maker capture (capture.gd) into its takes.

    python3 tools/promo/cut.py /tmp/promo/NAME [out_dir]

Frames painted solid magenta are between takes; each run of other frames is
encoded as out_dir/NAME-N.mp4 (H.264, near lossless) with the matching piece
of the sound Godot wrote beside the frames. The PNG frames are deleted once
cut unless KEEP=1. Dev tool only.
"""
import glob
import os
import subprocess
import sys

from PIL import Image

FPS = 30


def is_mask(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    for x, y in ((w // 2, h // 2), (10, 10), (w - 10, h - 10), (w // 3, h // 4)):
        r, g, b = im.getpixel((x, y))
        if not (r > 240 and g < 15 and b > 240):
            return False
    return True


def main():
    src = sys.argv[1].rstrip("/")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(src)
    name = os.path.basename(src)
    frames = sorted(glob.glob(os.path.join(src, "*.png")))
    wavs = glob.glob(os.path.join(src, "*.wav"))
    takes = []
    start = None
    for i, f in enumerate(frames):
        m = is_mask(f)
        if not m and start is None:
            start = i
        elif m and start is not None:
            takes.append((start, i))
            start = None
    if start is not None:
        takes.append((start, len(frames)))
    os.makedirs(out, exist_ok=True)
    for n, (a, b) in enumerate(takes, 1):
        lst = os.path.join(src, "take%d.txt" % n)
        with open(lst, "w") as fh:
            for f in frames[a:b]:
                fh.write("file '%s'\nduration %f\n" % (f, 1.0 / FPS))
        dst = os.path.join(out, "%s-%d.mp4" % (name, n))
        cmd = ["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", lst]
        if wavs:
            cmd += ["-ss", "%.4f" % (a / FPS), "-t", "%.4f" % ((b - a) / FPS), "-i", wavs[0]]
        cmd += ["-map", "0:v"] + (["-map", "1:a", "-c:a", "aac", "-b:a", "256k"] if wavs else [])
        cmd += ["-r", str(FPS), "-c:v", "libx264", "-preset", "slow", "-crf", "12", "-pix_fmt", "yuv420p", "-shortest", dst + ".part.mp4"]
        subprocess.run(cmd, check=True)
        os.replace(dst + ".part.mp4", dst)
        print("%s: frames %d-%d (%.1f s)" % (dst, a, b, (b - a) / FPS))
    if os.environ.get("KEEP") != "1" and takes:
        for f in frames:
            os.remove(f)


if __name__ == "__main__":
    main()
