// olcore_physics.cpp — see olcore_physics.hpp.
#include "olcore_physics.hpp"

#include <cmath>

#include <godot_cpp/variant/utility_functions.hpp>

#include "olcore/links_ground.hpp"
#include "olcore/links_launch.hpp"
#include "olcore/links_mouse.hpp"

namespace olcore_gdext {
namespace {

olcore::Vec3 to_vec3(const godot::Vector3& v) {
  return olcore::Vec3{static_cast<double>(v.x), static_cast<double>(v.y), static_cast<double>(v.z)};
}

godot::Vector3 from_vec3(const olcore::Vec3& v) {
  return godot::Vector3(static_cast<float>(v.x), static_cast<float>(v.y), static_cast<float>(v.z));
}

std::vector<double> to_doubles(const godot::PackedFloat64Array& a) {
  std::vector<double> out;
  out.reserve(a.size());
  for (int i = 0; i < a.size(); ++i) out.push_back(a[i]);
  return out;
}

bool table_from_dict(const godot::Dictionary& d, std::vector<double>& speeds, std::vector<double>& spins,
                     std::vector<double>& values) {
  if (!d.has("speeds") || !d.has("spins") || !d.has("values")) return false;
  godot::PackedFloat64Array s = d["speeds"];
  godot::PackedFloat64Array w = d["spins"];
  godot::PackedFloat64Array v = d["values"];
  speeds = to_doubles(s);
  spins = to_doubles(w);
  values = to_doubles(v);
  return true;
}

// Dictionary readers for the Links launch/swing calls. A missing key
// keeps the C++ struct's default, as the GDScript classes do.
double dict_double(const godot::Dictionary& d, const char* key, double def) {
  if (!d.has(key)) return def;
  godot::Variant v = d[key];
  return v.get_type() == godot::Variant::NIL ? def : static_cast<double>(v);
}

std::int64_t dict_int(const godot::Dictionary& d, const char* key, std::int64_t def) {
  if (!d.has(key)) return def;
  godot::Variant v = d[key];
  return v.get_type() == godot::Variant::NIL ? def : static_cast<std::int64_t>(v);
}

bool dict_bool(const godot::Dictionary& d, const char* key, bool def) {
  if (!d.has(key)) return def;
  godot::Variant v = d[key];
  return v.get_type() == godot::Variant::NIL ? def : static_cast<bool>(v);
}

godot::Vector3 dict_vec3(const godot::Dictionary& d, const char* key, const godot::Vector3& def) {
  if (!d.has(key)) return def;
  godot::Variant v = d[key];
  if (v.get_type() != godot::Variant::VECTOR3) return def;
  return static_cast<godot::Vector3>(v);
}

olcore::LinksStrike strike_from_dict(const godot::Dictionary& d) {
  olcore::LinksStrike s;
  s.club = static_cast<int>(dict_int(d, "club", 0));
  s.aim = dict_double(d, "aim", 0.0);
  s.power = dict_double(d, "power", 100.0);
  s.face_error = dict_double(d, "face_error", 0.0);
  s.path_error = dict_double(d, "path_error", 0.0);
  s.speed_scale = dict_double(d, "speed_scale", 1.0);
  s.spin_scale = dict_double(d, "spin_scale", 1.0);
  s.loft_scale = dict_double(d, "loft_scale", 1.0);
  s.setup.ball_position = static_cast<int>(dict_int(d, "setup_ball_position", -1));
  s.setup.face = static_cast<int>(dict_int(d, "setup_face", 30));
  s.setup.stance = static_cast<int>(dict_int(d, "setup_stance", 30));
  s.ground_normal = to_vec3(dict_vec3(d, "ground_normal", godot::Vector3(0, 0, 1)));
  return s;
}

godot::Dictionary strike_to_dict(const olcore::LinksStrike& s) {
  godot::Dictionary d;
  d["club"] = s.club;
  d["aim"] = s.aim;
  d["power"] = s.power;
  d["face_error"] = s.face_error;
  d["path_error"] = s.path_error;
  d["speed_scale"] = s.speed_scale;
  d["spin_scale"] = s.spin_scale;
  d["loft_scale"] = s.loft_scale;
  d["setup_ball_position"] = s.setup.ball_position;
  d["setup_face"] = s.setup.face;
  d["setup_stance"] = s.setup.stance;
  d["ground_normal"] = from_vec3(s.ground_normal);
  return d;
}

olcore::LinksSurface lie_from_dict(const godot::Dictionary& d) {
  olcore::LinksSurface lie;
  lie.ground_class = static_cast<int>(dict_int(d, "ground_class", lie.ground_class));
  lie.restitution = dict_double(d, "restitution", lie.restitution);
  lie.impact_friction = dict_double(d, "impact_friction", lie.impact_friction);
  lie.skid_friction = dict_double(d, "skid_friction", lie.skid_friction);
  lie.impact_drag = dict_double(d, "impact_drag", lie.impact_drag);
  lie.roll_resistance = dict_double(d, "roll_resistance", lie.roll_resistance);
  lie.stop_speed = dict_double(d, "stop_speed", lie.stop_speed);
  lie.spin_grip = dict_double(d, "spin_grip", lie.spin_grip);
  lie.lie_spin = dict_double(d, "lie_spin", lie.lie_spin);
  lie.lie_power = dict_double(d, "lie_power", lie.lie_power);
  return lie;
}

olcore::LinksSwing swing_from_dict(const godot::Dictionary& d) {
  olcore::LinksSwing w;
  w.method = dict_int(d, "method", 0) == 1 ? olcore::LinksSwingMethod::Mouse
                                          : olcore::LinksSwingMethod::PowerStroke;
  w.skill = static_cast<int>(dict_int(d, "skill", 3));
  w.contact = static_cast<int>(dict_int(d, "contact", 0));
  w.full_power = dict_double(d, "full_power", 100.0);
  w.mouse_face_deg = dict_double(d, "mouse_face_deg", 0.0);
  w.mouse_path_deg = dict_double(d, "mouse_path_deg", 0.0);
  w.mouse_loft = dict_double(d, "mouse_loft", 1.0);
  w.left_handed = dict_bool(d, "left_handed", false);
  w.chip = dict_bool(d, "chip", false);
  w.teed_up = dict_bool(d, "teed_up", false);
  return w;
}

olcore::LinksGolferRatings ratings_from_dict(const godot::Dictionary& d) {
  olcore::LinksGolferRatings g;
  g.tee = static_cast<int>(dict_int(d, "tee", g.tee));
  g.woods = static_cast<int>(dict_int(d, "woods", g.woods));
  g.long_irons = static_cast<int>(dict_int(d, "long_irons", g.long_irons));
  g.mid_irons = static_cast<int>(dict_int(d, "mid_irons", g.mid_irons));
  g.short_irons = static_cast<int>(dict_int(d, "short_irons", g.short_irons));
  g.wedges = static_cast<int>(dict_int(d, "wedges", g.wedges));
  g.chips = static_cast<int>(dict_int(d, "chips", g.chips));
  g.max_power = static_cast<int>(dict_int(d, "max_power", g.max_power));
  g.steady = dict_bool(d, "steady", g.steady);
  g.long_putts = static_cast<int>(dict_int(d, "long_putts", g.long_putts));
  g.short_putts = static_cast<int>(dict_int(d, "short_putts", g.short_putts));
  return g;
}

olcore::LinksComputerSwing computer_swing_from_dict(const godot::Dictionary& d) {
  olcore::LinksComputerSwing w;
  w.power = dict_double(d, "power", 100.0);
  w.face_deg = dict_double(d, "face_deg", 0.0);
  w.path_deg = dict_double(d, "path_deg", 0.0);
  return w;
}

godot::Dictionary computer_swing_to_dict(const olcore::LinksComputerSwing& w) {
  godot::Dictionary d;
  d["power"] = w.power;
  d["face_deg"] = w.face_deg;
  d["path_deg"] = w.path_deg;
  return d;
}

godot::Dictionary launch_to_dict(const olcore::LinksLaunch& l) {
  godot::Dictionary d;
  d["velocity"] = from_vec3(l.velocity);
  d["spin"] = from_vec3(l.spin);
  return d;
}

}  // namespace

// ---------------------------------------------------------------- OlcoreTerrain

void OlcoreTerrain::_bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD("bake", "origin_x", "origin_z", "cell", "nx", "nz", "heights",
                                             "surfaces", "green_surfaces", "has_green"),
                              &OlcoreTerrain::bake);
  godot::ClassDB::bind_method(godot::D_METHOD("bake_flat", "surface", "height"), &OlcoreTerrain::bake_flat);
  godot::ClassDB::bind_method(godot::D_METHOD("bake_obstacles", "cylinders", "boxes"),
                              &OlcoreTerrain::bake_obstacles);
  godot::ClassDB::bind_method(godot::D_METHOD("is_baked"), &OlcoreTerrain::is_baked);
  godot::ClassDB::bind_method(godot::D_METHOD("has_obstacles"), &OlcoreTerrain::has_obstacles);
  godot::ClassDB::bind_method(godot::D_METHOD("height_at", "x", "z"), &OlcoreTerrain::height_at);
  godot::ClassDB::bind_method(godot::D_METHOD("surface_at", "x", "z"), &OlcoreTerrain::surface_at);
  godot::ClassDB::bind_method(godot::D_METHOD("cell_count"), &OlcoreTerrain::cell_count);
  godot::ClassDB::bind_method(godot::D_METHOD("get_origin"), &OlcoreTerrain::get_origin);
  godot::ClassDB::bind_method(godot::D_METHOD("get_cell_size"), &OlcoreTerrain::get_cell_size);
  godot::ClassDB::bind_method(godot::D_METHOD("get_size"), &OlcoreTerrain::get_size);
}

