#include "olcore/resumable_shot.hpp"

namespace olcore {

ResumableShot::ResumableShot(const BallState& start, const BallParams& p, const Terrain& terrain,
                             const ShotOptions& opt)
    : start_(start), params_(p), terrain_(terrain), opt_(opt), links_(p.links != nullptr), ground_(terrain) {
  result_.path.push_back({0, start_.position});
  if (links_) {
    init_links();
  } else {
    init_standard();
  }
}

bool ResumableShot::advance(int max_steps) {
  if (done_) {
    return true;
  }
  if (max_steps < 1) {
    max_steps = 1;
  }
  for (int i = 0; i < max_steps && !done_; ++i) {
    // Each step method ends the shot itself when its time runs out, as
    // the one-shot loops did on leaving their while.
    done_ = links_ ? step_links() : step_standard();
  }
  return done_;
}

ShotResult ResumableShot::run() {
  while (!advance(1024)) {
  }
  return result_;
}

}  // namespace olcore
