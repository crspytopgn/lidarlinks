"""Holds the club the right way round in one hand through the reactions.

    python3 tools/golfer/carry_club.py [--glb game/assets/golfer/free_golfer.glb] [--dry] [--report]

The club hangs from the left hand (its joint is a child of hand_l), but
mixamo_bake turned it with the RIGHT hand in the standing takes (the
reactions and routines: upset, post_shot, celebrate, fist_pump, slump,
pre_putt...), because the swing takes' lead hand made no sense for a club.
Once the hands part, the club stayed in the left fist while it turned with
the right hand, so it spun in the palm and, much of the time, pointed back
up the forearm into his body (the shaft over 110 degrees from the forearm
in most of upset's keys).

Here, for every clip that does not hold the club in both hands (and not
pull_club, which moves it in the hand on purpose):

- While the hands are apart the club keeps the turn it had in the left
  hand when they parted, so it moves with that hand as a held club does.
  The change is blended over BLEND seconds, so the clip reads unchanged
  while both hands are on the grip.
- Each key is then turned about the grip by the least that keeps the shaft
  off the body (BODY capsules on the joints, with the person's joints),
  the head off the ground, and the shaft out of the fist at an angle a
  wrist allows (FOREARM_MAX degrees from the forearm at most), steady from
  key to key.

Runs once per glb (extras.carry_club). Run after the bake and the grip fits.
"""

import argparse
import json
import os
import sys

import numpy as np
from scipy.optimize import minimize

sys.path.insert(0, os.path.dirname(__file__))
import glb_edit  # noqa: E402
import mixamo_bake as B  # noqa: E402
import mocap_swing as M  # noqa: E402
import pose  # noqa: E402
from mesh_grip import channel, rot_vec  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
# Clips that hold the club in both hands (GolferHands.GRIP_CLIPS) or move it
# in the hand on purpose: left as they are.
CARRY = "walk"  # the clip whose club turn in the left hand is the one-handed carry
SKIP = ("walk", "address", "address_iron", "address_putt", "backswing", "backswing_iron",
        "swing", "swing_iron", "putt", "pull_club")
LENGTH = 1.1  # metres, grip to head (the driver, the longest club)
FROM = 0.12  # metres down the shaft from the grip's top where the checks start (the fist)
BLEND = 0.5  # seconds over which the club settles into the left hand once the hands part
APART = 0.06  # metres the hands part beyond their place on the grip before the club is the left hand's alone
STILL = 20.0  # degrees: a clip whose club turns less than this in the left hand already carries it there
FOREARM_MAX = 100.0  # degrees between the forearm and the shaft out of the fist
GROUND = 0.02  # height the club head keeps above (the ball sits 2 cm up, the head soles at about 1 cm)
# The body as capsules: (from joint, to joint, radius in metres). The head is
# a sphere above its joint.
BODY = [
    ("pelvis", "spine_02", 0.16), ("spine_02", "neck_01", 0.15),
    ("thigh_l", "calf_l", 0.09), ("thigh_r", "calf_r", 0.09),
    ("calf_l", "foot_l", 0.065), ("calf_r", "foot_r", 0.065),
    ("foot_l", "ball_l", 0.05), ("foot_r", "ball_r", 0.05),
    ("upperarm_r", "lowerarm_r", 0.06), ("lowerarm_r", "hand_r", 0.05),
    ("upperarm_l", "lowerarm_l", 0.06),
]
HEAD = ("head", 0.09, 0.13)  # joint, height of the middle above it, radius
MARGIN = 0.01
ALONG = np.linspace(FROM, LENGTH, 14)


class Key:
    """One key's body: the joints in the world, the left hand's turn."""

    def __init__(self, rig, rots, poss):
        ix = rig.index
        h, up, rh = HEAD
        head = poss[ix[h]] + np.array([0.0, up, 0.0])
        self.a = np.array([poss[ix[a]] for a, _, _ in BODY] + [head])
        self.b = np.array([poss[ix[b]] for _, b, _ in BODY] + [head])
        self.r = np.array([r for _, _, r in BODY] + [rh]) + MARGIN
        self.hand = rots[ix["hand_l"]]
        self.grip = poss[ix["club"]]
        fa = poss[ix["hand_l"]] - poss[ix["lowerarm_l"]]
        self.forearm = fa / np.linalg.norm(fa)
        self.apart = np.linalg.norm(poss[ix["hand_r"]] - poss[ix["hand_l"]])

    def cost(self, local, club_dir):
        """Squared metres into the body and the ground, squared degrees past
        the wrist's reach."""
        shaft = self.hand @ local @ club_dir
        q = self.grip + np.outer(ALONG, shaft)  # (points, 3)
        ab = self.b - self.a  # (caps, 3)
        aq = q[:, None, :] - self.a[None, :, :]
        t = np.clip(np.einsum("pck,ck->pc", aq, ab) / np.maximum(np.einsum("ck,ck->c", ab, ab), 1e-9), 0.0, 1.0)
        d = self.r[None, :] - np.linalg.norm(aq - ab[None, :, :] * t[:, :, None], axis=2)
        c = 1e4 * float(np.sum(np.maximum(d, 0.0) ** 2))
        c += 1e4 * max(0.0, GROUND - (self.grip + shaft * LENGTH)[1]) ** 2
        ang = np.degrees(np.arccos(np.clip(np.dot(shaft, self.forearm), -1.0, 1.0)))
        c += 0.2 * max(0.0, ang - FOREARM_MAX) ** 2
        return c

    def forearm_angle(self, local, club_dir):
        shaft = self.hand @ local @ club_dir
        return np.degrees(np.arccos(np.clip(np.dot(shaft, self.forearm), -1.0, 1.0)))