bool OlcoreTerrain::bake(double origin_x, double origin_z, double cell, int nx, int nz,
                         const godot::PackedFloat32Array& heights, const godot::PackedByteArray& surfaces,
                         const godot::PackedFloat32Array& green_surfaces,
                         const godot::PackedByteArray& has_green) {
  SnapshotGrid grid;
  grid.origin_x = origin_x;
  grid.origin_z = origin_z;
  grid.cell = cell;
  grid.nx = nx;
  grid.nz = nz;
  const std::size_t n = static_cast<std::size_t>(nx) * static_cast<std::size_t>(nz);
  if (nx <= 0 || nz <= 0 || heights.size() != static_cast<int>(n) || surfaces.size() != static_cast<int>(n)) {
    godot::UtilityFunctions::push_error("OlcoreTerrain.bake: heights/surfaces do not match nx*nz");
    return false;
  }
  grid.heights.reserve(n);
  grid.surfaces.reserve(n);
  for (int i = 0; i < heights.size(); ++i) grid.heights.push_back(heights[i]);
  for (int i = 0; i < surfaces.size(); ++i) grid.surfaces.push_back(surfaces[i]);
  if (!green_surfaces.is_empty() || !has_green.is_empty()) {
    // Ten LinksSurface values per cell, in struct order: ground_class,
    // restitution, impact_friction, skid_friction, impact_drag,
    // roll_resistance, stop_speed, spin_grip, lie_spin, lie_power.
    if (green_surfaces.size() != static_cast<int>(n * 10) || has_green.size() != static_cast<int>(n)) {
      godot::UtilityFunctions::push_error("OlcoreTerrain.bake: green surface arrays do not match nx*nz");
      return false;
    }
    grid.links.resize(n);
    grid.has_links.reserve(n);
    for (std::size_t i = 0; i < n; ++i) {
      olcore::LinksSurface s;
      const float* f = &green_surfaces[static_cast<int>(i * 10)];
      s.ground_class = static_cast<int>(f[0]);
      s.restitution = f[1];
      s.impact_friction = f[2];
      s.skid_friction = f[3];
      s.impact_drag = f[4];
      s.roll_resistance = f[5];
      s.stop_speed = f[6];
      s.spin_grip = f[7];
      s.lie_spin = f[8];
      s.lie_power = f[9];
      grid.links[i] = s;
      grid.has_links.push_back(has_green[static_cast<int>(i)]);
    }
  }
  if (!grid.valid()) {
    godot::UtilityFunctions::push_error("OlcoreTerrain.bake: grid failed validation");
    return false;
  }
  snapshot_ = SnapshotTerrain(std::move(grid));
  return true;
}

