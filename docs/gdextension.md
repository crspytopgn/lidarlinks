# GDExtension: the C++ physics core in Godot

Phase 2 (this branch): a thin, verifiable wrapper around `libs/olcore`,
exposing the shot simulation — `olcore::simulate_shot`, with obstacles
and billboards — and the Links launch and swing primitives to the game,
behind a flag, with the GDScript port as the default and the fallback.

## Why this shape

A shot simulation calls the terrain thousands of times per shot
(`height`/`surface`/`normal` per step, up to 3,600 steps in the Links
ground model and 15,000 in the stand-in flight). Calling back into
GDScript for each query is unsafe: shots run on `WorkerThreadPool`
threads, and GDScript objects are not thread-safe. So the game bakes
the ground the shot can reach into plain C++ data *before* the shot
(`OlcoreShotModel` bakes once per hole and caches it), and the
simulation runs entirely in C++ over that snapshot. The C++ that does
this (`extensions/olcore/src/olcore_snapshot.*`) has no Godot headers
and is unit-tested on its own (`olcore_snapshot_tests`).

## What is exposed

In `extensions/olcore/src/`:

- `OlcoreTerrain` — a baked `SnapshotTerrain`. `bake()` takes a grid
  (origin, 1 m cells, heights, surfaces, and per-cell `LinksSurface`
  overrides where the course differs from the class defaults).
  Outside the grid a ball is out of bounds. `bake_obstacles()` adds the
  merged obstacle field the shot can meet (cylinders and boxes, in Godot
  metres); the snapshot answers `obstacle_hit()` from it.
- `OlcoreAero` — Links 2003 drag/lift coefficient tables, built from
  the dictionaries `LinksAero` holds (read from the player's
  executable; nothing from the game is baked into the extension).
- `OlcoreLinksObjects` — the course's billboards and 3D objects for the
  Links model (`set_types()` / `add_billboard()` / `add_mesh()` /
  `add_model()`), in the game's frame (feet, z up), as `LinksObjects`
  holds them.
- `OlcoreClubs` — Links 2003's per-club launch table, built from the
  five arrays `LinksLaunch` holds.
- `OlcorePhysics` — `simulate_shot(...) -> Dictionary` (mirroring
  `ShotResult`) and `make_launch(...)`. With aero set, the Links 2003
  model runs; without it, the stand-in model runs. It is a pure
  function of its arguments, so it is safe on worker threads as long as
  the terrain/aero passed in are not being re-baked at the same time.
  It also exposes the Links launch and swing primitives —
  `links_launch`, `links_putt`, `links_putt_slope`, `links_apply_lie`,
  `links_apply_swing`, `links_meter_contact`,
  `links_clean_strike_speed`, `links_computer_miss`,
  `links_computer_putt_miss`, `links_mouse_swing` — each mirroring its
  GDScript port exactly (same cases, same rand draws, threaded through
  `rng_state`).

In `game/scripts/physics/olcore_shot_model.gd`:

- `OlcoreShotModel` wraps an inner `ShotModel` (Links or Standard) for
  launch, reach and lie power, and runs `simulate()` natively when
  enabled. It bakes a box around the shot (start-to-cup expanded by
  150 m, 1 m cells, capped at 500×500) and caches it per terrain and
  hole, so AI planning and the caddie — dozens of sims from one lie —
  reuse one bake. The bake also carries the merged obstacle field for
  the shot's model (the Links model meets the 3D models' boxes when the
  course has billboards, else the course's own obstacles; the hole's
  own obstacles are always added) and, for the Links model, the
  billboards and 3D objects inside the box. `launch()` runs the Links
  launch natively too (same strike, same draws), falling back to the
  inner model on any failure. `links_model()` / `links_of()` unwrap
  the inner `LinksShotModel` for the AI, the caddie and replays, which
  set Links-only swing flags on it.

## Enabling it

Off by default. Enable with `--native-physics` on the command line or
`LIDARLINKS_NATIVE_PHYSICS=1` in the environment. It never runs on
web: the web preset has `extensions_support=false`, there is no web
library in `olcore.gdextension`, and `native_available()` returns
false there. `AssetProviders` wraps the normal shot model in
`OlcoreShotModel` only when both the flag and the extension are
present.

## Phase 2 — what the native sim now covers

