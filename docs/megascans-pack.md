# Megascans pack (private)

Quixel Megascans became free on Fab in November 2026. Its licence lets the
scans be used in a game but not passed on as files, so nothing from it is
in this repository or the web build. Each player who has the scans can bake
a private pack, and the desktop game reads it from `user://megascans/`
(on a Mac, `~/Library/Application Support/Godot/app_userdata/OpenLinks2003/megascans/`),
or from the folder named by the `OL_MEGASCANS` environment variable.

| Pack file | Replaces | Made by |
|---|---|---|
| `foliage/fescue.png` | the drawn fescue tuft atlas (FescueField) | `tools/megascans/fescue_from_scans.py MEGASCANS_DIR OUT.png` |

`fescue_from_scans.py` cuts single photographed blades out of the
Megascans grass atlases (Dune Onion Weed, Canary Grass, Dry Grass, Wild
Grass) and builds four 1 m tufts from them, in the same 2 x 2 layout as
`tools/grass/fescue_atlas.py`. Needs numpy, scipy and Pillow.

Tried and not used: Megascans turf, sand, path and dirt surfaces in place of
the free ground set. Up close on a tee, the lawn scans looked mottled and
clumpy, even with their low frequencies flattened and their colour matched,
and from further back they looked no different.