void OlcoreTerrain::bake_flat(int surface, double height) {
  SnapshotGrid grid;
  grid.origin_x = 0.0;
  grid.origin_z = 0.0;
  grid.cell = 1.0;
  grid.nx = 1;
  grid.nz = 1;
  grid.heights = {height};
  grid.surfaces = {static_cast<std::uint8_t>(surface)};
  snapshot_ = SnapshotTerrain(std::move(grid));
}

bool OlcoreTerrain::bake_obstacles(const godot::PackedFloat32Array& cylinders,
                                   const godot::PackedFloat32Array& boxes) {
  if (cylinders.size() % 6 != 0 || boxes.size() % 16 != 0) {
    godot::UtilityFunctions::push_error("OlcoreTerrain.bake_obstacles: arrays are not whole items");
    return false;
  }
  olcore::ObstacleField field;
  for (int i = 0; i < cylinders.size(); i += 6) {
    int kind = static_cast<int>(cylinders[i + 5]);
    if (kind != 0 && kind != 1) {
      godot::UtilityFunctions::push_error("OlcoreTerrain.bake_obstacles: cylinder kind out of range");
      return false;
    }
    field.add_cylinder(cylinders[i], cylinders[i + 1], cylinders[i + 2], cylinders[i + 3], cylinders[i + 4],
                       static_cast<olcore::ObstacleKind>(kind));
  }
  for (int i = 0; i < boxes.size(); i += 16) {
    int kind = static_cast<int>(boxes[i + 15]);
    if (kind != 0 && kind != 1) {
      godot::UtilityFunctions::push_error("OlcoreTerrain.bake_obstacles: box kind out of range");
      return false;
    }
    olcore::Vec3 centre{boxes[i], boxes[i + 1], boxes[i + 2]};
    std::array<olcore::Vec3, 3> axes;
    for (int k = 0; k < 3; ++k) {
      axes[static_cast<std::size_t>(k)] = olcore::Vec3{boxes[i + 3 + 3 * k], boxes[i + 4 + 3 * k],
                                                       boxes[i + 5 + 3 * k]};
    }
    olcore::Vec3 half{boxes[i + 12], boxes[i + 13], boxes[i + 14]};
    field.add_box(centre, axes, half, static_cast<olcore::ObstacleKind>(kind));
  }
  field.finalize();
  snapshot_.set_obstacles(std::move(field));
  return true;
}

