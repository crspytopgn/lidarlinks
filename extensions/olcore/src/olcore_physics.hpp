// olcore_physics.hpp — Godot binding for the Olcore GDExtension.
//
// Thin classes, all RefCounted so the game can hold them in ShotModel
// instances and pass them between worker threads:
//
//   OlcoreTerrain — a baked SnapshotTerrain (see olcore_snapshot.hpp).
//   OlcoreAero    — Links 2003 drag/lift coefficient tables.
//   OlcoreLinksObjects — the course's billboards and 3D objects for the
//     Links model (olcore::LinksObjects), baked from the GDScript
//     LinksObjects in the game's frame (feet, z up).
//   OlcorePhysics — simulate_shot(): the one hot path, plus the Links
//     launch and mouse-swing primitives (links_launch, links_apply_swing,
//     links_mouse_swing and friends), which mirror the GDScript port.
//
// The binding converts Godot types to olcore types and back and does
// nothing else: club mapping, reach and lie power stay in GDScript
// (LinksShotModel / StandardShotModel). A shot is a pure function of its
// arguments, so simulate_shot() is safe to call from WorkerThreadPool
// threads as long as each thread uses its own OlcorePhysics instance and
// the OlcoreTerrain/OlcoreAero/OlcoreLinksObjects it passes are not being
// re-baked at the same time (OlcoreShotModel bakes once per hole, before
// any shot runs).
#pragma once

// godot-cpp's headers name unused callback parameters, which -Wall
// -Wextra (set by the extension build) reports when this header is
// parsed. Silence just that warning for the third-party includes, so
// this extension still builds warning-free; our own code keeps the
// full warnings.
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"
#endif
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

#include "olcore/links_launch.hpp"
#include "olcore/links_mouse.hpp"
#include "olcore/links_objects.hpp"
#include "olcore/obstacles.hpp"
#include "olcore_snapshot.hpp"

namespace olcore_gdext {

class OlcoreTerrain : public godot::RefCounted {
  GDCLASS(OlcoreTerrain, godot::RefCounted)
 public:
  // Bakes a grid from GDScript arrays. heights is nx*nz floats (metres),
  // surfaces nx*nz bytes (Surface.Type ints), green_surfaces is
  // nx*nz*10 floats (LinksSurface fields) with has_green marking the cells
  // that override the class defaults; either green array may be empty.
  // Returns false when the shapes do not match.
  bool bake(double origin_x, double origin_z, double cell, int nx, int nz,
            const godot::PackedFloat32Array& heights, const godot::PackedByteArray& surfaces,
            const godot::PackedFloat32Array& green_surfaces, const godot::PackedByteArray& has_green);
  void bake_flat(int surface, double height);
  // Bakes the obstacles the shot can meet, from the merged fields
  // OlcoreShotModel exports (see ObstacleField export in GDScript).
  // cylinders is 6 floats per item (x, z, radius, y0, y1, kind) and boxes
  // 16 per item (centre, three basis columns, half sizes, kind), all in
  // Godot metres. Call after bake(); a later bake() drops the field.
  // Returns false when the shapes do not match or a kind is out of range.
  bool bake_obstacles(const godot::PackedFloat32Array& cylinders, const godot::PackedFloat32Array& boxes);
  bool is_baked() const;
  bool has_obstacles() const;
  double height_at(double x, double z) const;
  int surface_at(double x, double z) const;
  int cell_count() const;
  godot::Vector2 get_origin() const;
  double get_cell_size() const;
  godot::Vector2i get_size() const;
  // The snapshot the physics runs over. Read-only after bake().
  const SnapshotTerrain& snapshot() const { return snapshot_; }

 protected:
  static void _bind_methods();

 private:
  SnapshotTerrain snapshot_{SnapshotGrid{}};
};

class OlcoreAero : public godot::RefCounted {
  GDCLASS(OlcoreAero, godot::RefCounted)
 public:
  // Each table is a Dictionary {speeds, spins, values} of
  // PackedFloat64Array, as LinksAero holds them in GDScript.
  bool set_tables(const godot::Dictionary& drag, const godot::Dictionary& lift);
  bool is_valid() const;
  const AeroTables& tables() const { return tables_; }

 protected:
  static void _bind_methods();

