// Tests for the GDExtension snapshot core (olcore_snapshot). No Godot
// needed: these check the C++ that the extension calls, against olcore
// itself and against the numbers the GDScript tests pin
// (game/tests/run_tests.gd, from libs/olcore/tests/test_main.cpp).
//
// Build with -DBUILD_GDEXTENSION=ON; run with ctest.
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include "olcore/ball_physics.hpp"
#include "olcore/links_flight.hpp"
#include "olcore/links_ground.hpp"
#include "olcore/links_objects.hpp"
#include "olcore/obstacles.hpp"
#include "olcore/shot.hpp"
#include "olcore/swing.hpp"
#include "olcore/terrain.hpp"
#include "olcore_snapshot.hpp"

namespace {
int failures = 0;
int checks = 0;

void check(bool ok, const char* what) {
  ++checks;
  if (!ok) {
    ++failures;
    std::printf("  FAIL: %s\n", what);
  }
}

void check_near(double got, double want, double tol, const char* what) {
  ++checks;
  if (std::fabs(got - want) > tol) {
    ++failures;
    std::printf("  FAIL: %s: got %.6f want %.6f (tol %.6f)\n", what, got, want, tol);
  }
}

olcore_gdext::SnapshotGrid flat_grid(olcore::Surface surface, double height, int nx = 64, int nz = 64,
                                     double cell = 1.0, double origin = -32.0) {
  olcore_gdext::SnapshotGrid g;
  g.origin_x = origin;
  g.origin_z = origin;
  g.cell = cell;
  g.nx = nx;
  g.nz = nz;
  g.heights.assign(static_cast<std::size_t>(nx) * nz, height);
  g.surfaces.assign(static_cast<std::size_t>(nx) * nz, static_cast<std::uint8_t>(surface));
  return g;
}

// A slope rising 0.1 m per metre in +z, as an analytic Terrain and as a
// baked snapshot, so the two can be compared shot for shot.
class SlopeTerrain : public olcore::Terrain {
 public:
  double height(double, double z) const override { return 0.1 * z; }
  olcore::Surface surface(double, double) const override { return olcore::Surface::Fairway; }
};

olcore_gdext::SnapshotGrid slope_grid() {
  olcore_gdext::SnapshotGrid g;
  g.origin_x = -100.0;
  g.origin_z = -100.0;
  g.cell = 1.0;
  g.nx = 201;
  g.nz = 201;
  g.heights.resize(static_cast<std::size_t>(g.nx) * g.nz);
  g.surfaces.assign(static_cast<std::size_t>(g.nx) * g.nz,
                    static_cast<std::uint8_t>(olcore::Surface::Fairway));
  for (int iz = 0; iz < g.nz; ++iz) {
    for (int ix = 0; ix < g.nx; ++ix) {
      g.heights[g.index(ix, iz)] = 0.1 * (g.origin_z + iz * g.cell);
    }
  }
  return g;
}

// Tables with real aerodynamic force, so wind can act on the ball: drag
// 0.25 and lift 0.15 everywhere (lift 0 at zero spin, as the game's
// tables have it).
olcore::LinksAero windy_aero() {
  std::vector<double> speeds{0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300};
  std::vector<double> spins{0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 120, 150, 200};
  std::vector<double> drag(11 * 14, 0.25);
  std::vector<double> lift(11 * 14, 0.15);
  for (int i = 0; i < 11; ++i) lift[static_cast<std::size_t>(i) * 14] = 0.0;
  return olcore::LinksAero{olcore::CoefficientTable{speeds, spins, drag},
                           olcore::CoefficientTable{speeds, spins, lift}};
}

const olcore::Club& club_by_name(const char* short_name) {
  for (const olcore::Club& c : olcore::standard_clubs()) {
    if (std::string(c.short_name) == short_name) return c;
  }
  return olcore::standard_clubs().front();
}

void test_flat_snapshot_is_exact() {
  // A flat fairway baked at 1 m must simulate identically to FlatTerrain:
  // the snapshot must not distort the ground the ball plays on.
  olcore::BallState start = olcore::make_launch(60.0, 12.0, 0.0, 6000.0, 0.0);
  start.position = {0, 0, 0};
  // The box must cover the whole shot (a driver carries ~190 m), or the
  // ball leaves it and ends OutOfBounds — that is the out-of-box test's
  // job, not this one's.
  olcore_gdext::SnapshotTerrain snap(flat_grid(olcore::Surface::Fairway, 0.0, 512, 512));
  olcore_gdext::NativeShotResult a = olcore_gdext::run_shot(start, {}, nullptr, snap, false, {});
  olcore_gdext::NativeShotResult b =
      olcore_gdext::run_shot_flat(start, {}, nullptr, olcore::Surface::Fairway, 0.0, false, {});
  check(a.outcome == b.outcome, "flat snapshot outcome matches FlatTerrain");
  check_near(a.carry_m, b.carry_m, 1e-9, "flat snapshot carry matches FlatTerrain");
  check_near(a.total_m, b.total_m, 1e-9, "flat snapshot total matches FlatTerrain");
  check_near(a.apex_m, b.apex_m, 1e-9, "flat snapshot apex matches FlatTerrain");
  check(a.bounces == b.bounces, "flat snapshot bounces match FlatTerrain");
  check(a.points.size() == b.points.size(), "flat snapshot path length matches FlatTerrain");
  std::printf("  flat driver: carry %.2f m, total %.2f m, apex %.2f m\n", a.carry_m, a.total_m, a.apex_m);
}

void test_slope_snapshot_parity() {
  // Bilinear interpolation of a plane is exact, so a slope baked at 1 m
  // must match the analytic slope to within a centimetre on carry.
  olcore::BallState start = olcore::make_launch(45.0, 18.0, 0.0, 5000.0, 0.0);
  start.position = {0, 0, -50.0};
  SlopeTerrain analytic;
  olcore::BallParams p;
  olcore::ShotResult want = olcore::simulate_shot(start, p, analytic);
  olcore_gdext::SnapshotTerrain snap(slope_grid());
  olcore_gdext::NativeShotResult got = olcore_gdext::run_shot(start, {}, nullptr, snap, false, {});
  check(got.outcome == static_cast<int>(want.outcome), "slope snapshot outcome matches analytic");
  check_near(got.carry_m, want.carry_m, 0.05, "slope snapshot carry matches analytic");
  check_near(got.total_m, want.total_m, 0.10, "slope snapshot total matches analytic");
  std::printf("  slope 7i: carry %.2f m (analytic %.2f m)\n", got.carry_m, want.carry_m);
}

void test_driver_carry_is_plausible() {
  // Same guard as the olcore tests: a driver must carry roughly 200-300 m.
  olcore::BallState start = olcore::make_launch(75.0, 11.0, 0.0, 2500.0, 0.0);
  start.position = {0, 0, 0};
  olcore_gdext::NativeShotResult r =
      olcore_gdext::run_shot_flat(start, {}, nullptr, olcore::Surface::Fairway, 0.0, false, {});
  check(r.outcome == 0, "driver comes to rest");
  check(r.carry_m > 200.0 && r.carry_m < 300.0, "driver carry is plausible");
  check(r.total_m > r.carry_m, "driver rolls past its carry");
  std::printf("  driver: carry %.2f m, total %.2f m\n", r.carry_m, r.total_m);
}

void test_links_model_runs_on_snapshot() {
  // With Links aero tables the same entry point must run the Links model
  // (simulate_links_shot) instead of the stand-in: a 7-iron with the
  // still-air tables must carry in the Links range the olcore tests pin
  // (100-250 m) and a headwind must shorten it.
  // With still-air tables (zero drag/lift) the Links model runs, but
  // wind has nothing to act through. Use tables with real force for the
  // wind check.
  olcore::LinksAero aero = windy_aero();
  olcore_gdext::AeroTables tables;
  tables.aero = aero;
  tables.valid = true;
  olcore::BallState launch = olcore::launch_from_swing(club_by_name("7i"), {}, olcore::Surface::Fairway);
  launch.position = {0, 0, 0};
  olcore_gdext::SnapshotTerrain snap(flat_grid(olcore::Surface::Fairway, 0.0, 512, 512));
  olcore_gdext::NativeShotResult calm = olcore_gdext::run_shot(launch, {}, &tables, snap, false, {});
  olcore_gdext::NativeShotResult head = olcore_gdext::run_shot(launch, {0, 0, -8}, &tables, snap, false, {});
  check(calm.carry_m > 100.0 && calm.carry_m < 250.0, "links 7i carry is in range");
  check(head.carry_m < calm.carry_m, "links headwind shortens the carry");
  std::printf("  links 7i: carry %.2f m, headwind carry %.2f m\n", calm.carry_m, head.carry_m);
}

void test_aero_table_validation() {
  std::vector<double> speeds{0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300};
  std::vector<double> spins{0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 120, 150, 200};
  std::vector<double> values(11 * 14, 0.2);
  olcore_gdext::AeroTables ok = olcore_gdext::AeroTables::from_arrays(speeds, spins, values, speeds, spins,
                                                                     values);
  check(ok.valid, "well-formed aero tables are accepted");
  std::vector<double> short_values(10, 0.2);
  olcore_gdext::AeroTables bad = olcore_gdext::AeroTables::from_arrays(speeds, spins, short_values, speeds,
                                                                      spins, values);
  check(!bad.valid, "short aero tables are rejected");
  std::vector<double> bad_speeds = speeds;
  bad_speeds[5] = bad_speeds[4];
  olcore_gdext::AeroTables bad2 = olcore_gdext::AeroTables::from_arrays(bad_speeds, spins, values, speeds,
                                                                       spins, values);
  check(!bad2.valid, "non-ascending aero speeds are rejected");
}

void test_out_of_bounds_outside_box() {
  // A ball that leaves the baked box must end OutOfBounds, never read
  // outside the grid.
  olcore::BallState start = olcore::make_launch(75.0, 11.0, 0.0, 2500.0, 0.0);
  start.position = {0, 0, 0};
  // A 10 m box: the driver flies far past it.
  olcore_gdext::SnapshotTerrain snap(flat_grid(olcore::Surface::Fairway, 0.0, 10, 10));
  olcore_gdext::NativeShotResult r = olcore_gdext::run_shot(start, {}, nullptr, snap, false, {});
  check(r.outcome == static_cast<int>(olcore::ShotOutcome::OutOfBounds),
        "shot leaving the baked box ends OutOfBounds");
  // The rest is just outside the box (where the ball left it) — it must
  // be finite, and the sim must have terminated instead of reading
  // outside the grid.
  check(std::isfinite(r.rest.x) && std::isfinite(r.rest.y) && std::isfinite(r.rest.z),
        "out-of-box rest is finite");
}

// The same obstacle cases as test_trees_stop_the_ball in test_main.cpp and
// _test_obstacles_match_olcore in run_tests.gd, run over a snapshot: the
// baked field must meet the ball exactly as olcore's own field does.
void test_snapshot_obstacles_match_olcore() {
  olcore::BallState drive = olcore::launch_from_swing(club_by_name("Dr"), {}, olcore::Surface::Tee);
  drive.position = {0, 0, 0};
  olcore::BallParams p;

  olcore::ObstacleField trunk;
  trunk.add_cylinder(0, 40, 0.5, -1, 30, olcore::ObstacleKind::Solid);
  trunk.finalize();
  olcore::FlatTerrain ground(olcore::Surface::Fairway);
  ground.obstacles = &trunk;
  olcore::ShotResult want = olcore::simulate_shot(drive, p, ground);
  olcore_gdext::SnapshotTerrain snap(flat_grid(olcore::Surface::Fairway, 0.0, 512, 512));
  olcore::ObstacleField trunk_baked;
  trunk_baked.add_cylinder(0, 40, 0.5, -1, 30, olcore::ObstacleKind::Solid);
  trunk_baked.finalize();
  snap.set_obstacles(std::move(trunk_baked));
  olcore_gdext::NativeShotResult got = olcore_gdext::run_shot(drive, {}, nullptr, snap, false, {});
  check(got.outcome == static_cast<int>(want.outcome), "trunk snapshot outcome matches olcore");
  check_near(got.carry_m, want.carry_m, 1e-9, "trunk snapshot carry matches olcore");
  check_near(got.total_m, want.total_m, 1e-9, "trunk snapshot total matches olcore");
  check_near(got.rest.z, want.rest.z, 1e-9, "trunk snapshot rest matches olcore");
  check(got.obstacle_hits == want.obstacle_hits, "trunk snapshot hit count matches olcore");
  // The number the GDScript port pins (run_tests.gd): the ball comes back
  // off the trunk and stops behind where it started.
  check_near(got.rest.z, -27.06, 1.0, "trunk rest z (GDScript pin)");
  std::printf("  trunk: rest z %.2f m, total %.2f m, %d hits\n", got.rest.z, got.total_m, got.obstacle_hits);

  // The field survives a move of the terrain: the obstacle pointer must
  // follow the owned field, not the moved-from terrain.
  olcore_gdext::SnapshotTerrain moved(std::move(snap));
  olcore_gdext::NativeShotResult again = olcore_gdext::run_shot(drive, {}, nullptr, moved, false, {});
  check(again.obstacle_hits >= 1, "moved snapshot still meets its obstacles");
  check_near(again.rest.z, got.rest.z, 1e-9, "moved snapshot rest matches");

  olcore::ObstacleField canopy;
  canopy.add_cylinder(0, 150, 6, 3, 40, olcore::ObstacleKind::Canopy);
  canopy.finalize();
  ground.obstacles = &canopy;
  want = olcore::simulate_shot(drive, p, ground);
  olcore_gdext::SnapshotTerrain snap2(flat_grid(olcore::Surface::Fairway, 0.0, 512, 512));
  olcore::ObstacleField canopy_baked;
  canopy_baked.add_cylinder(0, 150, 6, 3, 40, olcore::ObstacleKind::Canopy);
  canopy_baked.finalize();
  snap2.set_obstacles(std::move(canopy_baked));
  got = olcore_gdext::run_shot(drive, {}, nullptr, snap2, false, {});
  check_near(got.carry_m, want.carry_m, 1e-9, "canopy snapshot carry matches olcore");
  check(got.obstacle_hits >= 1, "canopy snapshot hits");
  check(got.carry_m < 165.0, "canopy snapshot carry (GDScript pin)");
  std::printf("  canopy: carry %.2f m, total %.2f m, %d hits\n", got.carry_m, got.total_m, got.obstacle_hits);

  // A putt rolled into a wall comes back, once.
  olcore::BallState putt = olcore::make_launch(3.0, 0, 0, 0, 0);
  putt.position = {0, 0, 0};
  olcore::ObstacleField wall;
  wall.add_box({0, 0.5, 4}, {{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}}, {2, 1, 0.1}, olcore::ObstacleKind::Solid);
  wall.finalize();
  olcore::FlatTerrain green(olcore::Surface::Green);
  green.obstacles = &wall;
  want = olcore::simulate_shot(putt, p, green);
  olcore_gdext::SnapshotTerrain snap3(flat_grid(olcore::Surface::Green, 0.0, 64, 64));
  olcore::ObstacleField wall_baked;
  wall_baked.add_box({0, 0.5, 4}, {{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}}, {2, 1, 0.1},
                     olcore::ObstacleKind::Solid);
  wall_baked.finalize();
  snap3.set_obstacles(std::move(wall_baked));
  got = olcore_gdext::run_shot(putt, {}, nullptr, snap3, false, {});
  check(got.obstacle_hits == want.obstacle_hits, "wall snapshot hit count matches olcore");
  check(got.obstacle_hits == 1, "wall snapshot hits once");
  check(got.rest.z < 3.9, "wall snapshot putt comes back");
  std::printf("  wall: rest z %.3f m, %d hits\n", got.rest.z, got.obstacle_hits);
}

// A rock billboard type: solid all over, restitution 0.8, opaque everywhere
// (mask rows bottom-first, as LinksSpriteMask stores them).
olcore::LinksObjects rock_billboard_objects() {
  olcore::LinksObjects objects;
  olcore::LinksObjectType type;
  type.collision = 1;
  type.shape = {0.8f, 1, 0, 0, 1, 1};
  type.aspect = 1;
  type.mask.width = type.mask.height = 20;
  type.mask.alpha.assign(400, 255);
  objects.types.push_back(type);
  olcore::LinksBillboard b;
  b.base = {0, 100, 0};  // 100 ft downrange, on the ground
  b.height = 30;         // 30 ft tall, 30 ft wide
  objects.add(b);
  return objects;
}

// A 3D wall: one quad 10 ft wide, 40 ft tall, 200 ft downrange, faced
// towards the ball (corners anticlockwise from the ball's side). Tall
// enough that a driver, still ~30 ft up at 200 ft, meets it.
olcore::LinksObjects wall_model_objects() {
  olcore::LinksObjects objects;
  olcore::LinksMesh mesh;
  const std::array<olcore::Vec3, 4> quad = {olcore::Vec3{-5, 200, 0}, olcore::Vec3{-5, 200, 40},
                                            olcore::Vec3{5, 200, 40}, olcore::Vec3{5, 200, 0}};
  olcore::LinksMesh::Face f;
  f.first = 0;
  f.count = 4;
  f.texture = 0;
  for (const olcore::Vec3& v : quad) {
    mesh.corners.push_back(static_cast<std::uint16_t>(mesh.positions.size()));
    mesh.positions.push_back({static_cast<float>(v.x), static_cast<float>(v.y), static_cast<float>(v.z)});
    mesh.uvs.push_back({0.5f, 0.5f});
  }
  mesh.faces.push_back(f);
  mesh.holes.resize(1);  // empty mask: a solid texture
  objects.meshes.push_back(mesh);
  olcore::LinksModel m;
  m.mesh = 0;
  for (const olcore::Vec3& v : quad) m.points.push_back(v);
  objects.add_model(std::move(m));
  return objects;
}

void check_links_shot_matches(const char* what, const olcore_gdext::NativeShotResult& got,
                              const olcore::ShotResult& want) {
  char buf[128];
  auto check_what = [&](bool ok, const char* field) {
    std::snprintf(buf, sizeof(buf), "%s %s matches olcore", what, field);
    check(ok, buf);
  };
  auto near_what = [&](double g, double w, double tol, const char* field) {
    std::snprintf(buf, sizeof(buf), "%s %s matches olcore", what, field);
    check_near(g, w, tol, buf);
  };
  check_what(got.outcome == static_cast<int>(want.outcome), "outcome");
  near_what(got.carry_m, want.carry_m, 1e-9, "carry");
  near_what(got.total_m, want.total_m, 1e-9, "total");
  near_what(got.rest.x, want.rest.x, 1e-9, "rest x");
  near_what(got.rest.y, want.rest.y, 1e-9, "rest y");
  near_what(got.rest.z, want.rest.z, 1e-9, "rest z");
  check_what(got.points.size() == want.path.size(), "path length");
}

// The Links model over a snapshot with billboards and 3D objects must
// meet them exactly as olcore does over its own terrain: same ball, same
// objects, same result.
void test_snapshot_links_objects_match_olcore() {
  olcore::LinksAero aero = windy_aero();
  olcore_gdext::AeroTables tables;
  tables.aero = aero;
  tables.valid = true;
  olcore::BallState drive = olcore::make_launch(60.0, 12.0, 0.0, 6000.0, 0.0);
  drive.position = {0, 0, 0};
  olcore::BallParams p;
  p.links = &aero;
  olcore::ShotOptions opt;
  opt.links_objects = nullptr;

  olcore::FlatTerrain ground(olcore::Surface::Fairway);
  olcore::ShotResult plain = olcore::simulate_links_shot(drive, p, ground, opt);
  // The box must cover the ball's way back as well as its way out: a ball
  // bounced off the billboard at 100 ft comes to rest well behind the tee.
  olcore_gdext::SnapshotTerrain snap(flat_grid(olcore::Surface::Fairway, 0.0, 512, 512, 1.0, -256.0));

  olcore::LinksObjects rocks = rock_billboard_objects();
  opt.links_objects = &rocks;
  olcore::ShotResult want = olcore::simulate_links_shot(drive, p, ground, opt);
  olcore_gdext::NativeShotResult got = olcore_gdext::run_shot(drive, {}, &tables, snap, false, {}, 0.054, 60.0,
                                                              &rocks);
  check_links_shot_matches("billboard", got, want);
  check(got.total_m < plain.total_m, "the billboard shortens the shot");
  std::printf("  billboard: total %.2f m (plain %.2f m)\n", got.total_m, plain.total_m);

  olcore::LinksObjects wall = wall_model_objects();
  opt.links_objects = &wall;
  want = olcore::simulate_links_shot(drive, p, ground, opt);
  got = olcore_gdext::run_shot(drive, {}, &tables, snap, false, {}, 0.054, 60.0, &wall);
  check_links_shot_matches("wall model", got, want);
  check(got.total_m < plain.total_m, "the wall shortens the shot");
  std::printf("  wall model: total %.2f m (plain %.2f m)\n", got.total_m, plain.total_m);
}

}  // namespace

int main() {
  test_flat_snapshot_is_exact();
  test_slope_snapshot_parity();
  test_driver_carry_is_plausible();
  test_links_model_runs_on_snapshot();
  test_aero_table_validation();
  test_out_of_bounds_outside_box();
  test_snapshot_obstacles_match_olcore();
  test_snapshot_links_objects_match_olcore();
  std::printf("olcore_snapshot_tests: %d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