bool OlcoreTerrain::is_baked() const { return snapshot_.grid().valid(); }
bool OlcoreTerrain::has_obstacles() const { return snapshot_.has_obstacles(); }
double OlcoreTerrain::height_at(double x, double z) const { return snapshot_.height(x, z); }
int OlcoreTerrain::surface_at(double x, double z) const {
  return static_cast<int>(snapshot_.surface(x, z));
}
int OlcoreTerrain::cell_count() const {
  const SnapshotGrid& g = snapshot_.grid();
  return g.nx * g.nz;
}
godot::Vector2 OlcoreTerrain::get_origin() const {
  const SnapshotGrid& g = snapshot_.grid();
  return godot::Vector2(static_cast<float>(g.origin_x), static_cast<float>(g.origin_z));
}
double OlcoreTerrain::get_cell_size() const { return snapshot_.grid().cell; }
godot::Vector2i OlcoreTerrain::get_size() const {
  const SnapshotGrid& g = snapshot_.grid();
  return godot::Vector2i(g.nx, g.nz);
}

// ---------------------------------------------------------------- OlcoreAero

void OlcoreAero::_bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD("set_tables", "drag", "lift"), &OlcoreAero::set_tables);
  godot::ClassDB::bind_method(godot::D_METHOD("is_valid"), &OlcoreAero::is_valid);
}

bool OlcoreAero::set_tables(const godot::Dictionary& drag, const godot::Dictionary& lift) {
  std::vector<double> ds, dw, dv, ls, lw, lv;
  if (!table_from_dict(drag, ds, dw, dv) || !table_from_dict(lift, ls, lw, lv)) {
    godot::UtilityFunctions::push_error("OlcoreAero.set_tables: tables need speeds, spins and values");
    return false;
  }
  tables_ = AeroTables::from_arrays(ds, dw, dv, ls, lw, lv);
  if (!tables_.valid) {
    godot::UtilityFunctions::push_error("OlcoreAero.set_tables: tables are not well-formed (11x14)");
    return false;
  }
  return true;
}

bool OlcoreAero::is_valid() const { return tables_.valid; }

// ---------------------------------------------------------------- OlcoreClubs

void OlcoreClubs::_bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD("set_table", "spin", "speed", "loft_deg", "glance",
                                             "ball_position"),
                              &OlcoreClubs::set_table);
  godot::ClassDB::bind_method(godot::D_METHOD("is_valid"), &OlcoreClubs::is_valid);
}

bool OlcoreClubs::set_table(const godot::PackedFloat64Array& spin, const godot::PackedFloat64Array& speed,
                            const godot::PackedFloat64Array& loft_deg,
                            const godot::PackedFloat64Array& glance,
                            const godot::PackedFloat64Array& ball_position) {
  if (spin.size() != olcore::kLinksClubCount || speed.size() != olcore::kLinksClubCount ||
      loft_deg.size() != olcore::kLinksClubCount || glance.size() != olcore::kLinksClubCount ||
      ball_position.size() != olcore::kLinksClubCount) {
    godot::UtilityFunctions::push_error("OlcoreClubs.set_table: each row needs 19 clubs");
    return false;
  }
  const godot::PackedFloat64Array* rows[5] = {&spin, &speed, &loft_deg, &glance, &ball_position};
  std::array<double, olcore::kLinksClubCount>* dst[5] = {&table_.spin, &table_.speed, &table_.loft_deg,
                                                         &table_.glance, &table_.ball_position};
  for (int r = 0; r < 5; ++r) {
    for (int i = 0; i < olcore::kLinksClubCount; ++i) {
      double v = (*rows[r])[i];
      if (!std::isfinite(v)) {
        godot::UtilityFunctions::push_error("OlcoreClubs.set_table: table holds a non-finite value");
        return false;
      }
      (*dst[r])[static_cast<std::size_t>(i)] = v;
    }
  }
  valid_ = true;
  return true;
}

bool OlcoreClubs::is_valid() const { return valid_; }

// ---------------------------------------------------------------- OlcoreLinksObjects

void OlcoreLinksObjects::_bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD("set_types", "collisions", "shapes", "aspects", "mask_widths",
                                             "mask_heights", "mask_alphas", "mask_offsets"),
                              &OlcoreLinksObjects::set_types);
  godot::ClassDB::bind_method(godot::D_METHOD("add_billboard", "base", "height", "anchor_x", "anchor_z",
                                             "type"),
                              &OlcoreLinksObjects::add_billboard);
  godot::ClassDB::bind_method(godot::D_METHOD("add_mesh", "positions", "uvs", "corners", "faces",
                                             "hole_widths", "hole_heights", "hole_alphas", "hole_offsets"),
                              &OlcoreLinksObjects::add_mesh);
  godot::ClassDB::bind_method(godot::D_METHOD("add_model", "mesh", "points"), &OlcoreLinksObjects::add_model);
  godot::ClassDB::bind_method(godot::D_METHOD("billboard_count"), &OlcoreLinksObjects::billboard_count);
  godot::ClassDB::bind_method(godot::D_METHOD("model_count"), &OlcoreLinksObjects::model_count);
  godot::ClassDB::bind_method(godot::D_METHOD("is_empty"), &OlcoreLinksObjects::is_empty);
}

