#!/usr/bin/env python3
"""Fetch the Sketchfab models in models.json and optimise them for the game.

    SKETCHFAB_TOKEN=... python3 tools/sketchfab/fetch.py [NAME ...] [--out DIR]

Needs a Sketchfab API token (sketchfab.com > Settings > Password & API) in
SKETCHFAB_TOKEN; never commit it. Downloads each model's glb, checks its
licence is still the one in models.json, then runs process.mjs (npm install
in this folder first) to write OUT/NAME.glb (default
game/assets/props/sketchfab/). Raw downloads are cached in
~/.cache/openlinks2003/sketchfab/.
"""
import argparse, json, os, subprocess, sys, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
API = "https://api.sketchfab.com/v3/models/"
OPEN = ("CC0", "CC Attribution", "CC BY")


def get(url, token=None):
    req = urllib.request.Request(url, headers={"Authorization": "Token " + token} if token else {})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--out", default=str(REPO / "game/assets/props/sketchfab"))
    a = ap.parse_args()
    token = os.environ.get("SKETCHFAB_TOKEN")
    if not token:
        sys.exit("Set SKETCHFAB_TOKEN to your Sketchfab API token.")
    models = json.loads((HERE / "models.json").read_text())["models"]
    cache = Path.home() / ".cache/openlinks2003/sketchfab"
    cache.mkdir(parents=True, exist_ok=True)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for name in a.names or models:
        m = models[name]
        info = json.loads(get(API + m["uid"], token))
        lic = (info.get("license") or {}).get("label", "")
        if not lic.startswith(OPEN) or "NonCommercial" in lic or "NoDerivs" in lic:
            sys.exit(f"{name}: licence is now '{lic}', not open; leave it out of the repo.")
        raw = cache / (m["uid"] + ".glb")
        if not raw.exists():
            links = json.loads(get(API + m["uid"] + "/download", token))
            raw.write_bytes(get(links["glb"]["url"]))
        dst = out / (name + ".glb")
        subprocess.run(["node", str(HERE / "process.mjs"), str(raw), str(dst), json.dumps(m["opts"])], check=True)
        print(name, "->", dst)


if __name__ == "__main__":
    main()
