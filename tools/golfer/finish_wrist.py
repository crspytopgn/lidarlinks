"""Keeps the lead wrist in its range through the finish of the full swings.

    python3 tools/golfer/finish_wrist.py [--glb game/assets/golfer/free_golfer.glb] [--dry]

mixamo_bake turns the club in the finish so the shaft settles across the
golfer's back (FINISH_SHAFT) and keeps clear of the body (CLEAR). The club
is held in the left hand, so the left wrist took every degree of that turn.
Past impact it bent about 85 degrees back and 60 to 80 toward the thumb
and twisted about 90, where a wrist manages about 70, 20 and 25 (anatomy.py).

Here, for every key after impact, the hand and club are turned together
about the wrist, and the elbow swung round the shoulder-to-wrist line (at
most SWIVEL_MAX), to bring the wrist as far back into its range as it goes
while the shaft keeps pointing where the bake put it (AIM_COST, so the club
still settles behind his back), CLEAR of the spine and off the head. The
wrist stays bent back, not hooked over the grip (FLEX_MAX). The driver's
finish went from about 60 degrees past the wrist's range to about 25. Most of the hand's
twist on the forearm becomes forearm roll (as anatomy.fit_arm does), and the
right arm reaches its place on the grip again (GolferHands does the same in the game).
Runs once per glb (extras.finish_wrist).
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import anatomy as A  # noqa: E402
import glb_edit  # noqa: E402
import mocap_swing as M  # noqa: E402
import pose  # noqa: E402
from mesh_grip import channel, pose_quat, rot_vec  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
CLIPS = {"swing": "ref_address", "swing_iron": "ref_address_iron"}
CLEAR = 0.2  # metres the shaft keeps off the spine behind him (mixamo_bake.CLEAR)
HEAD_CLEAR = 0.16  # and off the middle of his head
TURN_COST = 0.0005  # per degree squared of turn from the baked club
AIM_COST = 1.0  # per degree squared the shaft points away from the baked one
STEADY_COST = 0.02  # per degree squared of change from the last key's turn
SWIVEL_MAX = 40.0  # degrees it may swing at most
SWIVEL_COST = 0.01  # per degree squared the elbow swings round the shoulder-to-wrist line
FLEX_MAX = 10.0  # degrees toward the palm the lead wrist may bend after impact
WRIST_SLACK = 3.0  # degrees inside each limit the fit aims for


def wrist_cost(a, cupped=True):
    """Squared degrees past the wrist's range; `cupped` also keeps the
    wrist bent back (as a tour finish holds it), not hooked over the grip."""
    c = 0.0
    if cupped:
        c += max(0.0, a["wrist_flex"] - FLEX_MAX) ** 2
    for k in ("wrist_flex_l", "wrist_dev_l", "forearm_roll_l"):
        lo, hi = A.limit_of(k)
        v = a[k[:-2]]
        c += max(0.0, lo + WRIST_SLACK - v, v - hi + WRIST_SLACK) ** 2
    return c


class Key:
    """One key of a clip: the world pose, and the hand-and-club turn's cost."""

    def __init__(self, rig, rots, poss, club_dir, length):
        self.rig, self.rots, self.poss = rig, rots, poss
        i = rig.index
        self.U, self.L, self.H = rots[i["upperarm_l"]], rots[i["lowerarm_l"]], rots[i["hand_l"]]
        self.C = rots[i["club"]]
        self.grip = poss[i["club"]]
        self.wrist = poss[i["hand_l"]]
        self.axis = pose.unit(self.wrist - poss[i["upperarm_l"]])
        self.club_dir, self.length = club_dir, length
        self.spine = (poss[i["pelvis"]], poss[i["neck_01"]])
        self.back = rots[i["spine_02"]] @ np.array([0.0, 0.0, -1.0])
        self.head = poss[i["head"]] + rots[i["head"]] @ np.array([0.0, 0.09, 0.0])

    def angles(self, T, sw=0.0):
        S = pose.rot(self.axis, sw)
        return A.arm_angles(self.rig, "l", S @ self.U, S @ self.L, T @ self.H)

    def clear_cost(self, T):
        grip = self.wrist + T @ (self.grip - self.wrist)
        shaft = T @ self.C @ self.club_dir
        a, b = self.spine
        axis = pose.unit(b - a)
        c = 0.0
        for s in np.linspace(0.15, self.length, 10):
            q = grip + shaft * s
            t = np.clip(np.dot(q - a, axis), 0.0, np.linalg.norm(b - a))
            out = q - (a + axis * t)
            if np.dot(out, self.back) <= 0.0:
                c += (max(0.0, CLEAR - np.linalg.norm(out)) / 0.01) ** 2
            c += (max(0.0, HEAD_CLEAR - np.linalg.norm(q - self.head)) / 0.01) ** 2
        return c

    def cost(self, x, last):
        T = rot_vec(np.radians(x[:3]))
        c = wrist_cost(self.angles(T, x[3])) + self.clear_cost(T)
        c += TURN_COST * float(x[:3] @ x[:3]) + SWIVEL_COST * x[3] * x[3]
        c += (max(0.0, abs(x[3]) - SWIVEL_MAX) / 2.0) ** 2
        shaft0 = self.C @ self.club_dir
        aim = np.degrees(np.arccos(np.clip(np.dot(T @ shaft0, shaft0), -1.0, 1.0)))
        c += AIM_COST * aim * aim
        if last is not None:
            d = x - last
            c += STEADY_COST * float(d @ d)
        return c