bool OlcoreLinksObjects::set_types(const godot::PackedInt32Array& collisions,
                                   const godot::PackedFloat32Array& shapes,
                                   const godot::PackedFloat32Array& aspects,
                                   const godot::PackedInt32Array& mask_widths,
                                   const godot::PackedInt32Array& mask_heights,
                                   const godot::PackedByteArray& mask_alphas,
                                   const godot::PackedInt32Array& mask_offsets) {
  const int n = collisions.size();
  if (shapes.size() != n * 6 || aspects.size() != n || mask_widths.size() != n ||
      mask_heights.size() != n || mask_offsets.size() != n) {
    godot::UtilityFunctions::push_error("OlcoreLinksObjects.set_types: type arrays do not match");
    return false;
  }
  for (int i = 0; i < n; ++i) {
    int w = mask_widths[i];
    int h = mask_heights[i];
    int off = mask_offsets[i];
    if (w < 0 || h < 0 || off < 0 ||
        (w > 0 && h > 0 && off + w * h > mask_alphas.size())) {
      godot::UtilityFunctions::push_error("OlcoreLinksObjects.set_types: mask does not fit its bytes");
      return false;
    }
  }
  objects_.types.clear();
  objects_.types.reserve(static_cast<std::size_t>(n));
  for (int i = 0; i < n; ++i) {
    olcore::LinksObjectType t;
    t.collision = static_cast<std::uint32_t>(collisions[i]);
    for (int k = 0; k < 6; ++k) t.shape[static_cast<std::size_t>(k)] = shapes[i * 6 + k];
    t.aspect = aspects[i];
    int w = mask_widths[i];
    int h = mask_heights[i];
    if (w > 0 && h > 0) {
      t.mask.width = w;
      t.mask.height = h;
      int off = mask_offsets[i];
      t.mask.alpha.reserve(static_cast<std::size_t>(w) * static_cast<std::size_t>(h));
      for (int k = 0; k < w * h; ++k) t.mask.alpha.push_back(mask_alphas[off + k]);
    }
    objects_.types.push_back(std::move(t));
  }
  return true;
}

void OlcoreLinksObjects::add_billboard(const godot::Vector3& base, double height, double anchor_x,
                                       double anchor_z, int type) {
  olcore::LinksBillboard b;
  b.base = to_vec3(base);
  b.height = height;
  b.anchor_x = anchor_x;
  b.anchor_z = anchor_z;
  b.type = type;
  objects_.add(b);
}

int OlcoreLinksObjects::add_mesh(const godot::PackedVector3Array& positions,
                                 const godot::PackedVector2Array& uvs,
                                 const godot::PackedInt32Array& corners,
                                 const godot::PackedInt32Array& faces,
                                 const godot::PackedInt32Array& hole_widths,
                                 const godot::PackedInt32Array& hole_heights,
                                 const godot::PackedByteArray& hole_alphas,
                                 const godot::PackedInt32Array& hole_offsets) {
  if (faces.size() % 3 != 0 || hole_widths.size() != hole_heights.size() ||
      hole_widths.size() != hole_offsets.size()) {
    godot::UtilityFunctions::push_error("OlcoreLinksObjects.add_mesh: mesh arrays do not match");
    return -1;
  }
  for (int i = 0; i < hole_widths.size(); ++i) {
    int w = hole_widths[i];
    int h = hole_heights[i];
    int off = hole_offsets[i];
    if (w < 0 || h < 0 || off < 0 || (w > 0 && h > 0 && off + w * h > hole_alphas.size())) {
      godot::UtilityFunctions::push_error("OlcoreLinksObjects.add_mesh: hole mask does not fit its bytes");
      return -1;
    }
  }
  for (int i = 0; i < corners.size(); ++i) {
    if (corners[i] < 0 || corners[i] >= positions.size()) {
      godot::UtilityFunctions::push_error("OlcoreLinksObjects.add_mesh: corner out of range");
      return -1;
    }
  }
  olcore::LinksMesh mesh;
  mesh.positions.reserve(static_cast<std::size_t>(positions.size()));
  for (int i = 0; i < positions.size(); ++i) {
    mesh.positions.push_back({positions[i].x, positions[i].y, positions[i].z});
  }
  mesh.uvs.reserve(static_cast<std::size_t>(uvs.size()));
  for (int i = 0; i < uvs.size(); ++i) mesh.uvs.push_back({uvs[i].x, uvs[i].y});
  mesh.corners.reserve(static_cast<std::size_t>(corners.size()));
  for (int i = 0; i < corners.size(); ++i) mesh.corners.push_back(static_cast<std::uint16_t>(corners[i]));
  mesh.faces.reserve(static_cast<std::size_t>(faces.size() / 3));
  for (int i = 0; i < faces.size(); i += 3) {
    olcore::LinksMesh::Face f;
    f.first = static_cast<std::uint16_t>(faces[i]);
    f.count = static_cast<std::uint16_t>(faces[i + 1]);
    f.texture = static_cast<std::uint16_t>(faces[i + 2]);
    mesh.faces.push_back(f);
  }
  mesh.holes.resize(static_cast<std::size_t>(hole_widths.size()));
  for (int i = 0; i < hole_widths.size(); ++i) {
    int w = hole_widths[i];
    int h = hole_heights[i];
    if (w > 0 && h > 0) {
      olcore::LinksSpriteMask& m = mesh.holes[static_cast<std::size_t>(i)];
      m.width = w;
      m.height = h;
      int off = hole_offsets[i];
      m.alpha.reserve(static_cast<std::size_t>(w) * static_cast<std::size_t>(h));
      for (int k = 0; k < w * h; ++k) m.alpha.push_back(hole_alphas[off + k]);
    }
  }
  objects_.meshes.push_back(std::move(mesh));
  return static_cast<int>(objects_.meshes.size()) - 1;
}

