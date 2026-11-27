// olcore_snapshot.cpp — see olcore_snapshot.hpp.
#include "olcore_snapshot.hpp"

#include <algorithm>
#include <cmath>

namespace olcore_gdext {
namespace {

olcore::CoefficientTable make_table(const std::vector<double>& speeds, const std::vector<double>& spins,
                                    const std::vector<double>& values) {
  olcore::CoefficientTable t;
  t.speeds = speeds;
  t.spins = spins;
  t.values = values;
  return t;
}

bool table_shape_ok(const std::vector<double>& speeds, const std::vector<double>& spins,
                    const std::vector<double>& values) {
  // The Links tables are 11 speeds x 14 spins (see LinksAero in GDScript
  // and CoefficientTable in links_flight.hpp).
  if (speeds.size() != 11 || spins.size() != 14) return false;
  if (values.size() != speeds.size() * spins.size()) return false;
  if (speeds.empty() || speeds[0] != 0.0 || spins[0] != 0.0) return false;
  for (std::size_t i = 1; i < speeds.size(); ++i) {
    if (!(speeds[i] > speeds[i - 1])) return false;
  }
  for (std::size_t i = 1; i < spins.size(); ++i) {
    if (!(spins[i] > spins[i - 1])) return false;
  }
  for (double v : values) {
    if (!std::isfinite(v) || std::fabs(v) > 5.0) return false;
  }
  return true;
}

NativeShotResult convert(const olcore::ShotResult& r) {
  NativeShotResult out;
  out.outcome = static_cast<int>(r.outcome);
  out.rest = r.rest;
  out.first_landing = r.first_landing;
  out.rest_surface = static_cast<int>(r.rest_surface);
  out.carry_m = r.carry_m;
  out.total_m = r.total_m;
  out.apex_m = r.apex_m;
  out.time_s = r.time_s;
  out.bounces = r.bounces;
  out.obstacle_hits = r.obstacle_hits;
  out.times.reserve(r.path.size());
  out.points.reserve(r.path.size());
  for (const olcore::ShotSample& s : r.path) {
    out.times.push_back(s.t);
    out.points.push_back(s.position);
  }
  return out;
}

}  // namespace

bool SnapshotGrid::valid() const {
  if (nx <= 0 || nz <= 0 || !(cell > 0.0)) return false;
  const std::size_t n = static_cast<std::size_t>(nx) * static_cast<std::size_t>(nz);
  if (heights.size() != n || surfaces.size() != n) return false;
  if (!links.empty() && links.size() != n) return false;
  if (!has_links.empty() && has_links.size() != n) return false;
  for (std::uint8_t s : surfaces) {
    if (s > static_cast<std::uint8_t>(olcore::Surface::OutOfBounds)) return false;
  }
  return true;
}

void SnapshotTerrain::set_obstacles(olcore::ObstacleField field) {
  obstacles_field_ = std::make_unique<olcore::ObstacleField>(std::move(field));
  obstacles = obstacles_field_.get();
}

bool SnapshotTerrain::obstacle_hit(olcore::Vec3 from, olcore::Vec3 to, olcore::ObstacleHit& hit) const {
  return obstacles_field_ != nullptr && obstacles_field_->segment_hit(from, to, hit);
}

double SnapshotTerrain::height(double x, double z) const {
  const SnapshotGrid& g = grid_;
  if (g.nx <= 0 || g.nz <= 0) return 0.0;
  // Bilinear over the grid, clamped to the edge so a query just outside
  // the box still returns a sane height (in_bounds() is what ends the
  // shot there, not a height cliff).
  double fx = (x - g.origin_x) / g.cell;
  double fz = (z - g.origin_z) / g.cell;
  fx = std::clamp(fx, 0.0, static_cast<double>(g.nx - 1));
  fz = std::clamp(fz, 0.0, static_cast<double>(g.nz - 1));
  const int ix = static_cast<int>(std::min(fx, static_cast<double>(g.nx - 2 < 0 ? 0 : g.nx - 2)));
  const int iz = static_cast<int>(std::min(fz, static_cast<double>(g.nz - 2 < 0 ? 0 : g.nz - 2)));
  const double tx = std::clamp(fx - ix, 0.0, 1.0);
  const double tz = std::clamp(fz - iz, 0.0, 1.0);
  const double h00 = g.heights[g.index(ix, iz)];
  const double h10 = g.heights[g.index(ix + 1 <= g.nx - 1 ? ix + 1 : ix, iz)];
  const double h01 = g.heights[g.index(ix, iz + 1 <= g.nz - 1 ? iz + 1 : iz)];
  const double h11 = g.heights[g.index(ix + 1 <= g.nx - 1 ? ix + 1 : ix, iz + 1 <= g.nz - 1 ? iz + 1 : iz)];
  const double h0 = h00 + (h10 - h00) * tx;
  const double h1 = h01 + (h11 - h01) * tx;
  return h0 + (h1 - h0) * tz;
}

olcore::Surface SnapshotTerrain::surface(double x, double z) const {
  const SnapshotGrid& g = grid_;
  if (g.nx <= 0 || g.nz <= 0) return olcore::Surface::Fairway;
  int ix = static_cast<int>(std::llround((x - g.origin_x) / g.cell));
  int iz = static_cast<int>(std::llround((z - g.origin_z) / g.cell));
  ix = std::clamp(ix, 0, g.nx - 1);
  iz = std::clamp(iz, 0, g.nz - 1);
  return static_cast<olcore::Surface>(g.surfaces[g.index(ix, iz)]);
}

bool SnapshotTerrain::in_bounds(double x, double z) const {
  const SnapshotGrid& g = grid_;
  return x >= g.min_x() && x <= g.max_x() && z >= g.min_z() && z <= g.max_z();
}

const olcore::LinksSurface* SnapshotTerrain::links_surface_at(double x, double z) const {
  const SnapshotGrid& g = grid_;
  if (g.links.empty() || g.has_links.empty()) return nullptr;
  int ix = static_cast<int>(std::llround((x - g.origin_x) / g.cell));
  int iz = static_cast<int>(std::llround((z - g.origin_z) / g.cell));
  if (ix < 0 || ix >= g.nx || iz < 0 || iz >= g.nz) return nullptr;
  const std::size_t i = g.index(ix, iz);
  return g.has_links[i] ? &g.links[i] : nullptr;
}

AeroTables AeroTables::from_arrays(const std::vector<double>& drag_speeds,
                                   const std::vector<double>& drag_spins,
                                   const std::vector<double>& drag_values,
                                   const std::vector<double>& lift_speeds,
                                   const std::vector<double>& lift_spins,
                                   const std::vector<double>& lift_values) {
  AeroTables out;
  if (!table_shape_ok(drag_speeds, drag_spins, drag_values)) return out;
  if (!table_shape_ok(lift_speeds, lift_spins, lift_values)) return out;
  out.aero.drag = make_table(drag_speeds, drag_spins, drag_values);
  out.aero.lift = make_table(lift_speeds, lift_spins, lift_values);
  out.valid = true;
  return out;
}

NativeShotResult run_shot(const olcore::BallState& start, olcore::Vec3 wind, const AeroTables* aero,
                          const SnapshotTerrain& terrain, bool has_cup, olcore::Vec3 cup, double cup_radius,
                          double max_time, const olcore::LinksObjects* links_objects) {
  olcore::BallParams p;
  p.wind = wind;
  if (aero != nullptr && aero->valid) p.links = &aero->aero;
  olcore::ShotOptions opt;
  opt.has_cup = has_cup;
  opt.cup = cup;
  opt.cup_radius = cup_radius;
  opt.max_time = max_time;
  opt.links_objects = links_objects;
  return convert(olcore::simulate_shot(start, p, terrain, opt));
}

NativeShotResult run_shot_flat(const olcore::BallState& start, olcore::Vec3 wind, const AeroTables* aero,
                               olcore::Surface surface, double height, bool has_cup, olcore::Vec3 cup,
                               double cup_radius, double max_time, const olcore::LinksObjects* links_objects) {
  olcore::BallParams p;
  p.wind = wind;
  if (aero != nullptr && aero->valid) p.links = &aero->aero;
  olcore::ShotOptions opt;
  opt.has_cup = has_cup;
  opt.cup = cup;
  opt.cup_radius = cup_radius;
  opt.max_time = max_time;
  opt.links_objects = links_objects;
  olcore::FlatTerrain terrain(surface, height);
  return convert(olcore::simulate_shot(start, p, terrain, opt));
}

}  // namespace olcore_gdext
