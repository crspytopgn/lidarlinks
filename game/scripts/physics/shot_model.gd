class_name ShotModel
extends RefCounted
## The physics behind a shot. The round only talks to this interface, so the
## stand-in model can be replaced by the C++ core (through GDExtension) or by
## one tuned against the original game without touching the game flow.


## Links 2003's shot setup for the next launch: ball position, club face and
## stance, in the game's own steps (square by default). Full swings and chips
## use it; putts ignore it. See ShotShape for the draw, fade, high and low
## the round offers.
var setup := LinksLaunch.Setup.new()
## Extra backspin steps for the next full swing or chip (ShotShape.backspin):
## not a Links 2003 setting, so 0 in Classic Links and for computer golfers.
var backspin := 0
## How far the people playing hit their full swings (PlayerPower.Profile,
## Settings > Hitting distance). Computer golfers plan and swing on a copy
## at Classic: their power is their own (OpponentSkill).
var power_profile: int = PlayerPower.Profile.CLASSIC


## A new model of the same kind on the same tables, square and with nothing
## of this one's last shot: physics run on a worker thread (BackgroundWork)
## gets its own, since launch() and the round's replay set fields per shot.
## It keeps the power profile.
func fresh() -> ShotModel:
	var m := (get_script() as GDScript).new() as ShotModel
	m.power_profile = power_profile
	return m


## Launch state for a swing, with the ball sitting at `from` on a `lie`.
func launch(_club: Club, _power: float, _accuracy: float, _aim_deg: float, _lie: int, from: Vector3) -> BallState:
	push_error("ShotModel.launch() is not implemented")
	return BallState.new(from)


## Flies, bounces and rolls the ball until it stops, drops into the cup at
## `cup`, or ends in water or out of bounds. `wind` is the velocity of the air
## in m/s (see Wind).
func simulate(_start: BallState, _terrain: CourseTerrain, _cup: Vector3, _wind := Vector3.ZERO) -> ShotResult:
	push_error("ShotModel.simulate() is not implemented")
	return ShotResult.new()


## The same shot as simulate(), as a ResumableShot the caller advances a
## few milliseconds a frame instead of blocking on (see ResumableShot):
## the strike on the web build, where there are no worker threads and the
## sim cannot start earlier. The result is the same as simulate()'s.
func simulate_chunked(_start: BallState, _terrain: CourseTerrain, _cup: Vector3, _wind := Vector3.ZERO) -> ResumableShot:
	push_error("ShotModel.simulate_chunked() is not implemented")
	return null


## How much farther than its distance at power 100 (Club.total_m) a full
## swing sends `club` in this model.
func reach_scale(_club: Club) -> float:
	return 1.0


## The share of a full swing's ball speed a shot from `lie` keeps in this
## model, for the reach the game shows and plans with. With a `club`, the
## share that club keeps (a model may hit some clubs worse from a lie).
func lie_power(lie: int, _club: Club = null) -> float:
	return Surface.lie_power(lie)