bool OlcoreLinksObjects::add_model(int mesh, const godot::PackedVector3Array& points) {
  if (mesh < 0 || mesh >= static_cast<int>(objects_.meshes.size()) || points.is_empty()) {
    godot::UtilityFunctions::push_error("OlcoreLinksObjects.add_model: mesh out of range or no points");
    return false;
  }
  olcore::LinksModel m;
  m.mesh = mesh;
  m.points.reserve(static_cast<std::size_t>(points.size()));
  for (int i = 0; i < points.size(); ++i) m.points.push_back(to_vec3(points[i]));
  objects_.add_model(std::move(m));
  return true;
}

int OlcoreLinksObjects::billboard_count() const { return static_cast<int>(objects_.billboards().size()); }
int OlcoreLinksObjects::model_count() const { return static_cast<int>(objects_.models().size()); }
bool OlcoreLinksObjects::is_empty() const { return billboard_count() == 0 && model_count() == 0; }

// ---------------------------------------------------------------- OlcorePhysics

void OlcorePhysics::_bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD("simulate_shot", "start_position", "start_velocity", "start_spin",
                                             "on_ground", "wind", "aero", "terrain", "has_cup", "cup",
                                             "cup_radius", "max_time", "links_objects"),
                              &OlcorePhysics::simulate_shot, DEFVAL(0.054), DEFVAL(60.0),
                              DEFVAL(godot::Ref<OlcoreLinksObjects>()));
  godot::ClassDB::bind_method(godot::D_METHOD("make_launch", "speed_mps", "launch_deg", "azimuth_deg",
                                             "backspin_rpm", "sidespin_rpm"),
                              &OlcorePhysics::make_launch);
  godot::ClassDB::bind_method(godot::D_METHOD("get_version"), &OlcorePhysics::get_version);
  godot::ClassDB::bind_method(godot::D_METHOD("links_launch", "clubs", "strike"),
                              &OlcorePhysics::links_launch);
  godot::ClassDB::bind_method(godot::D_METHOD("links_putt", "strike"), &OlcorePhysics::links_putt);
  godot::ClassDB::bind_method(godot::D_METHOD("links_putt_slope", "v", "n"),
                              &OlcorePhysics::links_putt_slope);
  godot::ClassDB::bind_method(godot::D_METHOD("links_apply_lie", "strike", "lie", "sand_contact"),
                              &OlcorePhysics::links_apply_lie, DEFVAL(0));
  godot::ClassDB::bind_method(godot::D_METHOD("links_apply_swing", "strike", "swing", "lie", "rng_state"),
                              &OlcorePhysics::links_apply_swing);
  godot::ClassDB::bind_method(godot::D_METHOD("links_meter_contact", "miss", "skill", "meter_width"),
                              &OlcorePhysics::links_meter_contact, DEFVAL(192));
  godot::ClassDB::bind_method(godot::D_METHOD("links_clean_strike_speed", "club", "lie", "skill"),
                              &OlcorePhysics::links_clean_strike_speed);
  godot::ClassDB::bind_method(godot::D_METHOD("links_computer_miss", "swing", "ratings", "club", "teed_up",
                                             "chip", "ground_class", "feet_to_hole", "rng_state"),
                              &OlcorePhysics::links_computer_miss);
  godot::ClassDB::bind_method(godot::D_METHOD("links_computer_putt_miss", "swing", "ratings",
                                             "ground_class", "feet_to_hole", "rng_state"),
                              &OlcorePhysics::links_computer_putt_miss);
  godot::ClassDB::bind_method(godot::D_METHOD("links_mouse_swing", "stroke", "rng_state", "help"),
                              &OlcorePhysics::links_mouse_swing, DEFVAL(godot::Dictionary()));
}

