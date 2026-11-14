"""Bakes Mixamo golf animations into the free golfer's clips, exactly.

    python3 tools/golfer/mixamo_bake.py --glb game/assets/golfer/free_golfer.glb \\
        --clip swing=golf_drive:242:330 [--clip name=take:start:end[:club[:loop]]] ...

The takes are Michael's animations on his golfer rigged by Mixamo
(mixamo_person.py put that rig's skin and joints in the look pack), dumped
by mixamo_dump.gd to MIXAMO_DIR/<take>.json (default
~/.cache/openlinks/mixamo2; not redistributable, kept out of the repo).
Every bone takes the recorded turn from Mixamo's rest, carried through
the turn from that rest to ours (mixamo_turns.json), so the person in the
pack moves exactly as on mixamo.com; the pelvis follows the recorded hips.

Takes face +x with the target at -z; the rig faces -z with the target at
-x. Mixamo's actor swung without a club: it is set in the lead hand at
the clip's address (`club`: driver, iron or putter, from the matching
ref_ pose) with the head on the ball, and over the downswing it is turned
in the hand by up to the few degrees that bring the head back onto the
ball at impact, then eased back.
"""

import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import glb_edit  # noqa: E402
import mocap_swing as M  # noqa: E402
import pose  # noqa: E402
import rocketbox  # noqa: E402
from golf_shoes import load  # noqa: E402

ROOT = rocketbox.ROOT
MIXAMO_DIR = os.environ.get("MIXAMO_DIR", os.path.expanduser("~/.cache/openlinks/mixamo2"))
FPS = 30.0


def facing(bones, m_rots, m_poss, f, stand):
    """The turn about +y that sets the take the rig's way at frame f: a
    stance's feet along the target line (the lead foot at -x), or a
    standing take (`stand`) facing the target (-x)."""
    if stand:
        k = bones.index("mixamorig_Hips")
        d = m_rots[f, k] @ np.array([0.0, 0.0, 1.0])
        want = np.array([-1.0, 0.0, 0.0])
    else:
        d = m_poss[f, bones.index("mixamorig_LeftFoot")] - m_poss[f, bones.index("mixamorig_RightFoot")]
        want = np.array([-1.0, 0.0, 0.0])
    a = np.arctan2(d[0], d[2]) - np.arctan2(want[0], want[2])
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0.0, -s], [0.0, 1.0, 0.0], [s, 0.0, c]])
REFS = {"driver": "ref_address", "iron": "ref_address_iron", "putter": "ref_address_putt"}


def take(name):
    d = json.load(open(os.path.join(MIXAMO_DIR, name + ".json")))
    f = np.array(d["frames"], dtype=float)
    rots = f[:, :, :9].reshape(len(f), -1, 3, 3).transpose(0, 1, 3, 2)
    rots /= np.linalg.norm(rots, axis=2, keepdims=True)
    poss = f[:, :, 9:12]
    if np.abs(poss[0, :, 1]).max() < 0.1:
        poss = poss * 100.0
    return d["bones"], rots, poss


def person_rig(rig, pack, name):
    """The rig's local joint offsets for the person (as _fit_skeleton)."""
    info, _ = load(pack)
    offsets = info["people"][name]["joints"]
    moved = []
    out = []
    for j, p in enumerate(rig.parents):
        inherited = moved[p] if p >= 0 else np.zeros(3)
        moved.append(np.array(offsets.get(rig.names[j], inherited), dtype=float))
        out.append(rig.offsets[j] + moved[j] - inherited)
    return out


