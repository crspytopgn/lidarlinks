"""Lengthens the club meshes to the length the swings were baked for.

    python3 tools/golfer/club_length.py [--glb game/assets/golfer/free_golfer.glb] [--dry]

mixamo_bake sets the club in the hands so that a point at the address grip's
distance from the ball (1.14 m with the driver, 0.92 m with the putter, on the
drawn person) reaches the ball. The club meshes are shorter than that (the
driver's head sits 1.05 m down the shaft, the putter's 0.78 m), so in the
game the driver's sole passed 8 cm over the ball and the putter swung 12 cm
clean over it.

Here each club's head is moved down its shaft, and the shaft stretched to
meet it (the grip stays in the hands), by just enough that at impact the
head's centre crosses the ball with its sole at SOLE_AT: a 45.5 inch driver
and a 36 inch putter, both within real clubs' range.
The longer shaft carries the head further out from him, so each club's
clips (FAMILY) then slide him back from the ball until, at impact, the
head's middle is on the ball's line rather than the ball on the heel.
Runs once per glb (extras.club_length).
"""

import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import glb_edit  # noqa: E402
import mixamo_bake as B  # noqa: E402
import mocap_swing as M  # noqa: E402
from mesh_grip import PACK, channel  # noqa: E402

BALL_RADIUS = 0.02135
ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
# Club: (mesh node prefix, the clip that strikes, the seconds to search for
# impact in, the sole's height there: the driver's ball is teed up, an iron
# takes a little turf, the putter skims the green).
CLUBS = {
    "Driver": ("swing", (0.15, 0.4), 0.0),
    "Iron": ("swing_iron", (0.15, 0.4), -0.005),
    "Putter": ("putt", (0.8, 1.2), 0.003),
}

FAMILY = {
    "Driver": ("address", "backswing", "swing", "ref_address", "ref_address_v2"),
    "Iron": ("address_iron", "backswing_iron", "swing_iron", "ref_address_iron"),
    "Putter": ("address_putt", "putt", "ref_address_putt"),
}


def club_frame(glb, rig, node_name):
    """The mesh's vertices in the club joint's frame, and the matrices to
    and from it."""
    doc = glb.doc
    node = next(n for n in doc["nodes"] if n.get("name") == node_name)
    prim = doc["meshes"][node["mesh"]]["primitives"][0]
    skin = doc["skins"][node["skin"]]
    ibm = np.array(glb.read(skin["inverseBindMatrices"])).astype(float)
    k = skin["joints"].index(rig.joints[rig.index["club"]])
    m = ibm[k].reshape(4, 4).T
    V = np.array(glb.read(prim["attributes"]["POSITION"])).astype(float)
    return prim, m, (m[:3, :3] @ V.T).T + m[:3, 3]


def put_back(glb, prim, m, local):
    inv = np.linalg.inv(m)
    V = (inv[:3, :3] @ local.T).T + inv[:3, 3]
    prim["attributes"]["POSITION"] = glb.add(V.astype(np.float32), minmax=True)


def needed(glb, rig, clip, window, sole_at, head, shaft_dir):
    """Metres the head must move down the shaft so that, where its centre
    crosses the ball, its sole is at sole_at."""
    cj = rig.index["club"]
    ball = np.array(M.IMPACT_AT)
    best = None
    for t in np.arange(window[0], window[1], 1.0 / 240.0):
        local, root = rig.sample(glb, clip, float(t))
        R, P = rig.world(local, root)
        c = P[cj] + R[cj] @ head.mean(axis=0)
        if best is None or abs(c[0] - ball[0]) < best[0]:
            best = (abs(c[0] - ball[0]), t, R[cj], P[cj])
    _, t, R, P = best
    sole = (P + (R @ head.T).T)[:, 1].min()
    down = (R @ shaft_dir)[1]  # the head drops this much per metre down the shaft
    return float((sole_at - sole) / down), t, sole


def impact_z(glb, rig, clip, head):
    """The head's middle, out from him (z), where its face reaches the ball,
    interpolated between keys."""
    cj = rig.index["club"]
    anim = glb.animation(clip)
    times = np.array(glb.read(channel(glb, anim, rig.joints[rig.index["hand_l"]], "rotation")["input"]))
    back = M.IMPACT_AT[0] + BALL_RADIUS
    prev = None
    for t in times:
        local, root = rig.sample(glb, clip, float(t))
        R, P = rig.world(local, root)
        W = P[cj] + (R[cj] @ head.T).T
        lead, z = W[:, 0].min(), W[:, 2].mean()
        if prev is not None and prev[0] > back >= lead:
            k = (prev[0] - back) / (prev[0] - lead)
            return prev[1] + k * (z - prev[1]), float(t)
        prev = (lead, z)
    raise ValueError("the head never reaches the ball in " + clip)


def slide(glb, rig, names, dz):
    """The body slid dz along z (away from the ball +) in these clips."""
    for name in names:
        anim = glb.animation(name)
        if anim is None:
            continue
        smp = channel(glb, anim, rig.joints[0], "translation")
        v = np.array(glb.read(smp["output"])).astype(float)
        v[:, 2] += dz
        smp["output"] = glb.add(v.astype(np.float32))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default=os.path.join(ROOT, "game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--out")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    if glb.doc.get("extras", {}).get("club_length"):
        sys.exit("already done (extras.club_length)")
    rig = M.Rig(glb)
    turns = json.load(open(os.path.join(ROOT, "tools/golfer/mixamo_turns.json")))
    rig.offsets = B.person_rig(rig, PACK, turns["person"])
    for club, (clip, window, sole_at) in CLUBS.items():
        if glb.animation(clip) is None:
            continue
        hp, hm, head = club_frame(glb, rig, club + "_head")
        sp, sm, shaft = club_frame(glb, rig, club + "_shaft")
        d = shaft.mean(axis=0)
        d = d / np.linalg.norm(d)
        delta, t, sole = needed(glb, rig, clip, window, sole_at, head, d)
        along = shaft @ d
        top, end = along.min(), along.max()
        old = float(np.max(head @ d))
        print("  %-6s impact %.2f s, sole %+.3f m: head moved %.3f m down the shaft (to %.2f m, %.1f in)" % (
            club, t, sole, delta, old + delta, (old + delta) / 0.0254))
        if args.dry:
            continue
        put_back(glb, hp, hm, head + d * delta)
        k = np.clip((along - top) / (end - top), 0.0, 1.0)[:, None]
        put_back(glb, sp, sm, shaft + d * delta * k)
        z, t = impact_z(glb, rig, clip, head + d * delta)
        dz = z - M.IMPACT_AT[2]
        slide(glb, rig, FAMILY[club], -dz)
        print("         head's middle %.0f mm past the ball's line at %.3f s: slid him back %.0f mm" % (
            -dz * 1000, t, -dz * 1000))
    if not args.dry:
        glb.doc.setdefault("extras", {})["club_length"] = 1
        glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