godot::Dictionary OlcorePhysics::simulate_shot(const godot::Vector3& start_position,
                                               const godot::Vector3& start_velocity,
                                               const godot::Vector3& start_spin, bool on_ground,
                                               const godot::Vector3& wind, const godot::Ref<OlcoreAero>& aero,
                                               const godot::Ref<OlcoreTerrain>& terrain, bool has_cup,
                                               const godot::Vector3& cup, double cup_radius,
                                               double max_time,
                                               const godot::Ref<OlcoreLinksObjects>& links_objects) const {
  godot::Dictionary out;
  if (terrain.is_null() || !terrain->is_baked()) {
    godot::UtilityFunctions::push_error("OlcorePhysics.simulate_shot: terrain is not baked");
    return out;
  }
  olcore::BallState start;
  start.position = to_vec3(start_position);
  start.velocity = to_vec3(start_velocity);
  start.spin = to_vec3(start_spin);
  start.on_ground = on_ground;
  const AeroTables* tables = nullptr;
  if (aero.is_valid() && aero->is_valid()) tables = &aero->tables();
  const olcore::LinksObjects* objects = nullptr;
  if (links_objects.is_valid() && !links_objects->is_empty()) objects = &links_objects->objects();
  NativeShotResult r = run_shot(start, to_vec3(wind), tables, terrain->snapshot(), has_cup, to_vec3(cup),
                                cup_radius, max_time, objects);
  out["outcome"] = r.outcome;
  out["rest"] = from_vec3(r.rest);
  out["first_landing"] = from_vec3(r.first_landing);
  out["rest_surface"] = r.rest_surface;
  out["carry_m"] = r.carry_m;
  out["total_m"] = r.total_m;
  out["apex_m"] = r.apex_m;
  out["time_s"] = r.time_s;
  out["bounces"] = r.bounces;
  out["obstacle_hits"] = r.obstacle_hits;
  godot::PackedFloat32Array times;
  times.resize(static_cast<int>(r.times.size()));
  for (int i = 0; i < times.size(); ++i) times[i] = static_cast<float>(r.times[static_cast<std::size_t>(i)]);
  godot::PackedVector3Array points;
  points.resize(static_cast<int>(r.points.size()));
  for (int i = 0; i < points.size(); ++i) points[i] = from_vec3(r.points[static_cast<std::size_t>(i)]);
  out["times"] = times;
  out["points"] = points;
  return out;
}

godot::Dictionary OlcorePhysics::make_launch(double speed_mps, double launch_deg, double azimuth_deg,
                                             double backspin_rpm, double sidespin_rpm) const {
  olcore::BallState s = olcore::make_launch(speed_mps, launch_deg, azimuth_deg, backspin_rpm, sidespin_rpm);
  godot::Dictionary out;
  out["position"] = from_vec3(s.position);
  out["velocity"] = from_vec3(s.velocity);
  out["spin"] = from_vec3(s.spin);
  return out;
}

godot::String OlcorePhysics::get_version() const { return "olcore-gdext 0.1.0 (olcore snapshot, Godot 4.7)"; }

// ---------------------------------------------------------------- Links launch and swing

godot::Dictionary OlcorePhysics::links_launch(const godot::Ref<OlcoreClubs>& clubs,
                                              const godot::Dictionary& strike) const {
  godot::Dictionary out;
  if (clubs.is_null() || !clubs->is_valid()) {
    godot::UtilityFunctions::push_error("OlcorePhysics.links_launch: no club table");
    return out;
  }
  olcore::LinksStrike s = strike_from_dict(strike);
  if (s.club < 0 || s.club >= olcore::kLinksClubCount) {
    godot::UtilityFunctions::push_error("OlcorePhysics.links_launch: club out of range");
    return out;
  }
  return launch_to_dict(olcore::links_launch(clubs->table(), s));
}

godot::Dictionary OlcorePhysics::links_putt(const godot::Dictionary& strike) const {
  return launch_to_dict(olcore::links_putt(strike_from_dict(strike)));
}

godot::Vector3 OlcorePhysics::links_putt_slope(const godot::Vector3& v, const godot::Vector3& n) const {
  return from_vec3(olcore::links_putt_slope(to_vec3(v), to_vec3(n)));
}

godot::Dictionary OlcorePhysics::links_apply_lie(const godot::Dictionary& strike, const godot::Dictionary& lie,
                                                 int sand_contact) const {
  olcore::LinksStrike s = strike_from_dict(strike);
  olcore::links_apply_lie(s, lie_from_dict(lie), sand_contact);
  godot::Dictionary out;
  out["strike"] = strike_to_dict(s);
  return out;
}

