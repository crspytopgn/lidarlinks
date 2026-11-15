"""Puts a realistic person rigged by Mixamo's auto-rigger into the look pack.

    python3 tools/golfer/mixamo_person.py --fbx "Golf Drive.fbx" [--name Male_Adult_14]
        [--pack game/assets/golfer/free_golfer_parts.olg] [--glb game/assets/golfer/free_golfer.glb]
        [--godot godot] [--turns tools/golfer/mixamo_turns.json]

The person (a Rocketbox scan, exported with game/tests/export_golfer_obj.gd)
was rigged on mixamo.com and downloaded "With Skin": the same mesh, now with
Mixamo's joints and skin weights, which bend the shoulders, elbows and hips
far better than the Biped's. The FBX is not redistributable and stays out of
the repo; what goes in the pack is the person's own mesh with the weights
moved onto our bones.

As rocketbox.py: the mesh is turned to face the rig's way and laid into the
rig's rest pose for the joints, and the person's joints become joint
offsets; the mesh keeps Mixamo's rest pose with a bind per bone. It keeps
Mixamo's joints exactly ("exact"), since the golf clips are baked for them
(mixamo_direct.py), and writes each bone's turn from Mixamo's rest to ours
(the turns file) for that bake. The person's textures, clothing regions and
materials already in the pack stay; their caps are rebuilt on the new head.
"""

import argparse
import json
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import person_cap  # noqa: E402
import rocketbox  # noqa: E402
from golf_shoes import load, save  # noqa: E402
from look_pack import tangents  # noqa: E402

ROOT = rocketbox.ROOT
TURN = np.diag([-1.0, 1.0, -1.0])  # rocketbox.person's: Mixamo's rest faces +z


def dump(fbx, godot, out):
    """rocketbox_dump.gd's arrays, in metres (Mixamo's FBX comes in at a
    hundredth) with duplicate vertices merged."""
    if not os.path.exists(out + ".json"):
        subprocess.run([godot, "--headless", "--path", os.path.join(ROOT, "game"), "-s",
                        os.path.join(ROOT, "tools", "golfer", "rocketbox_dump.gd"), "--", fbx, out],
                       check=True, capture_output=True)
    d = json.load(open(out + ".json"))
    blob = open(out + ".bin", "rb").read()

    def arr(e, k, dt, cols):
        o, n = e[k]
        return np.frombuffer(blob[o:o + n], dt).reshape(-1, cols)
    height = max(b["origin"][1] for b in d["bones"])
    scale = 100.0 if height < 0.1 else 1.0
    for b in d["bones"]:
        b["origin"] = [v * scale for v in b["origin"]]
    for s in d["surfaces"]:
        pos = arr(s, "positions", np.float32, 3).astype(np.float64) * scale
        nrm = arr(s, "normals", np.float32, 3).astype(np.float64)
        uvs = arr(s, "uvs", np.float32, 2)
        bones = arr(s, "bones", np.int32, s["per"])
        weights = arr(s, "weights", np.float32, s["per"])
        idx = arr(s, "indices", np.int32, 3)
        # The FBX has every triangle corner apart; one vertex per position
        # and uv, its normal the corners' mean (smooth shading).
        key = np.concatenate([np.round(pos * 1e5), np.round(uvs * 1e5)], 1)
        _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
        inverse = inverse.reshape(-1)
        smooth = np.zeros((len(first), 3))
        np.add.at(smooth, inverse, nrm)
        smooth /= np.maximum(np.linalg.norm(smooth, axis=1, keepdims=True), 1e-9)
        s.update({"positions": pos[first], "normals": smooth, "uvs": uvs[first], "bones": bones[first],
                  "weights": weights[first], "indices": inverse[idx]})
        # "m012_bodymat" -> the pack's "body" part.
        s["material"] = "body" if "body" in s["material"] else "head"
    return d


