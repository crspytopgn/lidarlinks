#include "olcore/shot.hpp"

#include <algorithm>
#include <cmath>

#include "olcore/links_ground.hpp"
#include "olcore/resumable_shot.hpp"

namespace olcore {

namespace {

double horizontal_distance(Vec3 a, Vec3 b) {
  double dx = a.x - b.x, dz = a.z - b.z;
  return std::sqrt(dx * dx + dz * dz);
}

// Horizontal distance from point c to the segment a-b.
double segment_distance_xz(Vec3 a, Vec3 b, Vec3 c) {
  double abx = b.x - a.x, abz = b.z - a.z;
  double len2 = abx * abx + abz * abz;
  double t = len2 > 0 ? ((c.x - a.x) * abx + (c.z - a.z) * abz) / len2 : 0.0;
  t = std::clamp(t, 0.0, 1.0);
  return horizontal_distance({a.x + abx * t, 0, a.z + abz * t}, c);
}

constexpr double kRadToDeg = 57.29577951308232;
constexpr double kMaxCraterDeg = 30.0;

constexpr double kSolidRestitution = 0.35;  // normal speed kept off a trunk or wall
constexpr double kSolidFriction = 0.75;     // speed along the face kept
constexpr double kCanopyKeep = 0.2;         // speed kept going into leaves
constexpr double kCanopyBounce = 0.05;      // normal speed kept coming back out
constexpr double kObstacleGap = 0.01;       // m; keeps the ball off the face it hit
constexpr double kLoftedLaunch = 0.1;       // launch v.y / speed above which a shot is in the air
constexpr double kTakeOffGap = 0.005;       // m a step; a rolling ball this far above the ground has left it
constexpr double kFlatTop = 0.7;            // normal y above which the ball can rest on a solid
constexpr double kLandAtStart = 0.01;       // landing this early in a step: on the ground at its start

bool is_hazard_stop(Surface s) { return s == Surface::Water || s == Surface::OutOfBounds; }

}  // namespace

const char* surface_name(Surface s) {
  switch (s) {
    case Surface::Tee: return "Tee";
    case Surface::Fairway: return "Fairway";
    case Surface::Fringe: return "Fringe";
    case Surface::Green: return "Green";
    case Surface::Rough: return "Rough";
    case Surface::DeepRough: return "Deep rough";
    case Surface::Sand: return "Sand";
    case Surface::Water: return "Water";
    case Surface::OutOfBounds: return "Out of bounds";
  }
  return "?";
}

SurfaceParams surface_params(Surface s) {
  //        restitution, friction, softness, rolling resistance, lie power, lie spin
  // The rough's lie power and spin are fitted so 5-wood to lob wedge lose
  // what Links 2003's own lies take off them (carry and total, flat ground).
  switch (s) {
    case Surface::Tee: return {1.00, 0.40, 1.0, 0.16, 1.00, 1.00};
    case Surface::Fairway: return {1.00, 0.40, 1.0, 0.16, 1.00, 1.00};
    case Surface::Fringe: return {0.90, 0.45, 1.0, 0.10, 0.95, 0.90};
    case Surface::Green: return {0.85, 0.45, 1.0, 0.055, 1.00, 1.00};
    case Surface::Rough: return {0.60, 0.60, 1.2, 0.30, 0.97, 0.74};
    case Surface::DeepRough: return {0.40, 0.80, 1.4, 0.50, 0.855, 0.66};
    case Surface::Sand: return {0.12, 0.90, 1.6, 0.90, 0.75, 0.70};
    case Surface::Water: return {0.00, 1.00, 1.0, 1.0, 0.00, 0.00};
    case Surface::OutOfBounds: return {0.60, 0.60, 1.2, 0.30, 0.97, 0.74};
  }
  return {1, 0.4, 1.0, 0.16, 1, 1};
}

Vec3 Terrain::normal(double x, double z) const {
  const double e = 0.25;
  double dx = height(x + e, z) - height(x - e, z);
  double dz = height(x, z + e) - height(x, z - e);
  Vec3 n{-dx, 2 * e, -dz};
  return n * (1.0 / length(n));
}

const char* outcome_name(ShotOutcome o) {
  switch (o) {
    case ShotOutcome::Rest: return "Rest";
    case ShotOutcome::Holed: return "Holed";
    case ShotOutcome::Water: return "Water";
    case ShotOutcome::OutOfBounds: return "Out of bounds";
    case ShotOutcome::TimedOut: return "Timed out";
  }
  return "?";
}

double turf_restitution(double normal_speed) {
  double v = std::fabs(normal_speed);
  if (v > 20.0) {
    return 0.12;
  }
  return 0.510 - 0.0375 * v + 0.000903 * v * v;
}

void bounce(Vec3& velocity, Vec3& spin, Vec3 n, Surface surface, const BallParams& p) {
  if (dot(velocity, n) >= 0) {
    return;
  }
  SurfaceParams sp = surface_params(surface);

  // The ball dents the turf, so it meets a crater wall that is tilted back
  // towards it. Penner's fit for the tilt grows with impact speed and angle.
  Vec3 along = velocity - n * dot(velocity, n);
  double along_len = length(along);
  double speed = length(velocity);
  if (along_len > 1e-9 && speed > 1e-9) {
    double impact_deg = std::asin(std::min(1.0, -dot(velocity, n) / speed)) * kRadToDeg;
    double tilt_deg = std::min(kMaxCraterDeg, sp.softness * 15.4 * (speed / 18.6) * (impact_deg / 44.4));
    double tilt = tilt_deg / kRadToDeg;
    n = n * std::cos(tilt) - along * (std::sin(tilt) / along_len);
  }

  double vn = dot(velocity, n);
  if (vn >= 0) {
    return;
  }
  double e = turf_restitution(-vn) * sp.restitution_scale;
  double jn = (1 + e) * -vn;  // normal impulse per unit mass

  Vec3 vt = velocity - n * vn;
  // Velocity of the contact point (bottom of the ball) along the ground.
  Vec3 vc = vt + cross(spin, n * -p.radius);
  double vc_len = length(vc);
  if (vc_len > 1e-9) {
    // A solid sphere stops slipping after a tangential impulse of 2/7 m|vc|;
    // friction caps it at mu times the normal impulse.
    double j = std::min(2.0 / 7.0 * vc_len, sp.friction * jn);
    Vec3 dir = vc * (1.0 / vc_len);
    vt = vt - dir * j;
    spin = spin + cross(n, dir) * (2.5 * j / p.radius);
  }
  // Most spin about the normal (sidespin) scrubs off on the turf.
  spin = spin - n * (dot(spin, n) * 0.5);
  velocity = vt + n * (-e * vn);
}

void hit_obstacle(Vec3& velocity, Vec3& spin, const ObstacleHit& hit) {
  double vn = dot(velocity, hit.normal);
  if (vn >= 0) {
    return;
  }
  Vec3 vt = velocity - hit.normal * vn;
  if (hit.kind == ObstacleKind::Solid) {
    velocity = vt * kSolidFriction - hit.normal * (vn * kSolidRestitution);
    spin = spin * 0.5;
  } else {
    velocity = vt * kCanopyKeep - hit.normal * (vn * kCanopyBounce);
    spin = spin * 0.2;
  }
}

void ResumableShot::init_standard() {
  state_ = start_;
  Vec3 n0 = terrain_.normal(state_.position.x, state_.position.z);
  double vn0 = dot(state_.velocity, n0);
  double speed0 = length(state_.velocity);
  if (vn0 < 2 * opt_.roll_threshold && state_.velocity.y > kLoftedLaunch * speed0) {
    // A lofted shot from a lie on a bank (a bunker face) leaves the slope:
    // the club follows the ground, so the launch is off the slope too.
    Vec3 v = state_.velocity + n0 * (std::max(std::fabs(vn0), 2 * opt_.roll_threshold) - vn0);
    state_.velocity = v * (speed0 / length(v));
    vn0 = dot(state_.velocity, n0);
  }
  if (vn0 < -opt_.roll_threshold) {
    // Struck into a bank steeper than its launch (a bunker face): it meets
    // the ground at once, rather than rolling away at full speed.
    bounce(state_.velocity, state_.spin, n0, terrain_.surface(state_.position.x, state_.position.z), params_);
    ++result_.bounces;
    vn0 = dot(state_.velocity, n0);
  }
  rolling_ = vn0 < opt_.roll_threshold;
  if (rolling_) {
    state_.velocity = state_.velocity - n0 * vn0;
    landed_ = true;
    result_.first_landing = state_.position;
  }
}

ShotResult ResumableShot::finish_standard(ShotOutcome o, Vec3 pos) {
  ShotResult r = result_;
  // A course can limit each hole to an outline; it is judged where the ball
  // stops.
  if (o == ShotOutcome::Rest && !terrain_.in_bounds(pos.x, pos.z)) o = ShotOutcome::OutOfBounds;
  r.outcome = o;
  r.rest = pos;
  r.time_s = t_;
  r.rest_surface = terrain_.surface(pos.x, pos.z);
  if (!landed_) {
    r.first_landing = pos;
  }
  r.carry_m = horizontal_distance(start_.position, r.first_landing);
  r.total_m = horizontal_distance(start_.position, pos);
  if (r.path.empty() || r.path.back().t < t_) {
    r.path.push_back({t_, pos});
  }
  return r;
}

// One iteration of the old simulate_shot loop: one flight or ground step.
// Returns true once the shot has finished. The `continue`s of the loop
// are returns of false here (the step ran, the shot goes on); the
// `return finish(...)`s set the result and return true. The sample at
// the bottom of the loop is only appended on the paths that fell through
// to it, as before.
bool ResumableShot::step_standard() {
  if (t_ >= opt_.max_time) {
    result_ = finish_standard(ShotOutcome::TimedOut, state_.position);
    return true;
  }
  if (!rolling_) {
    BallState next = step_flight(state_, params_, opt_.dt);
    double h0 = state_.position.y - terrain_.height(state_.position.x, state_.position.z);
    double h1 = next.position.y - terrain_.height(next.position.x, next.position.z);
    t_ += opt_.dt;
    ++step_;
    result_.apex_m = std::max(result_.apex_m, next.position.y - start_.position.y);

    // An obstacle met before the ground. Time keeps the whole step, so a
    // ball wedged between obstacles still runs out of time.
    double ground = h1 <= 0 ? (h0 > 0 ? h0 / (h0 - h1) : 0.0) : 2.0;
    ObstacleHit hit;
    if (terrain_.obstacle_hit(state_.position, next.position, hit) && hit.fraction < ground) {
      Vec3 pos = state_.position + (next.position - state_.position) * hit.fraction;
      Vec3 vel = state_.velocity + (next.velocity - state_.velocity) * hit.fraction;
      Vec3 spin = next.spin;
      hit_obstacle(vel, spin, hit);
      // Just outside a solid, or just inside a canopy, so the same face
      // is not met again.
      pos = pos + hit.normal * (hit.kind == ObstacleKind::Solid ? kObstacleGap : -kObstacleGap);
      ++result_.obstacle_hits;
      result_.path.push_back({t_, pos});
      // Settled on top of something flat enough (a wall, a bridge).
      if (hit.kind == ObstacleKind::Solid && hit.normal.y > kFlatTop && dot(vel, hit.normal) < opt_.roll_threshold) {
        if (!landed_) {
          landed_ = true;
          result_.first_landing = pos;
        }
        result_ = finish_standard(ShotOutcome::Rest, pos);
        return true;
      }
      state_ = BallState{pos, vel, spin};
      return false;
    }

    if (h1 <= 0) {
      // Back up to the moment of contact.
      double frac = h0 > 0 ? h0 / (h0 - h1) : 0.0;
      Vec3 pos = state_.position + (next.position - state_.position) * frac;
      Vec3 vel = state_.velocity + (next.velocity - state_.velocity) * frac;
      pos.y = terrain_.height(pos.x, pos.z);
      t_ = t_ - opt_.dt + opt_.dt * frac;
      if (!landed_) {
        landed_ = true;
        result_.first_landing = pos;
      }
      result_.path.push_back({t_, pos});

      Surface surf = terrain_.surface(pos.x, pos.z);
      if (surf == Surface::Water) {
        result_ = finish_standard(ShotOutcome::Water, pos);
        return true;
      }
      if (surf == Surface::OutOfBounds) {
        result_ = finish_standard(ShotOutcome::OutOfBounds, pos);
        return true;
      }
      if (opt_.has_cup && horizontal_distance(pos, opt_.cup) < opt_.cup_radius) {
        result_ = finish_standard(ShotOutcome::Holed, opt_.cup);
        return true;
      }

      Vec3 n = terrain_.normal(pos.x, pos.z);
      // Already moving off the ground's plane yet under the ground: the
      // slope ahead is steeper than the normal (the foot of a bunker face).
      // It rolls up it, rather than meeting it again at once for ever.
      bool leaving = dot(vel, n) >= 0;
      Vec3 spin = next.spin;
      bounce(vel, spin, n, surf, params_);
      ++result_.bounces;
      state_ = BallState{pos, vel, spin};
      double vn = dot(vel, n);
      // A ball that meets the ground at the very start of a step (or a
      // hair after it) was on it already (a bank ahead rising faster than
      // it flies): it rolls from there. Bounced again it would land at
      // almost the same instant, again and again, and never finish.
      if (vn < opt_.roll_threshold || frac < kLandAtStart || leaving) {
        rolling_ = true;
        state_.velocity = vel - n * vn;
      }
      return false;
    }
    state_ = next;
  } else {
    Vec3 pos = state_.position;
    Vec3 v = state_.velocity;
    Vec3 n = terrain_.normal(pos.x, pos.z);
    SurfaceParams sp = surface_params(terrain_.surface(pos.x, pos.z));

    Vec3 g{0, -params_.gravity, 0};
    Vec3 slope = (g - n * dot(g, n)) * (5.0 / 7.0);
    double resist = sp.rolling_resistance * params_.gravity * n.y;
    double speed = length(v);
    bool holds = length(slope) <= resist;  // static friction holds the ball
    if (speed < opt_.stop_speed && holds) {
      result_ = finish_standard(ShotOutcome::Rest, pos);
      return true;
    }
    Vec3 a = slope;
    if (speed > 1e-9) {
      a = a - v * (resist / speed);
    }
    Vec3 nv = v + a * opt_.dt;
    if (speed > 1e-9 && dot(nv, v) < 0 && holds) {
      result_ = finish_standard(ShotOutcome::Rest, pos);
      return true;
    }
    Vec3 npos = pos + nv * opt_.dt;
    npos.y = terrain_.height(npos.x, npos.z);
    // Over a crest (a bunker's lip) faster than gravity can hold it to
    // the ground: it takes off, without the spin it rolled with.
    double free_y = pos.y + nv.y * opt_.dt - 0.5 * params_.gravity * opt_.dt * opt_.dt;
    if (free_y - npos.y > kTakeOffGap) {
      // The step is taken in the air, so time always moves on.
      rolling_ = false;
      state_ = BallState{Vec3{npos.x, free_y, npos.z}, nv + Vec3{0, -params_.gravity * opt_.dt, 0}, Vec3{}};
      t_ += opt_.dt;
      ++step_;
      return false;
    }
    Vec3 nn = terrain_.normal(npos.x, npos.z);
    nv = nv - nn * dot(nv, nn);
    t_ += opt_.dt;
    ++step_;

    // Rolling into a trunk or a wall; leaves do not stop a rolling ball.
    ObstacleHit hit;
    if (terrain_.obstacle_hit(pos, npos, hit) && hit.kind == ObstacleKind::Solid) {
      Vec3 hp = pos + (npos - pos) * hit.fraction + hit.normal * kObstacleGap;
      hp.y = terrain_.height(hp.x, hp.z);
      hit_obstacle(nv, state_.spin, hit);
      Vec3 hn = terrain_.normal(hp.x, hp.z);
      state_.position = hp;
      state_.velocity = nv - hn * dot(nv, hn);
      ++result_.obstacle_hits;
      result_.path.push_back({t_, hp});
      return false;
    }

    if (opt_.has_cup && length(nv) < opt_.max_holing_speed &&
        segment_distance_xz(pos, npos, opt_.cup) < opt_.cup_radius) {
      result_ = finish_standard(ShotOutcome::Holed, opt_.cup);
      return true;
    }
    Surface surf = terrain_.surface(npos.x, npos.z);
    if (is_hazard_stop(surf)) {
      result_ = finish_standard(surf == Surface::Water ? ShotOutcome::Water : ShotOutcome::OutOfBounds, npos);
      return true;
    }
    state_.position = npos;
    state_.velocity = nv;
  }
  if (opt_.sample_every > 0 && step_ % opt_.sample_every == 0) {
    result_.path.push_back({t_, state_.position});
  }
  return false;
}

ShotResult simulate_shot(const BallState& start, const BallParams& p, const Terrain& terrain,
                         const ShotOptions& opt) {
  ResumableShot sim(start, p, terrain, opt);
  return sim.run();
}

}  // namespace olcore
