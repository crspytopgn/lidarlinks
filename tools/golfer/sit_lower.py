"""Sits the golfer a little lower over the ball in the club clips.

    python3 tools/golfer/sit_lower.py [--glb game/assets/golfer/free_golfer.glb] [--dry]

The drawn person's hips stand DROP higher than the joints the takes were
baked on, so his hands, and the club in them, rode too high to reach the
ball (see club_length.py, which makes up the rest with real club lengths).
Here the body is lowered by DROP in every clip that addresses or strikes the
ball, the knees bending (two-bone IK) so the feet stay exactly where they
were. Runs once per glb (extras.sit_lower).
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
from mesh_grip import PACK, channel, pose_quat  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
DROP = 0.03
CLIPS = ("address", "backswing", "swing", "address_iron", "backswing_iron", "swing_iron",
         "address_putt", "putt", "ref_address", "ref_address_v2", "ref_address_iron", "ref_address_putt")
LEGS = ("thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r")


def lower(glb, rig, name):
    anim = glb.animation(name)
    i = rig.index
    rs = channel(glb, anim, rig.joints[0], "translation")
    times = np.array(glb.read(channel(glb, anim, rig.joints[i["thigh_l"]], "rotation")["input"]))
    rt = np.array(glb.read(rs["input"]))
    rv = np.array(glb.read(rs["output"])).astype(float)
    if len(rt) != len(times) and len(rt) != 1:
        raise ValueError("root and leg keys differ in " + name)
    out = {b: [] for b in LEGS}
    for t in times:
        local, root = rig.sample(glb, name, float(t))
        R, P = rig.world(local, root)
        feet = {s: (R[i["foot_" + s]].copy(), P[i["foot_" + s]].copy()) for s in "lr"}
        root2 = np.array(root, float) - np.array([0.0, DROP, 0.0])
        rots, poss = rig.world(local, root2)
        rots = list(rots)
        for s in "lr":
            for _ in range(3):
                M.two_bone(rig, rots, poss, "thigh_" + s, "calf_" + s, "foot_" + s, feet[s][1])
                rots[i["foot_" + s]] = feet[s][0]
                rots, poss = rig.world(rig.locals(rots), root2)
                rots = list(rots)
        loc = rig.locals(rots)
        for b in LEGS:
            out[b].append(pose_quat(loc[i[b]]))
    rv[:, 1] -= DROP
    rs["output"] = glb.add(rv.astype(np.float32))
    for b, qs in out.items():
        smp = channel(glb, anim, rig.joints[i[b]], "rotation")
        q = np.asarray(qs, float)
        for n in range(1, len(q)):
            if np.dot(q[n], q[n - 1]) < 0.0:
                q[n] = -q[n]
        smp["output"] = glb.add(q.astype(np.float32))
    print("  %-17s %3d keys lowered %.0f cm" % (name, len(times), DROP * 100))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default=os.path.join(ROOT, "game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--out")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    if glb.doc.get("extras", {}).get("sit_lower"):
        sys.exit("already done (extras.sit_lower)")
    rig = M.Rig(glb)
    turns = json.load(open(os.path.join(ROOT, "tools/golfer/mixamo_turns.json")))
    rig.offsets = B.person_rig(rig, PACK, turns["person"])
    for name in CLIPS:
        if glb.animation(name) is not None:
            lower(glb, rig, name)
    if not args.dry:
        glb.doc.setdefault("extras", {})["sit_lower"] = 1
        glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
