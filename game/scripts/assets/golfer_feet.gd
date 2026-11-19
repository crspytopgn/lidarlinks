class_name GolferFeet
extends SkeletonModifier3D
## Plants the golfer's feet on sloping ground. The clips are made on flat
## ground at the golfer's origin; this lowers the hips to the lower foot,
## bends each leg (two-bone IK) so its ankle sits on the ground under it,
## and tilts the feet with the slope. In a bunker the feet are worked down
## into the sand by `sink` (the knees bend; the hips and club stay put).
##
## With a club over the ball (an AT_BALL clip playing on `player`) the hips
## stay where the clip puts them over the ball instead, so the club head still meets it whether the
## ball is above or below his feet: the knees take the difference, as far as
## they can bend or straighten, and with the ball well above his feet he
## stands a little taller and chokes down the grip for the rest, so the club head
## neither digs into the slope nor swings over the ball.

const MAX_SHIFT := 0.35  ## metres, up or down
const MAX_TILT := deg_to_rad(20.0)
const NORMAL_STEP := 0.15  ## metres between height samples for the slope
const MAX_BEND := 0.15  ## metres a knee may bend further to reach higher ground
const MAX_CHOKE := 0.1  ## metres he may choke down the grip
const MAX_LEAN := deg_to_rad(8.0)  ## and stand taller at the waist
## Toward the ball from his feet, in the skeleton's frame (FreeGolfer.BALL).
const BALL_DIR := Vector3(0.0, 0.0, -1.0)
const HEAD_AT := 1.0  ## metres from the grip to the head, near enough for any club
## The shaft, grip to head, in the club bone's frame (tools/golfer/clubs.py).
const SHAFT := Vector3(0.0, -0.11, -1.0)
const AT_BALL_BLEND := 0.4  ## seconds to move between the two stances
## Clips (and their _iron, _2 variants) that hold a club over the ball.
const AT_BALL: Array[String] = ["address", "backswing", "swing", "putt"]