def impact_key(rig, keys, club_dir, length):
    ball = np.array(M.IMPACT_AT)
    best, at = None, 0
    for k, (rots, poss) in enumerate(keys):
        head = poss[rig.index["club"]] + rots[rig.index["club"]] @ club_dir * length
        d = np.linalg.norm(head - ball)
        if best is None or d < best:
            best, at = d, k
    return at


def roll_forearm(rig, rots):
    """The hand's twist on the forearm, past HAND_TWIST_SHARE, moved into
    the forearm (fit_arm's last step); the hand stays where it is."""
    i = rig.index
    rest = A._ARM_REST[(len(rig.parents), "l")]
    il, ih = i["lowerarm_l"], i["hand_l"]
    tw = pose.twist_angle(rots[il].T @ rots[ih], rest.fore)
    keep = float(np.clip(tw * A.HAND_TWIST_SHARE, -A.HAND_TWIST, A.HAND_TWIST))
    rots[il] = rots[il] @ pose.rot(rest.fore, tw - keep)


def fix_clip(glb, rig, name, ref, club_dir):
    from scipy.optimize import minimize
    i = rig.index
    hl, hr, cj = i["hand_l"], i["hand_r"], i["club"]
    anim = glb.animation(name)
    times = np.array(glb.read(channel(glb, anim, rig.joints[hl], "rotation")["input"]))
    # The right hand's place on the grip, as GolferHands reads it.
    rl, rr = rig.sample(glb, ref)
    rR, rP = rig.world(rl, rr)
    hand_R = rR[hl].T @ rR[hr]
    hand_P = rR[hl].T @ (rP[hr] - rP[hl])
    length = float(np.linalg.norm(np.array(M.IMPACT_AT) - rP[cj]))
    poses = []
    for t in times:
        local, root = rig.sample(glb, name, t)
        rots, poss = rig.world(local, root)
        poses.append((list(rots), poss, root))
    imp = impact_key(rig, [(r, p) for r, p, _ in poses], club_dir, length)
    A.arm_angles(rig, "l", np.eye(3), np.eye(3), np.eye(3))  # caches the rest
    out = {b: [] for b in ("upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r")}
    last, worst = None, [0.0, 0.0]
    for k, (rots, poss, root) in enumerate(poses):
        if k > imp:
            key = Key(rig, rots, poss, club_dir, length)
            x0 = last if last is not None else np.zeros(4)
            before = wrist_cost(key.angles(np.eye(3)))
            x = minimize(key.cost, x0, args=(last,), method="Powell",
                         options={"xtol": 0.05, "ftol": 1e-6, "maxiter": 6000}).x
            T = rot_vec(np.radians(x[:3]))
            a = key.angles(T, x[3])
            after = wrist_cost(a)
            worst = [max(worst[0], math.sqrt(before)), max(worst[1], math.sqrt(after))]
            last = x
            S = pose.rot(key.axis, x[3])
            for j in A.descendants(rig, hl):
                rots[j] = T @ rots[j]
            rots[i["upperarm_l"]] = S @ rots[i["upperarm_l"]]
            rots[i["lowerarm_l"]] = S @ rots[i["lowerarm_l"]]
            roll_forearm(rig, rots)
            rots, poss = rig.world(rig.locals(rots), root)
            rots = list(rots)
            want_R, want_P = rots[hl] @ hand_R, poss[hl] + rots[hl] @ hand_P
            M.two_bone(rig, rots, poss, "upperarm_r", "lowerarm_r", "hand_r", want_P)
            rots[hr] = want_R
            shaft0 = key.C @ club_dir
            aim = np.degrees(np.arccos(np.clip(np.dot(T @ shaft0, shaft0), -1.0, 1.0)))
            print("  %s %.2f s: shaft moved %2.0f deg, elbow swung %3.0f; wrist flex %4.0f, dev %3.0f, roll %4.0f;"
                  " past its range %4.1f -> %4.1f deg" % (name, times[k], aim, x[3], a["wrist_flex"], a["wrist_dev"],
                                                          a["forearm_roll"], math.sqrt(before), math.sqrt(after)))
        loc = rig.locals(rots)
        for b in out:
            out[b].append(pose_quat(loc[i[b]]))
    for b, qs in out.items():
        smp = channel(glb, anim, rig.joints[i[b]], "rotation")
        q = np.asarray(qs, float)
        for n in range(1, len(q)):  # no flips between keys
            if np.dot(q[n], q[n - 1]) < 0.0:
                q[n] = -q[n]
        smp["output"] = glb.add(q.astype(np.float32))
    print("  %s: impact at %.2f s, worst wrist excess %.0f -> %.0f deg" % (name, times[imp], worst[0], worst[1]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default=os.path.join(ROOT, "game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--out")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()
    glb = glb_edit.Glb(args.glb)
    if glb.doc.get("extras", {}).get("finish_wrist"):
        sys.exit("already fixed (extras.finish_wrist)")
    rig = M.Rig(glb)
    club_dir = M.club_direction(glb, rig)
    for name, ref in CLIPS.items():
        if glb.animation(name) is not None:
            fix_clip(glb, rig, name, ref, club_dir)
    if not args.dry:
        glb.doc.setdefault("extras", {})["finish_wrist"] = 1
        glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
