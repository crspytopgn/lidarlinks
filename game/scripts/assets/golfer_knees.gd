class_name GolferKnees
extends SkeletonModifier3D
## Keeps the knees from bowing outward. The Mixamo takes push the trail
## knee out past its foot as the backswing turns (14 cm off the hip-ankle
## line at the top, the legs bowed like a sumo stance from face on), where
## a tour player braces it over the inside of the trail foot and the lead
## knee kicks in. Here each leg turns about its own hip-ankle line until
## its knee sits no more than MAX_OUT outside that line (away from the
## other foot): the hip and ankle stay put, the knee keeps its bend and the
## foot its turn, so nothing above the hips (or the club) moves. Runs on
## every clip, before GolferFeet, whose leg IK keeps the knee in the plane
## it finds it in.

## Metres a knee may sit outside its hip-ankle line: what the address
## stance has (2 to 3 cm), so a golfer standing over the ball is untouched.
const MAX_OUT := 0.03
## Share of the bow past MAX_OUT kept, so the limit is soft, not a hinge.
const KEEP := 0.2

var _bones := {}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bones.is_empty():
		for b: String in ["thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]:
			_bones[b] = sk.find_bone(b)
	if _bones.values().has(-1):
		return
	var ankle_l := sk.get_bone_global_pose(_bones["foot_l"]).origin
	var ankle_r := sk.get_bone_global_pose(_bones["foot_r"]).origin
	var across := ankle_l - ankle_r
	if across.length_squared() < 1e-4:
		return
	across = across.normalized()
	brace(sk, _bones["thigh_l"], _bones["calf_l"], _bones["foot_l"], across)
	brace(sk, _bones["thigh_r"], _bones["calf_r"], _bones["foot_r"], -across)


## How far (metres) the knee sits outside the hip-ankle line, `out` being
## the outward direction (away from the other foot), in skeleton space.
static func bow(hip: Vector3, knee: Vector3, ankle: Vector3, out: Vector3) -> float:
	var n := (ankle - hip).normalized()
	var o := (knee - hip) - n * (knee - hip).dot(n)
	var u := (out - n * out.dot(n)).normalized()
	return o.dot(u)


## The turn (radians) about the hip-ankle line that brings a knee bowed
## `a` metres out (and `b` metres along the line's other side direction)
## back to MAX_OUT plus KEEP of the excess, its distance off the line kept.
static func swivel(a: float, b: float) -> float:
	if a <= MAX_OUT:
		return 0.0
	var r := sqrt(a * a + b * b)
	var a2 := minf(MAX_OUT + (a - MAX_OUT) * KEEP, r)
	var b2 := sqrt(maxf(0.0, r * r - a2 * a2)) * (1.0 if b >= 0.0 else -1.0)
	return atan2(b2, a2) - atan2(b, a)


static func brace(sk: Skeleton3D, thigh: int, calf: int, foot: int, out: Vector3) -> void:
	var hip := sk.get_bone_global_pose(thigh).origin
	var knee := sk.get_bone_global_pose(calf).origin
	var ankle_pose := sk.get_bone_global_pose(foot)
	var n := (ankle_pose.origin - hip).normalized()
	var o := (knee - hip) - n * (knee - hip).dot(n)
	var u := (out - n * out.dot(n)).normalized()
	var v := n.cross(u)
	var turn := swivel(o.dot(u), o.dot(v))
	if absf(turn) < 1e-4:
		return
	GolferLook.turn_bone(sk, thigh, Quaternion(n, turn))
	GolferLook.set_bone_basis(sk, foot, ankle_pose.basis)