## Ground height at (x, z) in world space; an invalid Callable turns this off.
var ground := Callable()
## Metres the feet are dug into the ground (a bunker stance).
var sink := 0.0
## The golfer's clips, to tell when he stands over the ball.
var player: AnimationPlayer
var _bones := {}
var _club := -1
var _ball_w := 0.0
var _lean_per_m := 0.75  ## radians a metre: about a driver's, until address is read
var _choke_per_lean := 1.2
var _last_us := 0


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or not ground.is_valid():
		return
	if _bones.is_empty():
		for b: String in ["Root", "spine_01", "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]:
			_bones[b] = sk.find_bone(b)
		if _bones.values().has(-1):
			return
		_club = sk.find_bone("club")
	elif _bones.values().has(-1):
		return
	var to_world := sk.global_transform
	var to_sk := to_world.affine_inverse()
	var base_y := to_world.origin.y
	var up := (to_sk.basis * Vector3.UP).normalized()
	var drop: Dictionary[String, float] = {}
	var tilt: Dictionary[String, Vector3] = {}
	for s: String in ["l", "r"]:
		var ankle := to_world * sk.get_bone_global_pose(_bones["foot_" + s]).origin
		var h: float = ground.call(ankle.x, ankle.z)
		drop[s] = clampf(h - base_y, -MAX_SHIFT, MAX_SHIFT)
		var e := NORMAL_STEP
		var dx: float = ground.call(ankle.x - e, ankle.z) - ground.call(ankle.x + e, ankle.z)
		var dz: float = ground.call(ankle.x, ankle.z - e) - ground.call(ankle.x, ankle.z + e)
		tilt[s] = (to_sk.basis * Vector3(dx, 2.0 * e, dz)).normalized()
	var now := Time.get_ticks_usec()
	var step := clampf(float(now - _last_us) / 1e6 / AT_BALL_BLEND, 0.0, 1.0) if _last_us > 0 else 1.0
	_last_us = now
	_ball_w = move_toward(_ball_w, 1.0 if at_ball() else 0.0, step)
	if absf(drop["l"]) < 1e-3 and absf(drop["r"]) < 1e-3 and sink < 1e-3:
		return
	var shift: float = lerpf(minf(drop["l"], drop["r"]), 0.0, _ball_w)
	# Each knee may bend MAX_BEND further, and each leg straighten until
	# it is straight: the hips go no further from the ground than that.
	var lo := -INF
	var hi := INF
	for s: String in ["l", "r"]:
		var hip := sk.get_bone_global_pose(_bones["thigh_" + s]).origin
		var knee := sk.get_bone_global_pose(_bones["calf_" + s]).origin
		var ankle := sk.get_bone_global_pose(_bones["foot_" + s]).origin
		var leg := (hip.distance_to(knee) + knee.distance_to(ankle)) * 0.995
		var w := hip - ankle
		var tall := w.dot(up)
		var wide := (w - up * tall).length()
		var straighten := sqrt(maxf(0.0, leg * leg - wide * wide)) - tall
		hi = minf(hi, drop[s] - sink + maxf(0.0, straighten))
		lo = maxf(lo, drop[s] - sink - MAX_BEND)
	shift = minf(maxf(shift, lo), hi)
	var root: int = _bones["Root"]
	sk.set_bone_pose_position(root, sk.get_bone_pose_position(root) + sk.get_bone_global_pose(root).basis.inverse() * (up * shift))
	if _ball_w > 0.0 and shift < -1e-3 and _club >= 0:
		_stand_tall(sk, up, -shift * _ball_w)


## His legs are straight and his hips still sit `low` below where the club
## needs them (the ball well above his feet). As a player does, he stands a
## little taller at the waist, which carries the club head up and out, and
## chokes down the grip, which brings it up and back in: together the head
## rises `low` and stays the same distance out, at the ball.
func _stand_tall(sk: Skeleton3D, up: Vector3, low: float) -> void:
	var g := sk.get_bone_global_pose(_club)
	var shaft := (g.basis * SHAFT).normalized()
	var waist := sk.get_bone_global_pose(_bones["spine_01"]).origin
	var head := g.origin + shaft * HEAD_AT - waist
	var out := head - up * head.dot(up)
	if out.length() < 0.05:
		return
	# The club's geometry is read at address (the swing and the putt start
	# from there) and kept through the stroke, so the stance holds steady
	# while the club swings round.
	var s_out := shaft.dot(out.normalized())
	if String(player.current_animation).begins_with("address") and s_out > 0.2 and shaft.dot(up) < -0.1:
		var h_down := -head.dot(up)
		# Standing taller by `lean` moves the head (h_down, h_out) * lean
		# out and up; choking down by `choke` moves it (s_out, -s_down) *
		# choke in and up.
		_lean_per_m = 1.0 / (out.length() + h_down * -shaft.dot(up) / s_out)
		_choke_per_lean = h_down / s_out
	var lean := minf(low * _lean_per_m, MAX_LEAN)
	var choke := minf(lean * _choke_per_lean, MAX_CHOKE)
	# Face-on to the ball whichever way the club points now.
	out = BALL_DIR - up * BALL_DIR.dot(up)
	var axis := out.normalized().cross(up)
	GolferLook.turn_bone(sk, _bones["spine_01"], Quaternion(axis, lean))
	g = sk.get_bone_global_pose(_club)
	shaft = (g.basis * SHAFT).normalized()
	var parent := sk.get_bone_global_pose(sk.get_bone_parent(_club))
	sk.set_bone_pose_position(_club, parent.affine_inverse() * (g.origin - shaft * choke))


## True while a clip that holds the club over the ball plays.
func at_ball() -> bool:
	if player == null or not player.is_playing():
		return false
	return String(player.current_animation).get_slice("_", 0) in AT_BALL


## Bends thigh and calf so the foot bone's origin reaches `target`, keeping
## the knee in the plane it was in.
static func _reach(sk: Skeleton3D, thigh: int, calf: int, foot: int, target: Vector3) -> void:
	var a := sk.get_bone_global_pose(thigh).origin
	var b := sk.get_bone_global_pose(calf).origin
	var c := sk.get_bone_global_pose(foot).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < 1e-4 or l2 < 1e-4:
		return
	var to := target - a
	var dist := clampf(to.length(), absf(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	var d := to.normalized()
	var pole := b - a
	var bend := pole - d * pole.dot(d)
	if bend.length_squared() < 1e-8:
		return
	bend = bend.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var mid := a + d * l1 * cos_a + bend * l1 * sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var tip := a + d * dist
	GolferLook.turn_bone(sk, thigh, Quaternion((b - a).normalized(), (mid - a).normalized()))
	var b2 := sk.get_bone_global_pose(calf).origin
	var c2 := sk.get_bone_global_pose(foot).origin
	if (c2 - b2).length_squared() > 1e-8 and (tip - b2).length_squared() > 1e-8:
		GolferLook.turn_bone(sk, calf, Quaternion((c2 - b2).normalized(), (tip - b2).normalized()))