 private:
  AeroTables tables_;
};

// Links 2003's per-club launch table (olcore::LinksClubTable), read from
// the player's executable into LinksLaunch in GDScript. Five arrays of 19
// (spin, speed, loft_deg, glance, ball_position), in club order (driver
// first, putter apart).
class OlcoreClubs : public godot::RefCounted {
  GDCLASS(OlcoreClubs, godot::RefCounted)
 public:
  bool set_table(const godot::PackedFloat64Array& spin, const godot::PackedFloat64Array& speed,
                 const godot::PackedFloat64Array& loft_deg, const godot::PackedFloat64Array& glance,
                 const godot::PackedFloat64Array& ball_position);
  bool is_valid() const;
  const olcore::LinksClubTable& table() const { return table_; }

 protected:
  static void _bind_methods();

 private:
  olcore::LinksClubTable table_;
  bool valid_ = false;
};

// The course's Links 2003 billboards and 3D objects (olcore::LinksObjects),
// baked from the GDScript LinksObjects. All coordinates are in the game's
// frame (feet, z up), exactly as LinksObjects holds them; only the
// billboards and models inside the baked shot box are passed in (see
// LinksObjects export in GDScript). Masks are alpha bytes: billboard
// masks bottom-row first (LinksSpriteMask row 0 is the bottom row), 3D
// hole masks top-row first (their uvs count v = 0 at the top).
class OlcoreLinksObjects : public godot::RefCounted {
  GDCLASS(OlcoreLinksObjects, godot::RefCounted)
 public:
  // One entry per object type: collision (int), shape (6 floats), aspect,
  // and the mask (width, height, and alpha bytes at mask_offsets[i] in the
  // concatenated mask_alphas; width 0 means no mask, as in GDScript when
  // ObjType.mask is null). Returns false when the shapes do not match.
  bool set_types(const godot::PackedInt32Array& collisions, const godot::PackedFloat32Array& shapes,
                 const godot::PackedFloat32Array& aspects, const godot::PackedInt32Array& mask_widths,
                 const godot::PackedInt32Array& mask_heights, const godot::PackedByteArray& mask_alphas,
                 const godot::PackedInt32Array& mask_offsets);
  // One billboard: base in the game's frame, height in feet, anchors as
  // fractions, and the index into the types set with set_types().
  void add_billboard(const godot::Vector3& base, double height, double anchor_x, double anchor_z, int type);
  // One 3D mesh: positions in model units, uvs one per corner (v = 0 at
  // the top), corners as position indices, faces as triples (first corner,
  // corner count, texture), and the see-through holes per texture
  // (hole_widths[i] == 0 means a solid texture). Returns the mesh index,
  // or -1 when the shapes do not match.
  int add_mesh(const godot::PackedVector3Array& positions, const godot::PackedVector2Array& uvs,
               const godot::PackedInt32Array& corners, const godot::PackedInt32Array& faces,
               const godot::PackedInt32Array& hole_widths, const godot::PackedInt32Array& hole_heights,
               const godot::PackedByteArray& hole_alphas, const godot::PackedInt32Array& hole_offsets);
  // One placed 3D object: its mesh's points already placed, in the game's
  // frame. Returns false when the mesh index is out of range or the
  // points are empty.
  bool add_model(int mesh, const godot::PackedVector3Array& points);
  int billboard_count() const;
  int model_count() const;
  bool is_empty() const;
  const olcore::LinksObjects& objects() const { return objects_; }

 protected:
  static void _bind_methods();

 private:
  olcore::LinksObjects objects_;
};

class OlcorePhysics : public godot::RefCounted {
  GDCLASS(OlcorePhysics, godot::RefCounted)
 public:
  // Runs olcore::simulate_shot over a baked terrain. With aero set, the
  // Links 2003 model runs; without it, the stand-in model runs. With
  // links_objects set, the Links model also meets the course's billboards
  // and 3D objects (ignored by the stand-in model, as in the GDScript
  // port). Returns a Dictionary mirroring ShotResult: outcome (int,
  // ShotResult.Outcome order), rest, first_landing (Vector3),
  // rest_surface (int), carry_m, total_m, apex_m, time_s, bounces,
  // obstacle_hits, times (PackedFloat32Array), points
  // (PackedVector3Array). Returns an empty Dictionary and logs an error
  // when the terrain is not baked.
  godot::Dictionary simulate_shot(const godot::Vector3& start_position, const godot::Vector3& start_velocity,
                                  const godot::Vector3& start_spin, bool on_ground, const godot::Vector3& wind,
                                  const godot::Ref<OlcoreAero>& aero, const godot::Ref<OlcoreTerrain>& terrain,
                                  bool has_cup, const godot::Vector3& cup, double cup_radius = 0.054,
                                  double max_time = 60.0,
                                  const godot::Ref<OlcoreLinksObjects>& links_objects =
                                      godot::Ref<OlcoreLinksObjects>()) const;
  // Mirrors olcore::make_launch. Returns {position, velocity, spin}.
  godot::Dictionary make_launch(double speed_mps, double launch_deg, double azimuth_deg, double backspin_rpm,
                                double sidespin_rpm) const;
  godot::String get_version() const;

