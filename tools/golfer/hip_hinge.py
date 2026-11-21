"""Stands the golfer taller over the ball: less knee bend, more hip hinge.

    python3 tools/golfer/hip_hinge.py [--glb game/assets/golfer/free_golfer.glb] [--dry]

The Mixamo takes (with sit_lower's 3 cm on top) had the knees bent about
39 degrees at address and 46 at impact, a sitting, squatting look. Tour
players flex the knees 20 to 25 degrees at address (swing_posture.py's
photos and numbers) and bend from the hips with a flat back, the seat out.

Here, in every full-swing clip, the hips are raised LIFT (the knees
straightening by two-bone IK, the feet exactly where they were), and the
trunk tips forward about the hips until the shoulders are as far from the
hands as before, so both arms reach their hands again by two-bone IK
(their elbows' bend planes kept) and the hands, the club and so the strike
don't move at all. The head keeps its turn, so the eyes stay on the ball.
The change fades out after impact (FADE_FROM to FADE_TO seconds into the
swing clips), so the finish, where he stands up anyway, is the take's.
Runs once per glb (extras.hip_hinge), after sit_lower.
"""

import argparse
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import glb_edit  # noqa: E402
import mixamo_bake as B  # noqa: E402
import mocap_swing as M  # noqa: E402
import pose  # noqa: E402
from mesh_grip import PACK, channel, pose_quat  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
LIFT = 0.025  # metres the hips rise (most of sit_lower's drop: the hinge reaches the ball instead)
FADE_FROM = 0.40  # seconds into a swing clip where the change starts to fade
FADE_TO = 0.65  # and is gone
CLIPS = ("address", "backswing", "swing", "address_iron", "backswing_iron", "swing_iron",
         "ref_address", "ref_address_v2", "ref_address_iron")
LEGS = ("thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r")
ARMS = ("upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r")
MOVED = ("pelvis",) + LEGS + ARMS + ("head",)
ACROSS = np.array([1.0, 0.0, 0.0])  # the target line (target at -x)


def knee_flex(rig, P, s):
    i = rig.index
    a, b, c = P[i["thigh_" + s]], P[i["calf_" + s]], P[i["foot_" + s]]
    u, v = a - b, c - b
    return 180.0 - math.degrees(math.acos(np.clip(np.dot(u, v) / np.linalg.norm(u) / np.linalg.norm(v), -1, 1)))


def reach(rig, P, hands):
    """Each shoulder's distance to where its hand must be (metres)."""
    i = rig.index
    return np.array([np.linalg.norm(hands[s][1] - P[i["upperarm_" + s]]) for s in "lr"])


def weight(name, t):
    if not name.startswith("swing"):
        return 1.0
    if t <= FADE_FROM:
        return 1.0
    if t >= FADE_TO:
        return 0.0
    x = (t - FADE_FROM) / (FADE_TO - FADE_FROM)
    return 1.0 - x * x * (3 - 2 * x)


def posed(rig, local, root, lift, hinge):
    """World rotations and positions with the hips `lift` higher and the
    pelvis (so the trunk) tipped `hinge` degrees toward the ball."""
    i = rig.index
    local = [m.copy() for m in local]
    root2 = np.array(root, float) + np.array([0.0, lift, 0.0])
    R, P = rig.world(local, root2)
    R = list(R)
    pel = i["pelvis"]
    # Tip toward the ball (-z): about +x, the front of the trunk going down.
    R[pel] = pose.rot(ACROSS, -hinge) @ R[pel]
    loc = rig.locals(R)
    # Only the pelvis turned: its children keep their locals.
    for j in range(len(loc)):
        if j != pel:
            loc[j] = local[j]
    return rig.world(loc, root2), loc, root2