`OlcoreShotModel.simulate()` runs natively for shots with obstacles,
`links_objects` billboards, hole obstacles and model obstacles: they
are baked into the snapshot (obstacles) or passed to the sim
(billboards and 3D objects). The native launch runs too, for the Links
model with a club table. It still falls back to the inner (GDScript)
model whenever the native path cannot run the shot exactly:

- the baked box would be larger than 500×500 cells;
- the native call returns empty (including a native launch failure,
  which restores the inner model's random draws first);
- the ball ends out of bounds within 2 m of the baked box edge (the
  box, not the course, may have cut it short) — the shot is then
  re-simulated in GDScript.

`LinksSurface` records are baked only on greens. Elsewhere the C++
class defaults apply, which is what every course checked so far uses.
Green firmness/speed therefore enter through the baked green cells,
via `Terrain.links_surface_at()`.

## Building it

```bash
git submodule update --init --recursive   # godot-cpp
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_GDEXTENSION=ON
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

The shared library lands in `game/addons/olcore/bin/` as
`libolcore.linux.x86_64.so` (and `.dll` / `.dylib` on Windows/macOS;
macOS needs both `arm64` and `x86_64` builds for the universal
export). The libraries are build products, not committed (`*.so`,
`*.dll`, `*.dylib` are gitignored); CI builds them in the
`gdextension` job and the `export` job downloads them before
`--import`.

godot-cpp is a submodule at `extensions/godot-cpp`, pinned to master
commit `c83a651`. There is no `godot-4.7-stable` godot-cpp release
yet (latest tag is 4.5), and this commit's `extension_api-4-7.json`
matches Godot 4.7. Re-pin to the 4.7 tag when it lands.

## Testing it

```bash
ctest --test-dir build --output-on-failure   # includes olcore_snapshot_tests
```

`olcore_snapshot_tests` checks: a flat snapshot simulates identically
to `FlatTerrain`; a baked slope matches the analytic slope to 0.05 m
on carry; a driver carries 200–300 m; the Links model with aero tables
runs and a headwind shortens the carry; malformed aero tables are
rejected; a shot leaving the baked box ends OutOfBounds without
reading outside the grid; obstacles (trunk, canopy, wall) and Links
billboards and 3D objects meet the ball exactly as olcore does over
its own terrain, and a moved snapshot still meets its obstacles.

With Godot 4.7.2 and the library built:

```bash
godot --headless --path game --import
godot --headless --path game -s res://tests/olcore_smoke.gd
```

The smoke test checks `make_launch` and a flat-driver shot against
the GDScript port (carry/total/apex within 0.01 m) and prints native
vs GDScript ms/shot. It exits 0 with "not loaded" when the extension
is absent. `game/tests/olcore_model_test.gd` (run with
`-- --native-physics`) does the same check through the
`OlcoreShotModel` wrapper, including a second shot that reuses the
baked terrain and shots that meet a trunk, a canopy, a hole obstacle,
a billboard and a 3D wall. `game/tests/olcore_launch_test.gd` (also
with `-- --native-physics` for the whole-launch check) checks every
native launch/swing primitive against the GDScript port on the cases
`run_tests.gd` pins. The full `res://tests/run_tests.gd` suite is unchanged by
this branch (the native path is off by default) and must still print
`GODOT TESTS PASSED`.

## What is still missing (Phase 2)

- A wasm build of the extension for the web, so the web build can use it
  too. The engine-independent core is proven: `libs/olcore` compiles with
  Emscripten 7.0.1 (`~/emsdk`, installed 2026-11-25) and its test binary
  runs under node as wasm (487 KB at `-O2`): all of `test_main.cpp` runs,
  with 2 of ~570 checks failing — both in one cup-roll case
  (`test_links_cup`: the ball rounds the rim and rests; the step count
  and the final x differ by 0.0021 ft against a 0.002 ft tolerance, a
  case the test itself documents as differing ~1e-3 ft between
  compilers). What is still missing for a real web extension is the
  godot-cpp wasm build, the Godot 4.7 web export templates, a web entry
  in the `.gdextension` file, and a browser test. Until then the GDScript
  port is the web implementation and must stay in step with the C++
  (see `CLAUDE.md`). The web preset still has `extensions_support=false`.
- Per-hole bake cost measurement on real courses (the bake is GDScript
  sampling, once per hole, cached) and a bake that reuses the course's
  own heightfield instead of sampling point by point.
