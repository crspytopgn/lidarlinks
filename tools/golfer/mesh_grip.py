"""Fits the club to the golfer's hands as the skin draws them.

    python3 tools/golfer/mesh_grip.py [--glb game/assets/golfer/free_golfer.glb] [--dry]

grip.py laid the grip from the old rig's hand joints with fixed skin
thicknesses. On Michael's Mixamo-rigged golfer (PR #274) that put the grip
through the right hand's knuckles and sank the fingers of both hands 7 to
11 mm into it, with the left fingers lying down the shaft instead of round
it. Here the hands are fitted to the skinned mesh itself (the look pack's
person, posed at ref_address) by least squares:

- no skin inside the grip (a tapered cylinder, grip.py's sizes);
- every finger segment and the thumb resting along the grip;
- the left grip running diagonally from the index finger's first bone to
  the heel pad, the right across the base of the fingers, its little
  finger over the left index finger, clear of the left hand's skin;
- the right wrist hanging nearly straight down the club (RIGHT_WRIST);
- the hands moved and turned as little as that allows.

The result goes into every clip that holds the club that way: the club's
place in the left hand (the hand turns on the wrist so the club keeps its
place in the world, the roll part going to the forearm), the finger turns,
the bodies slid the few millimetres the club moved, and the right arm of
the ref clips, where GolferHands reads the right hand's place on the club.
The putter's palm grip is left as it is. Runs once per glb (extras.mesh_grip).
GRIP_DEBUG=1 prints each bone's contact, GRIP_PICTURE=path draws them.
"""

import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import glb_edit  # noqa: E402
import grip as G  # noqa: E402
import mixamo_bake as B  # noqa: E402
import mocap_swing as M  # noqa: E402
import pose as P_  # noqa: E402
import rocketbox  # noqa: E402
from golf_shoes import load  # noqa: E402

ROOT = rocketbox.ROOT
PACK = os.path.join(ROOT, "game/assets/golfer/free_golfer_parts.olg")


class Skin:
    """The person's skinned body vertices (the parts with hands)."""

    def __init__(self, rig, pack, person):
        info, blob = load(pack)
        who = info["people"][person]
        names = info["bones"]
        span = lambda s, dt: np.frombuffer(bytes(blob[s[0]:s[0] + s[1]]), dt)  # noqa: E731
        e = info["parts"][who["parts"][0]]
        self.pos = span(e["positions"], np.float32).reshape(-1, 3).astype(float)
        self.bones = span(e["bones"], np.int32).reshape(len(self.pos), -1) if e["bones"][1] // len(self.pos) >= 16 else \
            span(e["bones"], np.uint16).reshape(len(self.pos), -1)
        self.weights = span(e["weights"], np.float32).reshape(len(self.pos), -1)
        self.rig_bone = np.array([rig.index.get(n, -1) for n in names])
        binds = who["binds"]
        self.bind = {}
        for k, n in enumerate(names):
            if n in binds:
                # The bone's world pose at the bind; the skin takes its inverse.
                v = binds[n]
                Bw = np.array(v[:9]).reshape(3, 3).T
                self.bind[k] = (Bw.T, -Bw.T @ np.array(v[9:12]))
        top = np.argmax(self.weights, axis=1)
        self.main = self.rig_bone[self.bones[np.arange(len(self.pos)), top]]

    def pick(self, bones):
        return np.isin(self.main, bones)

    def world(self, R, P, mask):
        out = np.zeros((mask.sum(), 3))
        v = self.pos[mask]
        for c in range(self.bones.shape[1]):
            b = self.bones[mask, c]
            w = self.weights[mask, c]
            for k in np.unique(b[w > 0]):
                sel = (b == k) & (w > 0)
                j = self.rig_bone[k]
                if j < 0 or k not in self.bind:
                    continue
                Bb, ob = self.bind[k]
                local = v[sel] @ Bb.T + ob
                out[sel] += w[sel, None] * (local @ R[j].T + P[j])
        return out


def hand_bones(rig, s):
    return [rig.index[n] for n in rig.names if n == "hand_" + s or (n.endswith("_" + s) and n.split("_")[0] in G.FINGERS)]


