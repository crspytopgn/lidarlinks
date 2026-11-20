"""A new lead arm through the finish, so the lead wrist ends inside its range.

    python3 tools/golfer/finish_pose.py [--glb game/assets/golfer/free_golfer.glb] [--dry]

finish_wrist.py turns the hand and club about the wrist and swings the
elbow, but the hands stay where the bake put them, so with the shaft held
across his back the lead wrist was still cocked about 40 degrees toward the
thumb where a wrist goes about 20 (25 degrees past its range at the end of
the driver's finish). A tour finish folds the lead arm instead: the hands
come in and up by the lead shoulder and the elbow points down, so the
forearm lines up under the shaft and the wrist barely needs to cock.

Here, for every key after impact, the lead wrist may also move (at most
MOVE_MAX, the arm bending to reach it by two-bone IK), on top of
finish_wrist's turn of hand and club and its elbow swing. The shaft keeps
pointing where the bake put it (AIM_COST), CLEAR of the spine and off the
head; the hands keep off the head and chest (BODY_CLEAR); and each key
changes smoothly from the last (STEADY_COST) and the move eases in after
impact (EASE_KEYS), so the through swing isn't touched. The right arm
reaches its place on the grip again, as in finish_wrist. Runs once per glb
(extras.finish_pose), after finish_wrist.
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import anatomy as A  # noqa: E402
import finish_wrist as F  # noqa: E402
import glb_edit  # noqa: E402
import mocap_swing as M  # noqa: E402
import pose  # noqa: E402
from mesh_grip import channel, pose_quat, rot_vec  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
MOVE_MAX = 0.18  # metres the lead wrist may move from the baked finish
MOVE_COST = 0.02  # per centimetre squared it moves
AIM_COST = 0.3  # per degree squared the shaft points away from the baked one
TURN_COST = 0.0005  # per degree squared of turn of hand and club
SWIVEL_MAX = 40.0
SWIVEL_COST = 0.01
STEADY_COST = 0.05  # per unit squared of change from the last key
BODY_CLEAR = 0.12  # metres the lead wrist keeps from the head and the chest line
EASE_KEYS = 3  # keys after impact over which the allowed move grows to full


class Key(F.Key):
    """One key, with the lead arm free to fold (finish_wrist.Key plus a wrist move)."""

    def __init__(self, rig, rots, poss, root, club_dir, length):
        super().__init__(rig, rots, poss, club_dir, length)
        self.root = root
        self.chest = poss[rig.index["spine_03"]] if "spine_03" in rig.index else poss[rig.index["spine_02"]]

    def posed(self, x):
        """World rotations and positions with x = (turn xyz deg, swivel deg, move xyz cm)."""
        rig, i = self.rig, self.rig.index
        hl = i["hand_l"]
        T = rot_vec(np.radians(x[:3]))
        rots = list(self.rots)
        poss = self.poss.copy()
        move = np.asarray(x[4:7]) * 0.01
        M.two_bone(rig, rots, poss, "upperarm_l", "lowerarm_l", "hand_l", self.wrist + move)
        rots, poss = rig.world(rig.locals(rots), self.root)
        rots = list(rots)
        # The elbow swung round the new shoulder-to-wrist line.
        axis = pose.unit(poss[hl] - poss[i["upperarm_l"]])
        S = pose.rot(axis, x[3])
        rots[i["upperarm_l"]] = S @ rots[i["upperarm_l"]]
        rots[i["lowerarm_l"]] = S @ rots[i["lowerarm_l"]]
        # Hand and club keep their baked world turn, then the fit's turn.
        for j in A.descendants(rig, hl):
            rots[j] = T @ self.rots[j]
        rots, poss = rig.world(rig.locals(rots), self.root)
        return T, list(rots), poss

    def cost(self, x, last, room):
        T, rots, poss = self.posed(x)
        i = self.rig.index
        a = A.arm_angles(self.rig, "l", rots[i["upperarm_l"]], rots[i["lowerarm_l"]], rots[i["hand_l"]])
        c = F.wrist_cost(a)
        # Clearance of the shaft from the spine and head, from the new grip.
        grip, shaft = poss[i["club"]], rots[i["club"]] @ self.club_dir
        a0, b0 = self.spine
        ax = pose.unit(b0 - a0)
        for s in np.linspace(0.15, self.length, 10):
            q = grip + shaft * s
            t = np.clip(np.dot(q - a0, ax), 0.0, np.linalg.norm(b0 - a0))
            out = q - (a0 + ax * t)
            if np.dot(out, self.back) <= 0.0:
                c += (max(0.0, F.CLEAR - np.linalg.norm(out)) / 0.01) ** 2
            c += (max(0.0, F.HEAD_CLEAR - np.linalg.norm(q - self.head)) / 0.01) ** 2
        w = poss[i["hand_l"]]
        for p in (self.head, self.chest):
            c += (max(0.0, BODY_CLEAR - np.linalg.norm(w - p)) / 0.01) ** 2
        shaft0 = self.C @ self.club_dir
        aim = np.degrees(np.arccos(np.clip(np.dot(shaft, shaft0), -1.0, 1.0)))
        c += AIM_COST * aim * aim
        move = np.asarray(x[4:7])
        c += TURN_COST * float(x[:3] @ x[:3]) + SWIVEL_COST * x[3] * x[3] + MOVE_COST * float(move @ move)
        c += (max(0.0, abs(x[3]) - SWIVEL_MAX) / 2.0) ** 2
        c += (max(0.0, float(np.linalg.norm(move)) - room * 100.0) / 0.5) ** 2
        if last is not None:
            d = x - last
            c += STEADY_COST * float(d @ d)
        return c


def fix_clip(glb, rig, name, ref, club_dir):
    from scipy.optimize import minimize
    i = rig.index
    hl, hr = i["hand_l"], i["hand_r"]
    anim = glb.animation(name)
    times = np.array(glb.read(channel(glb, anim, rig.joints[hl], "rotation")["input"]))
    rl, rr = rig.sample(glb, ref)
    rR, rP = rig.world(rl, rr)
    hand_R = rR[hl].T @ rR[hr]
    hand_P = rR[hl].T @ (rP[hr] - rP[hl])
    length = float(np.linalg.norm(np.array(M.IMPACT_AT) - rP[i["club"]]))
    poses = []
    for t in times:
        local, root = rig.sample(glb, name, t)
        rots, poss = rig.world(local, root)
        poses.append((list(rots), poss, root))
    imp = F.impact_key(rig, [(r, p) for r, p, _ in poses], club_dir, length)
    A.arm_angles(rig, "l", np.eye(3), np.eye(3), np.eye(3))  # caches the rest
    bones = ("upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r")
    out = {b: [] for b in bones}
    last, worst = None, [0.0, 0.0]
    for k, (rots, poss, root) in enumerate(poses):
        if k > imp:
            key = Key(rig, rots, poss, root, club_dir, length)
            room = MOVE_MAX * min(1.0, (k - imp) / float(EASE_KEYS))
            x0 = last if last is not None else np.zeros(7)
            before = F.wrist_cost(key.angles(np.eye(3)), False)
            x = minimize(key.cost, x0, args=(last, room), method="Powell",
                         options={"xtol": 0.05, "ftol": 1e-6, "maxiter": 12000}).x
            T, rots, poss = key.posed(x)
            F.roll_forearm(rig, rots)
            rots, poss = rig.world(rig.locals(rots), root)
            rots = list(rots)
            a = A.arm_angles(rig, "l", rots[i["upperarm_l"]], rots[i["lowerarm_l"]], rots[hl])
            after = F.wrist_cost(a, False)
            worst = [max(worst[0], math.sqrt(before)), max(worst[1], math.sqrt(after))]
            last = x
            want_R, want_P = rots[hl] @ hand_R, poss[hl] + rots[hl] @ hand_P
            M.two_bone(rig, rots, poss, "upperarm_r", "lowerarm_r", "hand_r", want_P)
            rots[hr] = want_R
            print("  %s %.2f s: wrist moved %4.1f cm, elbow swung %3.0f; flex %4.0f, dev %3.0f, roll %4.0f;"
                  " past its range %4.1f -> %4.1f deg" % (name, times[k], float(np.linalg.norm(x[4:7])), x[3],
                                                          a["wrist_flex"], a["wrist_dev"], a["forearm_roll"],
                                                          math.sqrt(before), math.sqrt(after)))
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
    extras = glb.doc.get("extras", {})
    if extras.get("finish_pose"):
        sys.exit("already fixed (extras.finish_pose)")
    if not extras.get("finish_wrist"):
        sys.exit("run finish_wrist.py first")
    rig = M.Rig(glb)
    club_dir = M.club_direction(glb, rig)
    for name, ref in F.CLIPS.items():
        if glb.animation(name) is not None:
            fix_clip(glb, rig, name, ref, club_dir)
    if not args.dry:
        glb.doc.setdefault("extras", {})["finish_pose"] = 1
        glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