def fix_key(rig, local, root, w):
    i = rig.index
    R0, P0 = rig.world(local, root)
    feet = {s: (R0[i["foot_" + s]].copy(), P0[i["foot_" + s]].copy()) for s in "lr"}
    hands = {s: (R0[i["hand_" + s]].copy(), P0[i["hand_" + s]].copy()) for s in "lr"}
    head = R0[i["head"]].copy()
    want = reach(rig, P0, hands)
    lift = LIFT * w
    # The hinge that puts the shoulders back at their hands' distances
    # (least squares over both arms), so the elbows keep their bend.
    best, hinge = None, 0.0
    for h in np.arange(-10.0, 30.01, 0.25):
        (_, P), _, _ = posed(rig, local, root, lift, h)
        e = float(np.sum((reach(rig, P, hands) - want) ** 2))
        if best is None or e < best:
            best, hinge = e, float(h)
    (R, P), loc, root2 = posed(rig, local, root, lift, hinge)
    rots = list(R)
    for s in "lr":
        for _ in range(3):
            M.two_bone(rig, rots, P, "thigh_" + s, "calf_" + s, "foot_" + s, feet[s][1])
            rots[i["foot_" + s]] = feet[s][0]
            rots, P = rig.world(rig.locals(rots), root2)
            rots = list(rots)
        for _ in range(3):
            M.two_bone(rig, rots, P, "upperarm_" + s, "lowerarm_" + s, "hand_" + s, hands[s][1])
            rots[i["hand_" + s]] = hands[s][0]
            rots, P = rig.world(rig.locals(rots), root2)
            rots = list(rots)
    rots[i["head"]] = head
    rots, P = rig.world(rig.locals(rots), root2)
    err = max(float(np.linalg.norm(P[i["hand_" + s]] - hands[s][1])) for s in "lr")
    flex = (knee_flex(rig, P0, "l"), knee_flex(rig, P0, "r"), knee_flex(rig, P, "l"), knee_flex(rig, P, "r"))
    return rig.locals(rots), root2, hinge, err, flex


def fix_clip(glb, rig, name):
    anim = glb.animation(name)
    i = rig.index
    rs = channel(glb, anim, rig.joints[0], "translation")
    times = np.array(glb.read(channel(glb, anim, rig.joints[i["pelvis"]], "rotation")["input"]))
    rv = np.array(glb.read(rs["output"])).astype(float)
    rt = np.array(glb.read(rs["input"]))
    if len(rt) != len(times):
        raise ValueError("root and pelvis keys differ in " + name)
    out = {b: [] for b in MOVED}
    worst, report = 0.0, None
    for k, t in enumerate(times):
        local, root = rig.sample(glb, name, float(t))
        loc, root2, hinge, err, flex = fix_key(rig, local, root, weight(name, float(t)))
        worst = max(worst, err)
        if k == 0:
            report = (hinge, flex)
        rv[k] = root2
        for b in MOVED:
            out[b].append(pose_quat(loc[i[b]]))
    rs["output"] = glb.add(rv.astype(np.float32))
    for b, qs in out.items():
        smp = channel(glb, anim, rig.joints[i[b]], "rotation")
        if smp is None:
            raise ValueError("%s has no %s rotation" % (name, b))
        if len(glb.read(smp["input"])) != len(times):
            raise ValueError("%s: %s keys differ" % (name, b))
        q = np.asarray(qs, float)
        for n in range(1, len(q)):
            if np.dot(q[n], q[n - 1]) < 0.0:
                q[n] = -q[n]
        smp["output"] = glb.add(q.astype(np.float32))
    hinge, flex = report
    print("  %-17s %3d keys  first key: hinge %+.1f deg, knees %.0f/%.0f -> %.0f/%.0f, hands off %.1f mm"
          % (name, len(times), hinge, flex[0], flex[1], flex[2], flex[3], worst * 1000))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default=os.path.join(ROOT, "game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--out")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    if glb.doc.get("extras", {}).get("hip_hinge"):
        sys.exit("already done (extras.hip_hinge)")
    rig = M.Rig(glb)
    turns = json.load(open(os.path.join(ROOT, "tools/golfer/mixamo_turns.json")))
    rig.offsets = B.person_rig(rig, PACK, turns["person"])
    for name in CLIPS:
        if glb.animation(name) is not None:
            fix_clip(glb, rig, name)
    if not args.dry:
        glb.doc.setdefault("extras", {})["hip_hinge"] = 1
        glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