def report(tag, rig, R, P, skin, club_dir):
    c = rig.index["club"]
    axis = R[c] @ club_dir
    origin = P[c]
    for s in "lr":
        m = skin.pick(hand_bones(rig, s))
        v = skin.world(R, P, m)
        t = (v - origin) @ axis
        off = v - origin - np.outer(t, axis)
        d = np.linalg.norm(off, axis=1)
        on = (t > G.GRIP_BUTT) & (t < G.GRIP_END)
        inside = on & (d < np.array([G.grip_radius(x) for x in t]) - 0.002)
        cen = v.mean(axis=0)
        ct = (cen - origin) @ axis
        cd = np.linalg.norm(cen - origin - ct * axis)
        print("%s %s: centre %.1f cm along, %.1f off; %d of %d verts inside the grip" % (tag, s, ct * 100, cd * 100, inside.sum(), on.sum()))


class Pose:
    """World rotations and positions with turns about a joint carried down
    its subtree."""

    def __init__(self, rig, R, P):
        self.rig = rig
        self.R = [r.copy() for r in R]
        self.P = [p.copy() for p in P]
        self.kids = {j: [k for k in range(len(rig.parents)) if self.under(k, j)] for j in range(len(rig.parents))}

    def under(self, k, j):
        while k >= 0:
            if k == j:
                return True
            k = self.rig.parents[k]
        return False

    def turn(self, j, m):
        piv = self.P[j].copy()
        for k in self.kids[j]:
            self.R[k] = m @ self.R[k]
            self.P[k] = piv + m @ (self.P[k] - piv)

    def move(self, j, d):
        for k in self.kids[j]:
            self.P[k] = self.P[k] + d


class Hand:
    """A hand's skin, carried rigidly by each vertex's main bone."""

    def __init__(self, rig, skin, pose, s):
        self.s = s
        self.bones = hand_bones(rig, s)
        self.local = {}
        for b in self.bones:
            v = skin.world(pose.R, pose.P, skin.pick([b]))
            self.local[b] = (v - pose.P[b]) @ pose.R[b]

    def verts(self, pose, bones):
        return np.concatenate([self.local[b] @ pose.R[b].T + pose.P[b] for b in bones if len(self.local[b])])


class Grip:
    """The club's grip as a tapered cylinder (grip.py's sizes)."""

    def __init__(self, origin, axis):
        self.o, self.a = origin, axis

    def gap(self, v):
        """Each point's distance outside the grip's surface (< 0 inside),
        +inf off the grip's length."""
        t = (v - self.o) @ self.a
        d = np.linalg.norm(v - self.o - np.outer(t, self.a), axis=1)
        out = d - G.grip_radius(t)
        out[(t < G.GRIP_BUTT - 0.005) | (t > G.GRIP_END)] = np.inf
        return out


FINGER_HALF = 0.009  # a gloved finger's half thickness
TOUCH = 0.0015  # skin held this far off the grip (glove, grip texture)


def palm_normal(rig, pose, s):
    x = lambda n: pose.P[rig.index[f"{n}_{s}"]]  # noqa: E731
    n = pose_unit(np.cross(x("index_01") - x("hand"), x("pinky_01") - x("hand")))
    # The fingers curl to the palm.
    if np.dot(x("middle_03") - x("middle_01"), n) < 0:
        n = -n
    return n


def pose_unit(v):
    return v / np.linalg.norm(v)


def _hinge(rig, pose, chain, i, n, s, tip=None):
    """Segment i's hinge (the knuckle line, turning the fingers to the
    palm) and its bend from its parent's line about it, in degrees (> 0
    towards the palm)."""
    x = lambda b: pose.P[rig.index[f"{b}_{s}"]]  # noqa: E731
    j = chain[i]
    if tip is None:
        tip = pose.P[chain[i + 1]] if i < 2 else pose.P[j] + (pose.P[j] - pose.P[chain[i - 1]])
    seg = pose_unit(tip - pose.P[j])
    parent = pose_unit(pose.P[j] - (pose.P[chain[i - 1]] if i else pose.P[rig.index["hand_" + s]]))
    if rig.names[j].startswith("thumb"):
        h = pose_unit(np.cross(seg, n))
    else:
        h = pose_unit(x("pinky_01") - x("index_01"))
    f = pose_unit(x("middle_01") - x("hand"))
    if np.dot(rot(h, 10.0) @ f - f, n) < 0:
        h = -h
    p = parent - h * np.dot(parent, h)
    q = seg - h * np.dot(seg, h)
    bend = np.degrees(np.arctan2(np.dot(np.cross(p, q), h), np.dot(p, q)))
    return h, bend


