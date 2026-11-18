"""Rebuilds the Mixamo golfer's finger skin weights as clean segments.

    python3 tools/golfer/finger_weights.py [--pack game/assets/golfer/free_golfer_parts.olg]

Mixamo's auto-rigger smeared the weights of Michael's golfer's fingers
(the look pack's Mixamo person, mixamo_person.py): a third of the hand's
skin was a blend under 0.75, and neighbouring fingers shared skin. When the
fingers closed round the grip they squashed and fused, and the gloved left
hand looked deformed. Here every vertex of a finger goes to the finger
whose bones it lies nearest, and along that finger to the segment it lies
on, blending only across a few millimetres at each knuckle (the palm and
the thumb's root keep a wider blend). Skin beyond the wrist is left alone.
Runs once (who.finger_weights).
"""

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import rocketbox  # noqa: E402
from golf_shoes import load, save  # noqa: E402

CHAINS = ("thumb", "index", "middle", "ring", "pinky")
BLEND = 0.008  # metres either side of a finger joint
BLEND_ROOT = 0.016  # at the knuckles, where the palm meets the finger
BLEND_THUMB_ROOT = 0.014


def smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def seg_param(p, a, b):
    d = b - a
    t = np.clip(((p - a) @ d) / (d @ d), 0.0, 1.0)
    return t, np.linalg.norm(p - (a + np.outer(t, d)), axis=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default=os.path.join(rocketbox.ROOT, "game/assets/golfer/free_golfer_parts.olg"))
    ap.add_argument("--person", default="Male_Adult_14")
    args = ap.parse_args()
    info, blob = load(args.pack)
    who = info["people"][args.person]
    if who.get("finger_weights"):
        sys.exit("already done (finger_weights)")
    names = info["bones"]
    idx = {n: k for k, n in enumerate(names)}
    e = info["parts"][who["parts"][0]]
    pos = np.frombuffer(bytes(blob[e["positions"][0]:e["positions"][0] + e["positions"][1]]), np.float32).reshape(-1, 3)
    n_v = len(pos)
    bo, wo = e["bones"], e["weights"]
    bones = np.frombuffer(bytes(blob[bo[0]:bo[0] + bo[1]]), np.int32).reshape(n_v, -1).copy()
    weights = np.frombuffer(bytes(blob[wo[0]:wo[0] + wo[1]]), np.float32).reshape(n_v, -1).copy()
    at = lambda n: np.array(who["binds"][n][9:12])  # noqa: E731 - the joint in bind (mesh) space
    changed = 0
    for s in "lr":
        hand = idx[f"hand_{s}"]
        side = [idx[n] for n in names if n == f"hand_{s}" or (n.endswith("_" + s) and n.split("_")[0] in CHAINS)]
        on = np.isin(bones, side)
        share = np.sum(np.where(on, weights, 0.0), axis=1)
        sel = np.nonzero(share > 0.5)[0]
        p = pos[sel].astype(float)
        # Each chain: its joints and a tip past the last.
        best_d = np.full(len(p), np.inf)
        best_w = [None] * len(p)
        for f in CHAINS:
            j = [at(f"{f}_0{i}_{s}") for i in (1, 2, 3)]
            tip = j[2] + (j[2] - j[1]) * 0.9
            pts = j + [tip]
            b = [idx[f"{f}_0{i}_{s}"] for i in (1, 2, 3)]
            # Distance to the chain (its three segments) and where along it.
            dist = np.full(len(p), np.inf)
            where = np.zeros(len(p))
            for k in range(3):
                t, d = seg_param(p, pts[k], pts[k + 1])
                closer = d < dist
                dist[closer] = d[closer]
                where[closer] = k + t[closer]
            # Before the first joint (towards the wrist): measured to that
            # joint along the finger, so the palm stays with the hand.
            d0 = pts[1] - pts[0]
            back = ((p - pts[0]) @ (d0 / np.linalg.norm(d0)))
            root = BLEND_THUMB_ROOT if f == "thumb" else BLEND_ROOT
            for v in range(len(p)):
                if dist[v] >= best_d[v]:
                    continue
                best_d[v] = dist[v]
                w = {}
                if where[v] <= 0.0 and back[v] < root:
                    # Round the first joint: hand to the first segment.
                    k = smooth((back[v] + root) / (2 * root))
                    w = {hand: 1 - k, b[0]: k}
                else:
                    k = int(min(2, np.floor(where[v])))
                    seg_len = np.linalg.norm(pts[k + 1] - pts[k])
                    x = (where[v] - k) * seg_len  # metres past joint k
                    y = (1.0 - (where[v] - k)) * seg_len  # metres before joint k+1
                    w = {b[k]: 1.0}
                    if k == 0:
                        m = smooth((x + root) / (2 * root))
                        w = {hand: 1 - m, b[0]: m}
                    elif x < BLEND:
                        m = smooth((x + BLEND) / (2 * BLEND))
                        w = {b[k - 1]: 1 - m, b[k]: m}
                    if k < 2 and y < BLEND:
                        m = smooth((BLEND - y) / (2 * BLEND))
                        w = {kk: vv * (1 - m) for kk, vv in w.items()}
                        w[b[k + 1]] = w.get(b[k + 1], 0.0) + m
                best_w[v] = w
        # Skin far from every finger (the palm's back, the wrist) keeps its
        # weights; a finger's skin lies within about its thickness.
        for v in range(len(p)):
            if best_w[v] is None or best_d[v] > 0.013:
                continue
            w = {k: x for k, x in best_w[v].items() if x > 1e-4}
            # The rest of the vertex's weight (the forearm) stays.
            rest = {int(bones[sel[v], c]): float(weights[sel[v], c]) for c in range(bones.shape[1])
                    if weights[sel[v], c] > 0 and bones[sel[v], c] not in side}
            total = share[sel[v]]
            merged = {k: x * total for k, x in w.items()}
            merged.update(rest)
            top = sorted(merged.items(), key=lambda kv: -kv[1])[:bones.shape[1]]
            norm = sum(x for _, x in top)
            row_b = [k for k, _ in top] + [0] * (bones.shape[1] - len(top))
            row_w = [x / norm for _, x in top] + [0.0] * (bones.shape[1] - len(top))
            bones[sel[v]] = row_b
            weights[sel[v]] = row_w
            changed += 1
    blob[bo[0]:bo[0] + bo[1]] = bones.astype(np.int32).tobytes()
    blob[wo[0]:wo[0] + wo[1]] = weights.astype(np.float32).tobytes()
    who["finger_weights"] = 1
    save(args.pack, info, blob)
    print("%d hand vertices reweighted" % changed)


if __name__ == "__main__":
    main()
