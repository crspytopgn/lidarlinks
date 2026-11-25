extends RefCounted
## A few frames from the swing's face-on camera (or the round's own view
## with own=1), for stills and checks. Args: hole, frames, own, hud.
const Common := preload("common.gd")


func run(c) -> void:
	await Common.open_hole(c)
	var g: GolfRound = c.game
	if c.arg("own", "0") != "1":
		var feet := g.golfer.global_position
		var face := g.ball_at - feet
		face.y = 0.0
		face = face.normalized()
		var down := g._aim_dir()
		c.camera_at(feet + face * float(c.arg("dist", "3.0")) + Vector3.UP * float(c.arg("up", "1.0")),
				feet + Vector3.UP * 0.95 + down * float(c.arg("lead", "0.3")), float(c.arg("fov", "32")))
	await c.take()
	await c.frames(int(c.arg("frames", "3")))
