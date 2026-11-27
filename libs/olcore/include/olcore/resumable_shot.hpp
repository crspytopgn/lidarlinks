#pragma once

#include <cstdint>

#include "olcore/ball_physics.hpp"
#include "olcore/links_ground.hpp"
#include "olcore/shot.hpp"
#include "olcore/terrain.hpp"

namespace olcore {

// A shot simulation that can be paused between steps and resumed later,
// with exactly the same result as the one-shot simulate_shot.
//
// Why this is safe to pause: both simulations are already loops of small
// fixed steps (0.004 s on the stand-in path, 1/60 s on the Links path),
// and everything one step needs is in this object: the ball, the clock,
// the step count, the result so far, and -- on the Links path -- the
// game's random-number state, which is drawn from in step order. Pausing
// between steps therefore changes nothing about the draws or the
// arithmetic; only the number of steps run per advance() call varies.
// Chunked and unchunked runs of the same shot agree exactly (see
// tests/test_main.cpp: test_shot_chunking).
//
// Step boundaries are the loop iterations of simulate_shot /
// simulate_links_shot: one advance() step is one flight or ground step
// of the original loop, including its landing, bounce, obstacle and cup
// handling. A step never pauses mid-bounce, mid-cup-sub-step or
// mid-nested-step: links_step() runs to the end of its frame step
// (including the cup's 1/1200 s sub-steps) before returning.
//
// The terrain, parameters and options are held by reference/pointer, as
// simulate_shot holds them: they must outlive the simulation, and the
// options' LinksObjects likewise. The Links path also keeps the aero
// tables through BallParams::links.
//
// Budget by step count, not by wall clock: a step count is deterministic
// and portable (the web build has no threads and no useful clock in the
// engine-independent core), while the caller -- GDScript's
// ResumableShot.advance_ms, or a frame loop -- can translate a
// millisecond budget into steps by timing advance() calls. A full drive
// is roughly 1,500-2,500 stand-in steps or 300-900 Links steps.
//
// The one-shot calls stay the default on desktop and worker threads:
// simulate_shot(start, p, terrain, opt) is ResumableShot(...).run().
class ResumableShot {
 public:
  ResumableShot(const BallState& start, const BallParams& p, const Terrain& terrain,
                const ShotOptions& opt = {});

  // Runs up to max_steps loop iterations (at least one when not done).
  // Returns true once the shot has finished (rest, holed, water, out of
  // bounds or timed out). result() is valid only then.
  bool advance(int max_steps);
  // Runs to the end, as simulate_shot does.
  ShotResult run();
  bool done() const { return done_; }
  const ShotResult& result() const { return result_; }
  int steps_done() const { return step_; }
  double time_s() const { return t_; }
  // The Links random state after the steps run so far (0 on the
  // stand-in path, which draws no random numbers). Two runs of the same
  // shot agree on this after the same number of steps, and on the final
  // state when both are done.
  std::uint32_t rng_state() const { return links_ ? rng_.state() : 0; }

 private:
  bool step_standard();
  bool step_links();
  ShotResult finish_standard(ShotOutcome outcome, Vec3 pos);
  ShotResult finish_links(ShotOutcome outcome, Vec3 pos);
  void init_standard();
  void init_links();

  // The shot as given.
  BallState start_;
  const BallParams& params_;
  const Terrain& terrain_;
  ShotOptions opt_;
  bool links_;

  // The result as built so far, and the loop clock.
  ShotResult result_;
  double t_ = 0;
  int step_ = 0;
  bool landed_ = false;
  bool done_ = false;

  // Stand-in path: the ball and whether it is rolling.
  BallState state_;
  bool rolling_ = false;

  // Links path: the ball in the game's frame, its random numbers, the
  // terrain seen in that frame, the hole, the wind and the billboard
  // facing (all fixed for the shot once init_links runs).
  LinksBall ball_;
  LinksRandom rng_;
  TerrainLinksGround ground_;
  LinksCup cup_;
  Vec3 wind_;
  Vec3 facing_{0, -1, 0};
};

}  // namespace olcore
