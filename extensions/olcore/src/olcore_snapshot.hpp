// olcore_snapshot.hpp — the Godot-free core of the Olcore GDExtension.
//
// A shot simulation in olcore calls Terrain virtuals thousands of times
// (height/surface/normal per step). Calling back into GDScript for each
// query is unsafe: shots run on WorkerThreadPool threads, and GDScript
// objects are not thread-safe. So the game bakes the ground the shot can
// reach into plain C++ data *before* the shot (OlcoreShotModel does this
// once per hole and caches it), and the simulation runs entirely in C++
// over that snapshot. No Godot headers here: this file is part of the
// extension, not of libs/olcore, so olcore stays engine-independent.
//
// What the snapshot carries besides the ground (Phase 2): the obstacles
// the shot can meet (a merged ObstacleField, baked from the course's
// ObstacleFields by OlcoreTerrain::bake_obstacles) and, for the Links
// model, the course's billboards and 3D objects (olcore::LinksObjects,
// passed to run_shot; built by OlcoreLinksObjects). LinksSurface records
// are carried only where the course overrides the class defaults (greens,
// in practice); elsewhere links_surface_at() returns null and olcore uses
// the class defaults, which is what every course checked so far uses.
#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

#include "olcore/ball_physics.hpp"
#include "olcore/links_flight.hpp"
#include "olcore/links_ground.hpp"
#include "olcore/links_objects.hpp"
#include "olcore/obstacles.hpp"
#include "olcore/shot.hpp"
#include "olcore/terrain.hpp"

namespace olcore_gdext {

// One cell of baked ground. Surface values use olcore::Surface's integer
// order, shared with GDScript Surface.Type.
struct SnapshotGrid {
  double origin_x = 0.0;  // SI metres, Godot frame (+x left, +z downrange)
  double origin_z = 0.0;
  double cell = 1.0;  // metres per cell
  int nx = 0;         // cells in x
  int nz = 0;         // cells in z
  // Row-major, nz rows of nx: index = iz * nx + ix.
  std::vector<double> heights;      // metres
  std::vector<std::uint8_t> surfaces;  // olcore::Surface as an integer
  // Per-cell LinksSurface overrides, only where the course differs from
  // the class defaults. has_links[i] says links[i] is meaningful.
  std::vector<olcore::LinksSurface> links;
  std::vector<std::uint8_t> has_links;

  bool valid() const;
  std::size_t index(int ix, int iz) const { return static_cast<std::size_t>(iz) * static_cast<std::size_t>(nx) + static_cast<std::size_t>(ix); }
  double min_x() const { return origin_x; }
  double max_x() const { return origin_x + (nx - 1) * cell; }
  double min_z() const { return origin_z; }
  double max_z() const { return origin_z + (nz - 1) * cell; }
};

// An olcore::Terrain backed by a SnapshotGrid. Height is bilinear (so a
// flat grid is exact); surface is the nearest cell. Outside the grid the
// ball is out of bounds, so a shot that leaves the baked box ends as
// OutOfBounds rather than reading garbage — OlcoreShotModel sizes the box
// around the shot and falls back to GDScript when the ball ends on its edge.
// Obstacles baked with set_obstacles() answer obstacle_hit(): the same
// field the GDScript port consults, merged from the course's fields (see
// OlcoreShotModel), so a native shot meets the same trees and walls.
class SnapshotTerrain : public olcore::Terrain {
 public:
  explicit SnapshotTerrain(SnapshotGrid grid) : grid_(std::move(grid)) {}
  const SnapshotGrid& grid() const { return grid_; }

  // Takes ownership of a finalized ObstacleField (the merged obstacles the
  // shot can meet). May be called once, before any shot runs over this
  // terrain; a later call replaces the field.
  void set_obstacles(olcore::ObstacleField field);
  bool has_obstacles() const { return obstacles_field_ != nullptr; }

  double height(double x, double z) const override;
  olcore::Surface surface(double x, double z) const override;
  bool in_bounds(double x, double z) const override;
  const olcore::LinksSurface* links_surface_at(double x, double z) const override;
  bool obstacle_hit(olcore::Vec3 from, olcore::Vec3 to, olcore::ObstacleHit& hit) const override;

 private:
  SnapshotGrid grid_;
  // Owned so the field outlives the bake; the base class `obstacles`
  // pointer is kept pointing at it for any code that reads Terrain
  // directly. obstacle_hit() consults this field, not the pointer, so a
  // move of the terrain cannot leave a stale pointer behind.
  std::unique_ptr<olcore::ObstacleField> obstacles_field_;
};

// Coefficient tables for the Links 2003 flight model, built from the
// arrays the game read from the player's executable (LinksAero in
// GDScript). Empty tables mean "no Links model": the stand-in flight runs.
struct AeroTables {
  olcore::LinksAero aero;
  bool valid = false;  // both tables present and well-formed

  // Builds the tables from flat arrays (speeds/spins in ft/s and rev/s,
  // values row-major by speed). Returns false and leaves valid=false when
  // the shapes do not match (11 speeds x 14 spins).
  static AeroTables from_arrays(const std::vector<double>& drag_speeds,
                                const std::vector<double>& drag_spins,
                                const std::vector<double>& drag_values,
                                const std::vector<double>& lift_speeds,
                                const std::vector<double>& lift_spins,
                                const std::vector<double>& lift_values);
};

// Plain result of a native shot, mirroring olcore::ShotResult without any
// Godot types so the C++ tests can check it directly.
struct NativeShotResult {
  int outcome = 0;  // olcore::ShotOutcome as an int (Rest=0, Holed=1, ...)
  olcore::Vec3 rest;
  olcore::Vec3 first_landing;
  int rest_surface = 1;  // olcore::Surface as an int (Fairway=1)
  double carry_m = 0;
  double total_m = 0;
  double apex_m = 0;
  double time_s = 0;
  int bounces = 0;
  int obstacle_hits = 0;
  std::vector<double> times;
  std::vector<olcore::Vec3> points;
};

// Runs olcore::simulate_shot over a snapshot terrain. When aero is null
// the stand-in model runs; when it is set the Links 2003 model runs
// (simulate_links_shot, via BallParams::links). `links_objects`, when
// given, is the course's billboards and 3D objects for the Links model
// (ShotOptions::links_objects); null means the shot meets none, as in the
// GDScript port when the terrain has none. Pure function of its
// arguments: no shared mutable state, so it is safe to call from worker
// threads with a separate SnapshotTerrain/AeroTables per shot.
NativeShotResult run_shot(const olcore::BallState& start, olcore::Vec3 wind, const AeroTables* aero,
                          const SnapshotTerrain& terrain, bool has_cup, olcore::Vec3 cup,
                          double cup_radius = 0.054, double max_time = 60.0,
                          const olcore::LinksObjects* links_objects = nullptr);

// The same, over olcore::FlatTerrain, for tests and for shots on flat
// ground (driving range, unit checks). No snapshot needed.
NativeShotResult run_shot_flat(const olcore::BallState& start, olcore::Vec3 wind, const AeroTables* aero,
                               olcore::Surface surface, double height, bool has_cup, olcore::Vec3 cup,
                               double cup_radius = 0.054, double max_time = 60.0,
                               const olcore::LinksObjects* links_objects = nullptr);

}  // namespace olcore_gdext