godot::Dictionary OlcorePhysics::links_apply_swing(const godot::Dictionary& strike,
                                                   const godot::Dictionary& swing,
                                                   const godot::Dictionary& lie, int rng_state) const {
  olcore::LinksStrike s = strike_from_dict(strike);
  olcore::LinksRand rng(static_cast<std::uint32_t>(rng_state));
  olcore::links_apply_swing(s, swing_from_dict(swing), lie_from_dict(lie), rng);
  godot::Dictionary out;
  out["strike"] = strike_to_dict(s);
  out["rng_state"] = static_cast<std::int64_t>(rng.state());
  return out;
}

int OlcorePhysics::links_meter_contact(double miss, int skill, int meter_width) const {
  return olcore::links_meter_contact(miss, skill, meter_width);
}

double OlcorePhysics::links_clean_strike_speed(int club, const godot::Dictionary& lie, int skill) const {
  if (club < 0 || club >= olcore::kLinksClubCount) return 1.0;
  return olcore::links_clean_strike_speed(club, lie_from_dict(lie), skill);
}

godot::Dictionary OlcorePhysics::links_computer_miss(const godot::Dictionary& swing,
                                                     const godot::Dictionary& ratings, int club, bool teed_up,
                                                     bool chip, int ground_class, double feet_to_hole,
                                                     int rng_state) const {
  olcore::LinksComputerSwing w = computer_swing_from_dict(swing);
  olcore::LinksRand rng(static_cast<std::uint32_t>(rng_state));
  olcore::links_computer_miss(w, ratings_from_dict(ratings), club, teed_up, chip, ground_class, feet_to_hole,
                              rng);
  godot::Dictionary out;
  out["swing"] = computer_swing_to_dict(w);
  out["rng_state"] = static_cast<std::int64_t>(rng.state());
  return out;
}

godot::Dictionary OlcorePhysics::links_computer_putt_miss(const godot::Dictionary& swing,
                                                          const godot::Dictionary& ratings, int ground_class,
                                                          double feet_to_hole, int rng_state) const {
  olcore::LinksComputerSwing w = computer_swing_from_dict(swing);
  olcore::LinksRand rng(static_cast<std::uint32_t>(rng_state));
  olcore::links_computer_putt_miss(w, ratings_from_dict(ratings), ground_class, feet_to_hole, rng);
  godot::Dictionary out;
  out["swing"] = computer_swing_to_dict(w);
  out["rng_state"] = static_cast<std::int64_t>(rng.state());
  return out;
}

godot::Dictionary OlcorePhysics::links_mouse_swing(const godot::Dictionary& stroke, int rng_state,
                                                   const godot::Dictionary& help) const {
  godot::Dictionary out;
  olcore::LinksMouseStroke m;
  m.skill = static_cast<int>(dict_int(stroke, "skill", 3));
  int shot = static_cast<int>(dict_int(stroke, "shot", 0));
  if (shot < 0 || shot > 2) {
    godot::UtilityFunctions::push_error("OlcorePhysics.links_mouse_swing: shot out of range");
    return out;
  }
  m.shot = static_cast<olcore::LinksMouseShot>(shot);
  m.club = static_cast<int>(dict_int(stroke, "club", 0));
  m.speed = dict_double(stroke, "speed", 0.0);
  m.drift = dict_double(stroke, "drift", 0.0);
  m.drift_before = dict_double(stroke, "drift_before", 0.0);
  m.down = static_cast<int>(dict_int(stroke, "down", 1));
  m.backswing = dict_double(stroke, "backswing", 1.0);
  m.straight = static_cast<int>(dict_int(stroke, "straight", 0));
  olcore::LinksRand rng(static_cast<std::uint32_t>(rng_state));
  olcore::LinksMouseHelp h;
  olcore::LinksMouseHelp* help_ptr = nullptr;
  if (!help.is_empty()) {
    h.enabled = dict_bool(help, "enabled", false);
    h.strokes = static_cast<int>(dict_int(help, "strokes", 0));
    h.still_strokes = static_cast<int>(dict_int(help, "still_strokes", 0));
    help_ptr = &h;
  }
  olcore::LinksMouseSwing o = olcore::links_mouse_swing(m, rng, help_ptr);
  godot::Dictionary outcome;
  outcome["power"] = o.power;
  outcome["face_deg"] = o.face_deg;
  outcome["path_deg"] = o.path_deg;
  outcome["loft"] = o.loft;
  outcome["whiff"] = o.whiff;
  outcome["quality"] = o.quality;
  outcome["help_deg"] = o.help_deg;
  out["outcome"] = outcome;
  out["rng_state"] = static_cast<std::int64_t>(rng.state());
  if (help_ptr != nullptr) {
    godot::Dictionary help_out;
    help_out["enabled"] = h.enabled;
    help_out["strokes"] = h.strokes;
    help_out["still_strokes"] = h.still_strokes;
    out["help"] = help_out;
  }
  return out;
}

}  // namespace olcore_gdext