def smooth_step(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def fix_clip(glb, rig, name, club_dir, together, carry):
    anim = glb.animation(name)
    node = rig.joints[rig.index["club"]]
    smp = channel(glb, anim, node, "rotation")
    if smp is None:
        return None
    times = np.array(glb.read(smp["input"]), dtype=float)
    if len(times) < 2:
        return None
    quats = np.array(glb.read(smp["output"]), dtype=float)
    baked = [pose.matrix(q / np.linalg.norm(q)) for q in quats]
    q = quats / np.linalg.norm(quats, axis=1)[:, None]
    if np.degrees(2 * np.arccos(np.clip(np.abs(q @ q[0]), 0, 1))).max() < STILL:
        return None  # already carried by the left hand (teeing up, the read)
    keys = []
    for t in times:
        loc, root = rig.sample(glb, name, float(t))
        r, p = rig.world(loc, root)
        keys.append(Key(rig, r, p))
    # How far the club is the left hand's alone at each key: the hands
    # apart, eased in and out over BLEND.
    off = np.array([k.apart > together + APART for k in keys], dtype=float)
    w = np.zeros(len(keys))
    for i, t in enumerate(times):
        near = np.abs(times - t) <= BLEND * 0.5
        w[i] = smooth_step(off[near].mean() * 1.0)
    # The club in the left hand alone: carried as he carries it walking.
    held = [pose.slerp(baked[i], carry, w[i]) for i in range(len(keys))]
    # Turned about the grip, in the hand, by the least that keeps it clear.
    out, before, after = [], [], []
    v = np.zeros(3)
    for i, k in enumerate(keys):
        base = held[i]
        before.append(k.cost(baked[i], club_dir))

        def f(x, base=base, k=k, last=v):
            return k.cost(rot_vec(x) @ base, club_dir) + 0.02 * np.dot(x, x) + 0.5 * np.dot(x - last, x - last)
        if w[i] < 1e-3:
            v = np.zeros(3)  # both hands on the grip: the clip's own club
        elif np.any(v) or k.cost(base, club_dir) > 0.0:
            best = minimize(f, v, method="Powell", options={"xtol": 1e-4, "ftol": 1e-7})
            v = best.x if best.fun < f(v) else v
            if np.linalg.norm(v) < 1e-3 and k.cost(base, club_dir) == 0.0:
                v = np.zeros(3)
        out.append((rot_vec(v), base))
    # A little smoothing of the turns, key to key.
    vs = []
    for corr, _ in out:
        q = pose.quat(corr)
        vs.append(q if q[3] >= 0 else -q)
    vs = np.array(vs)
    sm = vs.copy()
    for i in range(len(vs)):
        lo, hi = max(0, i - 1), min(len(vs), i + 2)
        m = vs[lo:hi].mean(axis=0)
        sm[i] = m / np.linalg.norm(m)
    final = [pose.slerp(np.eye(3), pose.matrix(sm[i]), w[i]) @ out[i][1] for i in range(len(out))]
    after = [k.cost(final[i], club_dir) for i, k in enumerate(keys)]
    ang_b = [k.forearm_angle(baked[i], club_dir) for i, k in enumerate(keys)]
    ang_a = [k.forearm_angle(final[i], club_dir) for i, k in enumerate(keys)]
    moved = max(np.degrees(np.arccos(np.clip((np.trace(final[i].T @ baked[i]) - 1) / 2, -1, 1)))
                for i in range(len(keys)))
    smp["output"] = glb.add(np.array([pose.quat(m) for m in final], dtype=np.float32))
    stats = dict(keys=len(keys), apart=int((w > 0.5).sum()), moved=moved,
                 bad_before=int(sum(c > 1.0 for c in before)), bad_after=int(sum(c > 1.0 for c in after)),
                 wrong_before=int(sum(a > 110 for a in ang_b)), wrong_after=int(sum(a > 110 for a in ang_a)))
    print("%-12s %3d keys, %3d apart: turned up to %3.0f deg; keys into body/ground/past wrist %3d -> %3d, "
          "shaft back up the forearm (>110 deg) %3d -> %3d" % (
              name, stats["keys"], stats["apart"], moved, stats["bad_before"], stats["bad_after"],
              stats["wrong_before"], stats["wrong_after"]))
    return stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default=os.path.join(ROOT, "game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--out")
    ap.add_argument("--pack", default=os.path.join(ROOT, "game/assets/golfer/free_golfer_parts.olg"))
    ap.add_argument("--clip", action="append", help="only these clips")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    if glb.doc.get("extras", {}).get("carry_club") and not args.dry:
        sys.exit("already fixed (extras.carry_club)")
    rig = M.Rig(glb)
    club_dir = M.club_direction(glb, rig)
    # The joints of the person the takes were made on, for the body.
    turns = json.load(open(os.path.join(ROOT, "tools/golfer/mixamo_turns.json")))
    rig.offsets = B.person_rig(rig, args.pack, turns["person"])
    ref, root = rig.sample(glb, "ref_address")
    _, p = rig.world(ref, root)
    together = np.linalg.norm(p[rig.index["hand_r"]] - p[rig.index["hand_l"]])
    # How the left hand carries the club alone (the walk's carry: the shaft
    # hanging from the fist).
    carry = rig.sample(glb, CARRY)[0][rig.index["club"]]
    for anim in glb.doc["animations"]:
        name = anim["name"]
        if name in SKIP or name.startswith("ref_") or (args.clip and name not in args.clip):
            continue
        fix_clip(glb, rig, name, club_dir, together, carry)
    if not args.dry:
        glb.doc.setdefault("extras", {})["carry_club"] = 1
        glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