def compact(info, blob):
    """The pack's blob without the arrays nothing refers to any more (the
    person's old meshes): every [offset, length] span in the info, copied
    once each, in order."""
    spans = set()

    def walk(o, fix=None):
        if isinstance(o, dict):
            for v in o.values():
                walk(v, fix)
        elif isinstance(o, list):
            if (len(o) == 2 and all(type(x) is int for x in o) and o[1] > 0 and o[0] % 4 == 0
                    and o[0] + o[1] <= len(blob)):
                if fix is None:
                    spans.add((o[0], o[1]))
                else:
                    o[0] = fix[(o[0], o[1])]
            else:
                for x in o:
                    walk(x, fix)
    walk(info)
    out = bytearray()
    moved = {}
    for off, n in sorted(spans):
        while len(out) % 4:
            out.append(0)
        moved[(off, n)] = len(out)
        out.extend(blob[off:off + n])
    walk(info, moved)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fbx", required=True)
    ap.add_argument("--name", default="Male_Adult_14")
    ap.add_argument("--pack", default=os.path.join(ROOT, "game/assets/golfer/free_golfer_parts.olg"))
    ap.add_argument("--glb", default=os.path.join(ROOT, "game/assets/golfer/free_golfer.glb"))
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/openlinks/mxperson"))
    ap.add_argument("--turns", default=os.path.join(ROOT, "tools/golfer/mixamo_turns.json"))
    args = ap.parse_args()
    os.makedirs(args.cache, exist_ok=True)
    d = dump(args.fbx, args.godot, os.path.join(args.cache, "dump"))
    rig = rocketbox.rig_rest(args.glb)
    out = {}
    surfaces, offsets, height = rocketbox.person(d, rig, exact=True, out=out)
    # The mesh stays in Mixamo's rest pose (only turned the rig's way) and
    # each bone gets its own bind there: Mixamo's joint, turned by the
    # bone's turn back from the rig's rest. Posed by clips baked through
    # the same turns, the skin is then exactly Mixamo's, one blend of bone
    # transforms (laying the mesh into the rig's rest first blended twice
    # and pinched the shoulders).
    for s, raw in zip(surfaces, d["surfaces"]):
        s["positions"] = (raw["positions"] @ TURN.T).astype(np.float32)
        s["normals"] = (raw["normals"] @ TURN.T).astype(np.float32)
    binds = {}
    for b, r in out["rot"].items():
        basis = np.asarray(r).T  # the bone's frame at Mixamo's rest
        binds[b] = [float(v) for v in list(basis[:, 0]) + list(basis[:, 1]) + list(basis[:, 2]) + list(out["from"][b])]
    height = float(max(s["positions"][:, 1].max() for s in surfaces))
    info, blob = load(args.pack)

    def put(array, dtype):
        a = np.ascontiguousarray(array, dtype=dtype)
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(a.tobytes())
        return [off, a.nbytes]
    who = info["people"][args.name]
    for s in surfaces:
        part = "RB_%s_%s" % (args.name, s["material"])
        old = info["parts"][part]
        pos, nrm, uvs, idx = s["positions"], s["normals"], s["uvs"], s["indices"]
        entry = {"material": old["material"], "count": int(len(pos)), "positions": put(pos, np.float32),
                 "normals": put(nrm.astype(np.float16), np.float16), "uvs": put(uvs, np.float32),
                 "bones": put(s["joints"], np.int32), "weights": put(s["weights"], np.float32),
                 "indices": put(idx, np.int32), "shapes": {}}
        if "tangents" in old:
            entry["tangents"] = put(tangents(pos.astype(np.float64), nrm.astype(np.float64), uvs.astype(np.float64),
                                             idx).astype(np.float16), np.float16)
        info["parts"][part] = entry
        print("%s: %d vertices, %d triangles (was %d vertices)" % (part, len(pos), len(idx), old["count"]))
    person_cap.add(info, blob, args.name)
    who["joints"] = offsets
    who["height"] = height
    who["binds"] = binds
    save(args.pack, info, compact(info, blob))
    # Each rig bone's turn from Mixamo's rest (in the rig's frame) to the
    # rig's rest pose, for mixamo_direct.py.
    turns = {b: np.asarray(r).tolist() for b, r in out["rot"].items()}
    rest = {b["name"]: {"origin": b["origin"], "basis": b["basis"]} for b in d["bones"]}
    json.dump({"person": args.name, "turn": TURN.tolist(), "rot": turns, "mixamo_rest": rest},
              open(args.turns, "w"), indent=1)
    print("%s: %.2f m, %d joints, turns in %s" % (args.name, height, len(offsets), args.turns))


if __name__ == "__main__":
    main()
