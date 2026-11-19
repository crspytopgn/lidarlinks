"""Slows the short standing idles to a calm, seamless loop.

    python3 tools/golfer/idle_loop.py [--glb game/assets/golfer/free_golfer.glb] [--dry]

mixamo_bake loops an idle over the frames it is given. The putting address
was baked from 11 frames, so it played a 0.37 s loop: millimetre mocap
jitter repeated three times a second, and he looked as if he were shaking
over the ball. Every standing idle (IDLES) shorter than
MIN_LOOP is stretched here to LOOP_S, its keys resampled every 1/KEYS s with a
periodic Catmull-Rom (so there is no corner, and no pop where the loop joins)
and then softened with a periodic box filter SMOOTH keys wide.
The pose it starts on is unchanged, so the putt still begins where it did.
Runs once per glb (extras.idle_loop).
"""

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import glb_edit  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
IDLES = ("address", "address_iron", "address_putt")  # free_golfer.gd LOOPING, less the walk (a stride keeps its pace)
MIN_LOOP = 2.0  # seconds: shorter loops read as a twitch
LOOP_S = 4.0  # as long as the full-swing address idles
KEYS = 15  # a second
SMOOTH = 5


def periodic(v, u):
    """Catmull-Rom through the closed loop of keys v (the last key equals
    the first), at fractional key positions u."""
    n = len(v) - 1
    i = np.floor(u).astype(int)
    f = (u - i)[:, None]
    p0, p1, p2, p3 = (v[(i + k) % n] for k in (-1, 0, 1, 2))
    return 0.5 * (2 * p1 + (p2 - p0) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f
                  + (3 * p1 - p0 - 3 * p2 + p3) * f * f * f)


def box(v):
    k = SMOOTH // 2
    return sum(np.roll(v, s, axis=0) for s in range(-k, k + 1)) / SMOOTH


def retime(glb, name):
    anim = glb.animation(name)
    if anim is None:
        return
    first = None
    for ch in anim["channels"]:
        smp = anim["samplers"][ch["sampler"]]
        t = np.array(glb.read(smp["input"]), float)
        if len(t) > 1:
            first = t
            break
    if first is None or first[-1] >= MIN_LOOP:
        return
    n = int(round(LOOP_S * KEYS))
    times = np.arange(n + 1) / KEYS
    keys = len(first) - 1
    u = times[:-1] / LOOP_S * keys
    inp = glb.add(times.astype(np.float32), minmax=True)
    done = set()
    for ch in anim["channels"]:
        smp = anim["samplers"][ch["sampler"]]
        if id(smp) in done:
            continue
        t = np.array(glb.read(smp["input"]), float)
        if len(t) <= 1:
            continue
        if len(t) != len(first) or not np.allclose(t, first):
            raise ValueError("%s: channels keyed at different times" % name)
        v = np.array(glb.read(smp["output"]), float)
        quat = ch["target"]["path"] == "rotation"
        if quat:
            for k in range(1, len(v)):
                if np.dot(v[k], v[k - 1]) < 0.0:
                    v[k] = -v[k]
            if np.dot(v[-1], v[0]) < 0.0:
                v[-1] = -v[-1]
        # Make the loop exactly closed: the last key is the first again.
        v[-1] = v[0]
        w = periodic(v, u)
        start = w[0].copy()
        w = box(w)
        w += start - w[0]  # the pose it starts on stays where it was
        if quat:
            w /= np.linalg.norm(w, axis=1, keepdims=True)
        w = np.vstack([w, w[:1]])
        smp["input"] = inp
        smp["output"] = glb.add(w.astype(np.float32))
        done.add(id(smp))
    print("  %s: %.2f s loop of %d keys -> %.1f s, %d keys" % (name, first[-1], len(first), LOOP_S, n + 1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default=os.path.join(ROOT, "game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--out")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    if glb.doc.get("extras", {}).get("idle_loop"):
        sys.exit("already done (extras.idle_loop)")
    for name in IDLES:
        retime(glb, name)
    if not args.dry:
        glb.doc.setdefault("extras", {})["idle_loop"] = 1
        glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
