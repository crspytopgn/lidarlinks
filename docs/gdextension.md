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
`LIDARLINKS_NATIVE_PHYSICS=1` in the environment. On web there is no
command line, so `use_native_enabled()` returns `native_available()`
there: the web build uses the native sim whenever the wasm extension
is present, and the GDScript port whenever it is absent (the extension
is a wasm side module, `libolcore.web.wasm32.wasm`, loaded from the
web export; see "Building it" below). `AssetProviders` wraps the
normal shot model in `OlcoreShotModel` only when both the flag and the
extension are present.

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
cmake --build build --parallel 2
ctest --test-dir build --output-on-failure
```

Two jobs at a time, not an unbounded build: godot-cpp's biggest
translation units each take several GB to compile, and an unbounded
build OOM-kills the compiler on small machines and CI runners.

The shared library lands in `game/addons/olcore/bin/` as
`libolcore.linux.x86_64.so` (and `.dll` / `.dylib` on Windows/macOS;
macOS needs both `arm64` and `x86_64` builds for the universal
export). The libraries are build products, not committed (`*.so`,
`*.dll`, `*.dylib`, `*.wasm` are gitignored). In CI, `.github/workflows/ci.yml`
calls `.github/workflows/gdextension.yml` as a reusable workflow, so
the build runs inside the CI run and the `export` job can download
its artifacts: the four `olcore-gdext-<os>-<arch>` artifacts, merged
into `game/addons/olcore/bin/`, before `--import`. The `gdextension`
workflow also runs standalone — on pushes to `main` and `perf/**`
and on PRs touching `extensions/olcore`, `libs/olcore` or
`game/addons/olcore` — for fast feedback without running the export.

If the extension build fails, the export still runs: the `export`
job starts anyway (its `if: always()` only requires the launcher
templates), the download ignores missing artifacts, and the "Check
GDExtension libraries" step reports which libraries are present and
warns — in the log and on the job summary — when a desktop export
falls back to the GDScript physics port. A missing library is a loud
fallback, not a silent one, and the failed `gdextension` job still
fails the run overall. A web export from CI never gets a library (there is no wasm job
in the workflow yet), so it runs the GDScript port.

### Web (wasm)

The web build ships the same extension as a wasm side module
(`libolcore.web.wasm32.wasm`, entry `web.wasm32` in
`olcore.gdextension`), and the web preset has
`extensions_support=true` with `thread_support=false` (the export
uses the `web_dlink_nothreads_release` template). Build it with
Emscripten **4.0.20** — the version the Godot 4.7.2 export templates
were built with (the string is in the template's `index.wasm`):

```bash
source ~/emsdk/emsdk_env.sh   # after `emsdk activate 4.0.20`
emcmake cmake -S . -B build-wasm -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_GDEXTENSION=ON -DGODOTCPP_THREADS=OFF
cmake --build build-wasm --target olcore_gdext --parallel
```

Three things about this build are load-bearing, all found the hard
way (2026-11-26) — each one fails in the browser with a bare
`function signature mismatch` or `TypeError: resolved is not a
function` that names neither the symbol nor the cause:

- **Emscripten 4.0.20.** The templates were built with it; a side
  module built with another version disagrees with the engine about
  the dynamic-link ABI.
- **Hidden visibility at compile time** (`-fvisibility=hidden
  -fvisibility-inlines-hidden` on `olcore_gdext`,
  `olcore_snapshot`, `olcore`, and `olcore_noexcept`; godot-cpp
  sets it itself). A web export loads the extension as an Emscripten
  side module, and any symbol left at default visibility joins the
  dynamic symbol table. Emscripten then emits the side module's own
  functions as imports from `env`; Godot cannot supply them, so the
  loader substitutes a stub of another arity and the first indirect
  call through it aborts (in our case the `StringName` destructor
  pointer call inside `D_METHOD`). Visibility is fixed when a
  translation unit is compiled, so a link option alone does nothing.
- **No SJLJ exceptions in the extension's copy of the core**
  (`olcore_noexcept`, built without `-fexceptions`). The `olcore`
  copy used by the standalone tests is compiled with `-fexceptions`
  so they can catch the loaders' `ReadError`/`InflateError`, but
  that emits `invoke_*` calls (SJLJ landing pads) in every object,
  including the sim files. The Godot web template does not export
  `invoke_*` (the engine is not built with SJLJ exceptions), so the
  loader stubs them and the first sim call fails with `TypeError:
  resolved is not a function`. The extension never calls a throwing
  function (no loaders, no decompression in the sim path), so its
  copy is safe without exceptions. Do not "fix" this with
  `-fwasm-exceptions`: the engine template does not export the
  `__cpp_exception` tag, so such a module cannot even instantiate.

The web export itself is the usual `godot --headless --path game
--export-release "Web" export/web/index.html` (release template;
`--export-debug` works the same way). The GDScript port stays the
fallback: if the wasm file is missing, `native_available()` is false
and the game runs the GDScript sim, exactly as on desktop without
the `.so`.

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

### Web smoke test

`olcore_smoke.gd` cannot be run in the browser with `-s`: the web
export templates (release and debug alike) are built without
`OVERRIDE_PATH_ENABLED`, so the engine clears the script argument
and always runs the main scene. To run the same checks in the
browser, temporarily wire the checks as an autoload (a `Node` script
that runs them in `_ready` and prints `OLCORE NATIVE SMOKE PASSED`
without quitting), temporarily drop `tests/*` from the Web preset's
`exclude_filter`, export, serve the export over HTTP and load it in
a browser (headless Chromium works). Revert the preset edit and
remove the autoload afterwards; neither belongs in the repo. The
browser result (2026-11-26, headless Chromium): native and GDScript
both carried 188.93 m / 202.55 m total on the flat driver, native
4.9 ms/shot vs GDScript 106.9 ms/shot (n=20).

## What is still missing (Phase 2)

- A wasm build of the extension for the web, so the web build can use it
  too. The engine-independent core is proven: `libs/olcore` compiles with
  Emscripten 4.0.20 (`~/emsdk`) and all three test binaries run under node
  as wasm and pass (`olcore_tests`, `olcourse_tests`, `olcvt_tests`, exit 0;
  verified 2026-11-26):
  ```
  source ~/emsdk/emsdk_env.sh   # after `emsdk activate 4.0.20`
  emcmake cmake -S libs/olcore -B build-wasm -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS_RELEASE="-O2 -DNDEBUG"
  cmake --build build-wasm --parallel
  node build-wasm/olcore_tests.js   # and olcourse_tests.js, olcvt_tests.js
  ```
  `-fexceptions` is needed and is now in `libs/olcore/CMakeLists.txt`:
  the loaders throw `ReadError`/`InflateError` and the tests catch them,
  and without it the wasm binary aborts in `test_reader_bounds`.
  The cup-roll case (`test_links_cup`) passes under wasm with the
  loosened tolerance the test documents: native stops on step 63 at
  (-0.084640, 0.641452), wasm on step 65 at (-0.086740, 0.643333) — a
  0.0021 ft difference on a rim-exit knife-edge (same code, same `Rest`
  outcome, out past the hole), inside the allowed 63–65 steps and
  3e-3 ft on x. The numbers are identical under Emscripten 7.0.1 and
  4.0.20, so the divergence is a stable wasm-libm property, not a
  version quirk. What is still missing for a real web extension is a
  browser test. The godot-cpp wasm build, the Godot 4.7 web export
  templates, the web entry in the `.gdextension` file and the web
  preset (`extensions_support=true`) are all in place: the extension
  builds as a wasm side module (see `extensions/olcore/CMakeLists.txt`;
  Emscripten 4.0.20 is required — a 7.0.1 side module fails to load in
  the browser with a signature mismatch), and a headless web export
  (`godot --headless --path game --export-release "Web"
  export/web/index.html`, verified 2026-11-26) produces
  `export/web/index.html` whose `GODOT_CONFIG` lists
  `"gdextensionLibs":["libolcore.web.wasm32.wasm"]`, with the side
  module beside it. A browser run (2026-11-26, headless Chromium)
  confirms it: the extension loads, `OlcorePhysics` registers, and
  the smoke checks pass (see "Web smoke test" above), so the web
  build now runs the native sim when the extension is present and
  the GDScript port when it is absent. The CI `gdextension` workflow
  has no wasm job yet, and the CI export job does not download a wasm
  artifact, so a web export from CI still runs the GDScript port —
  that wiring is follow-up, not part of this branch.- Per-hole bake cost measurement on real courses (the bake is GDScript
  sampling, once per hole, cached) and a bake that reuses the course's
  own heightfield instead of sampling point by point.