  // --- Links 2003 launch and swing (olcore::links_launch / apply_swing /
  // mouse_swing), mirroring LinksLaunch / LinksMouse in GDScript. ---
  //
  // A strike is a Dictionary {club, aim, power, face_error, path_error,
  // speed_scale, spin_scale, loft_scale, setup_ball_position, setup_face,
  // setup_stance, ground_normal (Vector3)}; a lie is {ground_class,
  // restitution, impact_friction, skid_friction, impact_drag,
  // roll_resistance, stop_speed, spin_grip, lie_spin, lie_power} — the
  // ten LinksSurface fields in the order the green bake uses. A swing is
  // {method (0 PowerStroke, 1 Mouse), skill, contact, full_power,
  // mouse_face_deg, mouse_path_deg, mouse_loft, left_handed, chip,
  // teed_up}. The game's rand draws run through rng_state (an int holding
  // the LinksRand state, as LinksLaunch.Rand.state holds it): functions
  // that draw return it updated, so the next call draws what the
  // GDScript port would. A bad table, strike or swing returns an empty
  // Dictionary. Velocities and spins are in the game's frame (ft/s,
  // rev/s), as LinksLaunch.launch returns them.
  //
  // links_launch / links_putt: {velocity, spin} for a strike.
  godot::Dictionary links_launch(const godot::Ref<OlcoreClubs>& clubs, const godot::Dictionary& strike) const;
  godot::Dictionary links_putt(const godot::Dictionary& strike) const;
  // Tilts a putt's velocity or spin onto ground with unit normal n.
  godot::Vector3 links_putt_slope(const godot::Vector3& v, const godot::Vector3& n) const;
  // What a lie does to a strike: {strike}. sand_contact is the swing
  // meter's miss in whole steps (0 for the standard splash).
  godot::Dictionary links_apply_lie(const godot::Dictionary& strike, const godot::Dictionary& lie,
                                    int sand_contact = 0) const;
  // What a swing and a lie do to a strike: {strike, rng_state}.
  godot::Dictionary links_apply_swing(const godot::Dictionary& strike, const godot::Dictionary& swing,
                                      const godot::Dictionary& lie, int rng_state) const;
  // The PowerStroke meter's accuracy in whole steps for a snap landing
  // `miss` meter units past the perfect zone.
  int links_meter_contact(double miss, int skill, int meter_width = 192) const;
  // The share of ball speed a clean strike from `lie` keeps with `club`
  // at `skill`.
  double links_clean_strike_speed(int club, const godot::Dictionary& lie, int skill) const;
  // A computer golfer's miss: {swing, rng_state}, where a swing is
  // {power, face_deg, path_deg} and ratings is {tee, woods, long_irons,
  // mid_irons, short_irons, wedges, chips, max_power, steady, long_putts,
  // short_putts}.
  godot::Dictionary links_computer_miss(const godot::Dictionary& swing, const godot::Dictionary& ratings,
                                       int club, bool teed_up, bool chip, int ground_class,
                                       double feet_to_hole, int rng_state) const;
  // A computer golfer's putt miss: {swing, rng_state}.
  godot::Dictionary links_computer_putt_miss(const godot::Dictionary& swing, const godot::Dictionary& ratings,
                                            int ground_class, double feet_to_hole, int rng_state) const;
  // What a mouse stroke makes of a swing: {outcome, rng_state, help},
  // where a stroke is {skill, shot (0 Full, 1 Chip, 2 Putt), club, speed,
  // drift, drift_before, down, backswing, straight}, an outcome is
  // {power, face_deg, path_deg, loft, whiff, quality, help_deg}, and help
  // is {enabled, strokes, still_strokes} (empty means no swing help).
  godot::Dictionary links_mouse_swing(const godot::Dictionary& stroke, int rng_state,
                                      const godot::Dictionary& help = godot::Dictionary()) const;

 protected:
  static void _bind_methods();
};

}  // namespace olcore_gdext