def rot(axis, deg):
    a = np.radians(deg)
    k = pose_unit(axis)
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + np.sin(a) * K + (1 - np.cos(a)) * K @ K


def channel(glb, anim, node, path):
    for ch in anim["channels"]:
        if ch["target"]["node"] == node and ch["target"]["path"] == path:
            return anim["samplers"][ch["sampler"]]
    return None


def constant(glb, sampler, value):
    """Every key of the sampler set to `value`."""
    n = len(np.array(glb.read(sampler["input"])))
    sampler["output"] = glb.add(np.tile(np.asarray(value, np.float32), (n, 1)))


def family(glb, rig, ref):
    """The clips holding the club as `ref` does: its club joint turned in
    the hand by the same constant."""
    node = rig.joints[rig.index["club"]]
    want = np.array(glb.read(channel(glb, glb.animation(ref), node, "rotation")["output"]))[0]
    out = []
    for anim in glb.doc["animations"]:
        smp = channel(glb, anim, node, "rotation")
        if smp is None:
            continue
        q = np.array(glb.read(smp["output"]))
        if np.max(1.0 - np.abs(q @ want)) < 1e-6:
            out.append(anim["name"])
    return out


class HandFit:
    """A hand placed and its fingers closed round the grip by least
    squares: no skin inside the grip, every finger segment resting on it,
    the hand moved as little as it can."""

    THUMB = ("thumb_01", "thumb_02", "thumb_03")

    def __init__(self, rig, pose, hand, grip, s, turn=True, contact=None, others=(), angle=None, axial=None,
                 patches=(), wrist=None):
        self.rig, self.hand, self.grip, self.s = rig, hand, grip, s
        # (lo, hi): the wrist's sideways bend held in that band, degrees,
        # thumb-ward +, about the elbow as it stands.
        self.wrist = wrist
        self.elbow = pose.P[rig.index["lowerarm_" + s]]
        self.angle, self.axial = angle, axial or {}
        # Patches of skin that rest on the grip: (bone, its vertex rows),
        # picked on the palm side within PATCH_R of a landmark.
        n0 = palm_normal(rig, pose, s)
        self.patches = []
        for bone, at in patches:
            b = rig.index[bone]
            v = hand.verts(pose, [b])
            p = at(pose.P)
            keep = (np.linalg.norm(v - p, axis=1) < PATCH_R) & ((v - p) @ n0 > -0.002)
            self.patches.append((b, np.nonzero(keep)[0]))
        self.turn_ok = turn
        self.others = others
        hj = rig.index["hand_" + s]
        self.hj = hj
        self.R0, self.P0 = pose.R[hj], pose.P[hj]
        n = palm_normal(rig, pose, s)
        self.chains = []
        for f in ("index", "middle", "ring", "pinky", "thumb"):
            chain = [rig.index[f"{f}_0{i}_{s}"] for i in (1, 2, 3)]
            self.chains.append(chain)
        # Each fingertip: the end bone's skin farthest from its joint, as
        # the middle of the pad (in the bone's frame).
        self.tip = {}
        for c in self.chains:
            v = hand.local[c[2]]
            far = v[np.argsort(np.linalg.norm(v, axis=1))[-max(3, len(v) // 10):]]
            self.tip[c[2]] = far.mean(axis=0) * 0.8
        # Each finger bone's rest in its parent and its hinge (own frame).
        self.local, self.hinge, self.bend0, self.spread = {}, {}, {}, {}
        for chain in self.chains:
            thumb = chain[0] == rig.index["thumb_01_" + s]
            for i, j in enumerate(chain):
                p = rig.parents[j]
                self.local[j] = (pose.R[p].T @ pose.R[j], pose.R[p].T @ (pose.P[j] - pose.P[p]))
                tip = pose.P[j] + pose.R[j] @ self.tip[j] if j in self.tip else None
                h, bend = _hinge(rig, pose, chain, i, n, s, tip)
                self.hinge[j] = pose.R[j].T @ h
                self.bend0[j] = bend
                if thumb and i == 0:
                    tip = pose.P[chain[1]] - pose.P[j]
                    self.spread[j] = pose.R[j].T @ pose_unit(np.cross(h, tip))
        self.bones = [j for c in self.chains for j in c]
        self.limits = {}
        for chain in self.chains:
            for i, j in enumerate(chain):
                # Holding a grip: the middle and end joints bend together
                # (no finger flicks straight at the tip).
                self.limits[j] = ((0.0, 95.0), (25.0, 105.0), (20.0, 80.0))[i]
                if chain[0] == rig.index["thumb_01_" + s]:
                    self.limits[j] = ((-40.0, 60.0), (-10.0, 60.0), (-10.0, 80.0))[i]
        # Segments that should rest on the grip.
        self.contact = contact or [j for c in self.chains for j in c[1:]]
        self.nvar = 6 + len(self.bones) + 1

    def apply(self, x):
        t = x[:3] * 0.01
        r = rot_vec(x[3:6] if self.turn_ok else np.zeros(3))
        R, P = {}, {}
        R[self.hj] = r @ self.R0
        P[self.hj] = self.P0 + t
        k = 6
        for chain in self.chains:
            for j in chain:
                p = self.rig.parents[j]
                Rl, Pl = self.local[j]
                m = rot(self.hinge[j], x[k])
                if j in self.spread:
                    m = m @ rot(self.spread[j], x[-1])
                R[j] = R[p] @ Rl @ m
                P[j] = P[p] + R[p] @ Pl
                k += 1
        return R, P

    def verts(self, R, P, bones):
        return [(b, self.hand.local[b] @ R[b].T + P[b]) for b in bones if len(self.hand.local[b])]

    def cost(self, x):
        R, P = self.apply(x)
        c = 0.0
        for b, v in self.verts(R, P, [self.hj] + self.bones):
            g = self.grip.gap(v)
            inside = np.minimum(g - TOUCH, 0.0)
            c += 4e4 * np.sum(inside ** 2) / 1e-6 * 1e-6
            if b in self.contact or b == self.hj:
                # The segment's grip side lies along the grip (its nearest
                # quarter of skin on the surface), so the fingers wrap
                # round it rather than touch it at a point.
                gg = np.sort(g)[:max(3, len(g) // 4)]
                if np.isfinite(gg).all():
                    w = 1.0 if b != self.hj else 0.5
                    c += w * np.mean(np.maximum(gg - TOUCH, 0.0) / 0.002) ** 2
            for o in self.others:
                d = o.gap(v)
                c += 4e4 * np.sum(np.minimum(d, 0.0) ** 2)
        for b, rows in self.patches:
            v = self.hand.local[b][rows] @ R[b].T + P[b]
            g = self.grip.gap(v) if len(v) else np.array([np.inf])
            m = np.min(g)
            if not np.isfinite(m):
                # Off the grip's length: by its distance from the line.
                t = (v - self.grip.o) @ self.grip.a
                m = np.min(np.linalg.norm(v - self.grip.o - np.outer(t, self.grip.a), axis=1)) + 0.02
            c += 3.0 * (max(m - TOUCH, 0.0) / 0.002) ** 2
        # The finger joints and tips hug the grip (a finger's half
        # thickness off its surface), so the fingers curl right round it
        # instead of leaving it at a tangent.
        for chain in self.chains[:4]:
            pts = [P[j] for j in chain[1:]] + [P[chain[2]] + R[chain[2]] @ self.tip[chain[2]]]
            for q in pts:
                t = (q - self.grip.o) @ self.grip.a
                d = np.linalg.norm(q - self.grip.o - t * self.grip.a)
                c += 0.5 * ((d - G.grip_radius(t) - FINGER_HALF) / 0.003) ** 2
        if self.angle is not None:
            # The grip across the fingers at the hand's angle (degrees from
            # the line wrist to middle knuckle).
            f = pose_unit(P[self.rig.index["middle_01_" + self.s]] - P[self.hj])
            ang = np.degrees(np.arccos(np.clip(np.dot(f, self.grip.a), -1, 1)))
            c += ((ang - self.angle) / 4.0) ** 2
        if self.wrist is not None:
            dev = self.deviation(R, P)
            lo, hi = self.wrist
            c += (max(lo - dev, 0.0, dev - hi) / 0.5) ** 2
        for b, want in self.axial.items():
            t = (P[b] - self.grip.o) @ self.grip.a
            c += ((t - want) / 0.005) ** 2
        c += 0.05 * np.sum(x[:3] ** 2) + 0.2 * np.sum(np.degrees(x[3:6]) ** 2) / 100.0
        k = 6
        for j in self.bones:
            lo, hi = self.limits[j]
            b = self.bend0[j] + x[k]
            c += 0.2 * (max(0.0, lo - b) ** 2 + max(0.0, b - hi) ** 2) + 1e-4 * x[k] ** 2
            k += 1
        return c

    def deviation(self, R, P):
        """The wrist's sideways bend: the hand's line (wrist to middle
        knuckle) against the forearm's (elbow to wrist), toward the thumb +."""
        i = lambda n: self.rig.index[f"{n}_{self.s}"]  # noqa: E731
        f = pose_unit(P[self.hj] - self.elbow)
        h = pose_unit(P[i("middle_01")] - P[self.hj])
        across = P[i("index_01")] - P[i("pinky_01")]
        across = pose_unit(across - f * np.dot(across, f))
        return np.degrees(np.arctan2(np.dot(h, across), np.dot(h, f)))

    def solve(self):
        from scipy.optimize import minimize
        x = np.zeros(self.nvar)
        best = minimize(self.cost, x, method="Powell", options={"maxiter": 20000, "xtol": 1e-3, "ftol": 1e-6})
        return best.x


class Blob:
    """Points held off by a radius (the other hand's skin)."""

    def __init__(self, pts, r=0.002):
        from scipy.spatial import cKDTree
        self.tree, self.r = cKDTree(pts), r

    def gap(self, v):
        d, _ = self.tree.query(v)
        return d - self.r


def pose_quat(m):
    return P_.quat(m)


def rot_vec(v):
    a = np.linalg.norm(v)
    return np.eye(3) if a < 1e-9 else rot(v / a, np.degrees(a))


def fit(glb, rig, skin, club_dir, ref, base_offsets):
    """The grip refitted to the drawn hands at `ref`'s address. Returns the
    club's move in the left hand, both hands' finger turns (local) and the
    right hand in the left hand's frame."""
    local, root = rig.sample(glb, ref)
    R, P = rig.world(local, root)
    pose = Pose(rig, R, P)
    hl, hr, cj = rig.index["hand_l"], rig.index["hand_r"], rig.index["club"]
    # The right hand where the game puts it (GolferHands): the stock body's
    # hand_l^-1 hand_r at this ref.
    person = rig.offsets
    rig.offsets = base_offsets
    sR, sP = rig.world(local, root)
    rig.offsets = person
    grip_R = sR[hl].T @ sR[hr]
    grip_P = sR[hl].T @ (sP[hr] - sP[hl])
    pose.turn(hr, pose.R[hl] @ grip_R @ pose.R[hr].T)
    pose.move(hr, pose.P[hl] + pose.R[hl] @ grip_P - pose.P[hr])
    left, right = Hand(rig, skin, pose, "l"), Hand(rig, skin, pose, "r")
    grip = Grip(pose.P[cj], pose.R[cj] @ club_dir)
    report_pose("  before", rig, pose, left, right, grip)
    if os.environ.get("GRIP_PICTURE"):
        picture(os.environ["GRIP_PICTURE"] + "_before_" + ref + ".png", rig, pose, (left, right), grip)
    out = {}
    lf = HandFit(rig, pose, left, grip, "l", angle=LEFT_ANGLE, patches=landmarks(rig, "l"))
    x = lf.solve()
    if os.environ.get("GRIP_DEBUG"):
        for k, j in enumerate(lf.bones):
            print("    %-12s bend %6.1f (was %6.1f, limits %s)" % (rig.names[j], lf.bend0[j] + x[6 + k], lf.bend0[j], lf.limits[j]))
    Rl, Pl = lf.apply(x)
    C_R, C_P = pose.R[cj], pose.P[cj]
    out["club_local"] = (Rl[hl].T @ C_R, Rl[hl].T @ (C_P - Pl[hl]))
    # Back into the hand's own place: the club moves and turns instead.
    MR = pose.R[hl] @ Rl[hl].T
    Mt = pose.P[hl] - MR @ Pl[hl]
    pose.turn(cj, MR @ C_R @ C_R.T)
    pose.P[cj] = pose.P[hl] + pose.R[hl] @ out["club_local"][1]
    for j in lf.bones:
        pose.R[j] = MR @ Rl[j]
        pose.P[j] = MR @ Pl[j] + Mt
    grip = Grip(pose.P[cj], pose.R[cj] @ club_dir)
    lpts = np.concatenate([left.verts(pose, [b]) for b in [hl] + lf.bones if len(left.local[b])])
    li = (pose.P[rig.index["index_02_l"]] - grip.o) @ grip.a
    rf = HandFit(rig, pose, right, grip, "r", others=(Blob(lpts),), angle=RIGHT_ANGLE, patches=landmarks(rig, "r"),
                 axial={rig.index["pinky_02_r"]: li + RIGHT_OVERLAP}, wrist=RIGHT_WRIST)
    R0, P0 = rf.apply(np.zeros(rf.nvar))
    print("  right wrist bend before %.1f deg" % rf.deviation(R0, P0))
    x = rf.solve()
    print("  right wrist bend after %.1f deg" % rf.deviation(*rf.apply(x)))
    Rr, Pr = rf.apply(x)
    pose.turn(hr, Rr[hr] @ pose.R[hr].T)
    pose.move(hr, Pr[hr] - pose.P[hr])
    for j in rf.bones:
        pose.turn(j, Rr[j] @ pose.R[j].T)
    report_pose("  after", rig, pose, left, right, grip)
    if os.environ.get("GRIP_PICTURE"):
        picture(os.environ["GRIP_PICTURE"] + "_" + ref + ".png", rig, pose, (left, right), grip)
    turn = np.degrees(np.arccos(np.clip((np.trace(MR) - 1) / 2, -1, 1)))
    print("  left hand turned %.0f deg on the club; right hand moved %.1f cm, turned %.0f deg" % (
        turn, np.linalg.norm(x[:3]), np.degrees(np.linalg.norm(x[3:6]))))
    out["hand_r"] = (pose.R[hl].T @ pose.R[hr], pose.R[hl].T @ (pose.P[hr] - pose.P[hl]))
    out["fingers"] = {j: pose.R[rig.parents[j]].T @ pose.R[j] for j in lf.bones + rf.bones}
    return out


# The grip's line across each hand, degrees from the wrist-to-middle-
# knuckle line: diagonally across the left palm and fingers, nearer square
# across the base of the right fingers; the right little finger rides on
# the left index finger (overlapping grip), metres along the shaft.
LEFT_ANGLE, RIGHT_ANGLE = 60.0, 75.0
PATCH_R = 0.02


def _mix(a, b, k):
    return lambda P: P[a] + (P[b] - P[a]) * k


def landmarks(rig, s):
    """Where the grip rests on each hand: the left grip runs diagonally from
    the index finger's first bone to the heel pad under the little finger;
    the right lies across the base of the fingers."""
    i = lambda n: rig.index[f"{n}_{s}"]  # noqa: E731
    if s == "l":
        return [("hand_l", _mix(i("hand"), i("pinky_01"), 0.35)),
                ("index_01_l", _mix(i("index_01"), i("index_02"), 0.5))]
    return [(f"{f}_01_r", _mix(i(f + "_01"), i(f + "_02"), 0.4)) for f in ("index", "middle", "ring")]
RIGHT_OVERLAP = 0.0
# The right wrist at address hangs nearly straight down the club, a little
# toward the little finger (tour setups), not bent so the wrist knuckle
# sticks out: degrees, thumb-ward +.
RIGHT_WRIST = (-2.0, 4.0)


def picture(path, rig, pose, hands, grip):
    """Three views of the hands round the grip: down the shaft, and two
    side views; points inside the grip in red."""
    from PIL import Image, ImageDraw
    a = grip.a
    u = pose_unit(np.cross(a, [0.0, 1.0, 0.0]))
    w = np.cross(a, u)
    views = [(u, w), (a, w), (a, u)]
    S, sc = 500, 500 / 0.22
    img = Image.new("RGB", (S * 3, S), "white")
    d = ImageDraw.Draw(img)
    hue = {"hand": (120, 120, 120), "index": (0, 150, 0), "middle": (0, 0, 220), "ring": (220, 150, 0),
           "pinky": (160, 0, 160), "thumb": (0, 170, 170)}
    for k, (x, y) in enumerate(views):
        ox = k * S
        for h in hands:
            for b in h.bones:
                if not len(h.local[b]):
                    continue
                v = h.verts(pose, [b])
                g = grip.gap(v)
                for p, gg in zip(v, g):
                    q = p - grip.o
                    X, Y = ox + S / 2 + np.dot(q, x) * sc, S / 2 - np.dot(q, y) * sc
                    col = (255, 0, 0) if gg < 0 else hue[rig.names[b].split("_")[0]]
                    if h.s == "r" and gg >= 0:
                        col = tuple(int(c * 0.5 + 127) for c in col)
                    d.point((X, Y), fill=col)
        if k == 0:
            r = G.GRIP_R0 * sc
            d.ellipse((ox + S / 2 - r, S / 2 - r, ox + S / 2 + r, S / 2 + r), outline="black")
        else:
            for t in (G.GRIP_BUTT, G.GRIP_END):
                for side in (-1, 1):
                    pass
            p0 = np.dot(a * G.GRIP_BUTT, x) * sc
            p1 = np.dot(a * G.GRIP_END, x) * sc
            r = G.GRIP_R0 * sc
            d.rectangle((ox + S / 2 + min(p0, p1), S / 2 - r, ox + S / 2 + max(p0, p1), S / 2 + r), outline="black")
    img.save(path)


def report_pose(tag, rig, pose, left, right, grip):
    for h in (left, right):
        v = h.verts(pose, h.bones)
        g = grip.gap(v)
        print("%s %s: %d verts inside the grip (deepest %.1f mm), %d touching" % (
            tag, h.s, (g < 0).sum(), -min(0, g.min()) * 1000, ((g >= 0) & (g < 0.004)).sum()))
        if os.environ.get("GRIP_DEBUG"):
            for b in h.bones:
                if len(h.local[b]) == 0:
                    continue
                g = grip.gap(h.verts(pose, [b]))
                print("     %-12s inside %3d deepest %5.1f mm  nearest %5.1f mm" % (rig.names[b], (g < 0).sum(), -min(0, g.min()) * 1000, g.min() * 1000 if np.isfinite(g.min()) else 99))


def turn_hand(glb, rig, anim, delta):
    """The left hand turned by `delta` (its own frame) on the forearm: the
    part about the forearm's line is a forearm roll (lowerarm_l), the rest
    the wrist, so the wrist never twists."""
    joints = rig.joints
    hl, la = rig.index["hand_l"], rig.index["lowerarm_l"]
    hs = channel(glb, anim, joints[hl], "rotation")
    ls = channel(glb, anim, joints[la], "rotation")
    hq = np.array(glb.read(hs["output"])).astype(float)
    lq = np.array(glb.read(ls["output"])).astype(float)
    if len(lq) != len(hq):
        if len(lq) == 1:
            lq = np.repeat(lq, len(hq), axis=0)
        elif len(hq) == 1:
            hq = np.repeat(hq, len(lq), axis=0)
            hs["input"] = ls["input"]
        else:
            raise ValueError("hand and forearm keys differ in " + anim["name"])
    a_l = pose_unit(np.asarray(rig.offsets[hl], float))  # the forearm's line, in its own frame
    hout, lout = [], []
    for h, lo in zip(hq, lq):
        H = P_.matrix(h / np.linalg.norm(h))
        Lo = P_.matrix(lo / np.linalg.norm(lo))
        a_h = H.T @ a_l
        q = pose_quat(delta)  # x, y, z, w
        v = np.asarray(q[:3], float)
        tw = np.dot(v, a_h)
        theta = 2.0 * np.degrees(np.arctan2(tw, q[3]))
        T = rot(a_l, theta)
        lout.append(pose_quat(Lo @ T))
        hout.append(pose_quat(T.T @ H @ delta))
    hs["output"] = glb.add(np.asarray(hout, np.float32))
    ls["input"] = hs["input"]
    ls["output"] = glb.add(np.asarray(lout, np.float32))


HELD = {"ref_address": ("address", "backswing", "swing", "ref_address", "ref_address_v2",
                         "address_iron", "backswing_iron", "swing_iron", "ref_address_iron"),
        "ref_address_putt": ("address_putt", "putt", "ref_address_putt")}


def write(glb, rig, base_offsets, ref, out):
    """The fit into the clips: the club's place in the left hand and the
    left fingers in every clip that holds the club as `ref` does; the right
    fingers in the two-handed ones, their bodies slid so the club head stays
    where it was at address; the right arm of the ref clips (on the stock
    rests GolferHands reads it on) to the new right hand."""
    joints = rig.joints
    cj, hl, hr = rig.index["club"], rig.index["hand_l"], rig.index["hand_r"]
    local, root = rig.sample(glb, ref)
    R, P = rig.world(local, root)
    old_R = local[cj]
    new_R, new_t = out["club_local"]
    # The hand turns on the wrist so the club keeps its place in the world.
    delta = old_R @ new_R.T
    H_R = R[hl] @ delta
    slide = -((P[hl] + H_R @ new_t) - P[cj])
    names = family(glb, rig, ref)
    for name in names:
        anim = glb.animation(name)
        smp = channel(glb, anim, joints[cj], "translation")
        if smp is None:
            t = glb.add(np.zeros(1, np.float32), minmax=True)
            anim["samplers"].append({"input": t, "output": glb.add(np.asarray([new_t], np.float32)),
                                     "interpolation": "LINEAR"})
            anim["channels"].append({"sampler": len(anim["samplers"]) - 1, "target": {"node": joints[cj], "path": "translation"}})
        else:
            constant(glb, smp, new_t)
        constant(glb, channel(glb, anim, joints[cj], "rotation"), pose_quat(new_R))
        turn_hand(glb, rig, anim, delta)
        two = name in HELD[ref]
        for j, m in out["fingers"].items():
            if rig.names[j].endswith("_r") and not two:
                continue
            smp = channel(glb, anim, joints[j], "rotation")
            if smp is not None:
                constant(glb, smp, pose_quat(m))
        if two and not name.startswith("ref_"):
            smp = channel(glb, anim, joints[0], "translation")
            v = np.array(glb.read(smp["output"])).astype(float) + slide
            smp["output"] = glb.add(v.astype(np.float32))
    for name in HELD[ref]:
        if not name.startswith("ref_") or glb.animation(name) is None:
            continue
        local, root = rig.sample(glb, name)
        saved = rig.offsets
        rig.offsets = base_offsets
        rots, poss = rig.world(local, root)
        hR, hP = out["hand_r"]
        for _ in range(6):
            want_R, want_P = rots[hl] @ hR, poss[hl] + rots[hl] @ hP
            M.two_bone(rig, rots, poss, "upperarm_r", "lowerarm_r", "hand_r", want_P)
            rots[hr] = want_R
            rots, poss = rig.world(rig.locals(rots), root)
            short = want_P - poss[hr]
            if np.linalg.norm(short) < 1e-4:
                break
            # Out of the stock right arm's reach: the left hand comes the
            # rest of the way (only the hands' relation is read from here).
            keep = rots[hl].copy()
            M.two_bone(rig, rots, poss, "upperarm_l", "lowerarm_l", "hand_l", poss[hl] - short * 1.05)
            rots[hl] = keep
            rots, poss = rig.world(rig.locals(rots), root)
        want_P = poss[hl] + rots[hl] @ hP
        miss = np.linalg.norm(poss[hr] - want_P)
        rig.offsets = saved
        loc = rig.locals(rots)
        anim = glb.animation(name)
        for b in ("upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r"):
            j = rig.index[b]
            constant(glb, channel(glb, anim, joints[j], "rotation"), pose_quat(loc[j]))
        print("  %s: right arm to the new grip (%.1f mm short)" % (name, miss * 1000))
    print("  %d clips: club moved in the hand, bodies slid %.1f cm" % (len(names), np.linalg.norm(slide) * 100))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default=os.path.join(ROOT, "game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--out")
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()
    turns = json.load(open(os.path.join(ROOT, "tools/golfer/mixamo_turns.json")))
    glb = glb_edit.Glb(args.glb)
    rig = M.Rig(glb)
    base = rig.offsets
    rig.offsets = B.person_rig(rig, PACK, turns["person"])
    skin = Skin(rig, PACK, turns["person"])
    club_dir = M.club_direction(glb, rig)
    if glb.doc.get("extras", {}).get("mesh_grip"):
        sys.exit("already fitted (extras.mesh_grip): run on the committed glb")
    # The putter's palm grip (putt_posture.palm_grip) is left as it is.
    for ref in ("ref_address",):
        print(ref)
        cache = os.environ.get("GRIP_CACHE")
        if cache and os.path.exists(cache + ref):
            import pickle
            out = pickle.load(open(cache + ref, "rb"))
        else:
            out = fit(glb, rig, skin, club_dir, ref, base)
            if cache:
                import pickle
                pickle.dump(out, open(cache + ref, "wb"))
        if not args.dry:
            write(glb, rig, base, ref, out)
    if not args.dry:
        glb.doc.setdefault("extras", {})["mesh_grip"] = 1
        glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