def bake(glb, rig, turns, name, take_name, start, end, club="driver", loop=False, addr=None):
    """`club` "stand": a take standing up (a reaction), turned to face the
    target and set where the address stands, the driver kept in hand.
    `addr`: the take's address frame, where the club is set in the hand
    and the take placed (default `start`), so that a backswing and the
    swing from its top share them."""
    addr = start if addr is None else addr
    bones, m_rots, m_poss = take(take_name)
    stand = club == "stand"
    if stand:
        club = "driver"
    FACE = facing(bones, m_rots, m_poss, addr, stand)
    index = {b: k for k, b in enumerate(bones)}
    T = np.array(turns["turn"])
    rest = turns["mixamo_rest"]
    # Each rig bone's Mixamo bone (the first one mapped to it) and its
    # rest turn.
    source = {}
    for b in bones:
        if rocketbox.primary(b):
            source.setdefault(rocketbox.our_bone(b), b)
    fixed = {}
    for ours, b in source.items():
        if ours not in turns["rot"] or b not in rest:
            continue
        basis = np.array(rest[b]["basis"], dtype=float).reshape(3, 3).T
        basis /= np.linalg.norm(basis, axis=0, keepdims=True)
        fixed[rig.index[ours]] = (index[b], basis.T @ T.T @ np.array(turns["rot"][ours]).T)
    ref_local, ref_root = rig.sample(glb, REFS[club])
    pel, cj = rig.index["pelvis"], rig.index["club"]
    hl = rig.index[os.environ.get("CLUB_HAND", "hand_r")]
    hips = index["mixamorig_Hips"]

    def posed(f):
        rots = [None] * len(rig.names)
        rots[0] = np.eye(3)
        for j, (k, after) in fixed.items():
            rots[j] = FACE @ m_rots[f, k] @ after
        rots = M.fill(rig, rots, ref_local)
        root = FACE @ m_poss[f, hips] - rig.offsets[pel]
        return rots, root

    # The club in the lead hand at the first frame, as the ref pose holds
    # it (its length), aimed from the grip down to the turf straight out
    # in front; the take is slid so its head is on the ball.
    ref_rots, ref_poss = rig.world(ref_local, ref_root)
    ball = np.array(M.IMPACT_AT)
    club_dir = M.club_direction(glb, rig)
    ref_head = ref_poss[cj] + ref_rots[cj] @ club_dir * 1.0
    length = float(np.linalg.norm(ball - ref_poss[cj]))
    rots0, root0 = posed(addr)
    _, p0 = rig.world(rig.locals(rots0), root0)
    grip = p0[cj]
    drop = min(grip[1] - ball[1], length * 0.95)
    head = np.array([grip[0], ball[1], grip[2] - np.sqrt(length * length - drop * drop)])
    club_local = rots0[hl].T @ M.between(rots0[cj] @ club_dir, pose.unit(head - grip)) @ rots0[cj]
    slide = np.array([ball[0] - head[0], 0.0, ball[2] - head[2]])
    if stand:
        slide = ref_poss[pel] - p0[pel]
        slide[1] = 0.0
    del ref_head
    frames = []
    for f in range(start, end + 1):
        rots, root = posed(f)
        rots[cj] = rots[hl] @ club_local
        frames.append((rots, root + slide))
    # Impact: after the hands' highest point, the frame the head comes
    # closest to the ball.
    heads, hands = [], []
    for rots, root in frames:
        r, p = rig.world(rig.locals(rots), root)
        heads.append(p[cj] + r[cj] @ club_dir * length)
        hands.append(p[hl][1])
    # Impact: the first frame the hands are back down at address height
    # within a second of being well above it (the top); the head's nearest
    # pass of the ball there.
    hand0 = p0[hl][1]
    impact = top = None
    if club != "putter" and not stand:
        for i in range(len(frames)):
            back = max(hands[max(0, i - int(FPS)):i + 1]) if i > 0 else hands[0]
            if back - hand0 > 0.4 and hands[i] - hand0 < 0.12:
                near = range(max(0, i - 3), min(len(frames), i + 4))
                impact = min(near, key=lambda k: np.linalg.norm(heads[k] - ball))
                top = max(range(max(0, impact - int(FPS)), impact + 1), key=lambda k: hands[k])
                break
    if impact is not None:
        miss = [np.linalg.norm(heads[impact] - ball)]
        rots, root = frames[impact]
        r, p = rig.world(rig.locals(rots), root)
        fix_w = M.between(heads[impact] - p[cj], ball - p[cj])
        fix = r[hl].T @ fix_w @ r[hl]
        print("  top %d, impact %d (%.2f s from the top), head %.0f cm off the ball, turned %.1f deg" % (
            start + top, start + impact, (impact - top) / FPS, 100 * min(miss),
            np.degrees(np.arccos(np.clip((np.trace(fix) - 1) / 2, -1, 1)))))
        for i, (rots, root) in enumerate(frames):
            if i <= impact:
                w = 0.0 if i <= top else (i - top) / max(impact - top, 1)
            else:
                w = max(0.0, 1.0 - (i - impact) / (0.4 * FPS))
            w = w * w * (3 - 2 * w)
            rots[cj] = rots[hl] @ pose.slerp(np.eye(3), fix, w) @ club_local
    times = [i / FPS for i in range(len(frames))]
    out = [rig.locals(r) for r, _ in frames]
    roots = [root for _, root in frames]
    if loop:
        out, roots = out + out[:1], roots + roots[:1]
        # A single frame held: a still address two seconds long, so the
        # game's random start in a looping clip has room.
        times = times + [len(frames) / FPS if len(frames) > 1 else 2.0]
    M.write_clip(glb, rig, name, times, out, roots, filtered=False)
    print("%s: %s %d-%d, %.2f s, club %s" % (name, take_name, start, end, times[-1], club))
    return {"top": top, "impact": impact}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--out")
    ap.add_argument("--pack", default=os.path.join(ROOT, "game/assets/golfer/free_golfer_parts.olg"))
    ap.add_argument("--turns", default=os.path.join(ROOT, "tools/golfer/mixamo_turns.json"))
    ap.add_argument("--clip", action="append", default=[], help="name=take:start:end[:club[:loop|-[:address frame]]]")
    args = ap.parse_args()
    turns = json.load(open(args.turns))
    glb = glb_edit.Glb(args.glb)
    rig = M.Rig(glb)
    rig.offsets = person_rig(rig, args.pack, turns["person"])
    for c in args.clip:
        name, spec = c.split("=")
        p = spec.split(":")
        bake(glb, rig, turns, name, p[0], int(p[1]), int(p[2]), p[3] if len(p) > 3 else "driver",
             len(p) > 4 and p[4] == "loop", int(p[5]) if len(p) > 5 else None)
    glb.save(args.out or args.glb)


if __name__ == "__main__":
    main()
