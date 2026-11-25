extends RefCounted
## The golfer's swing up close and slowed down, face on. Args: hole, dist,
## slow, secs.
const Common := preload("common.gd")


func run(c) -> void:
	await Common.open_hole(c)
	var g: GolfRound = c.game
	var feet := g.golfer.global_position
	var face := g.ball_at - feet
	face.y = 0.0
	face = face.normalized()
	var down := g._aim_dir()
	var side := float(c.arg("side", "0.0"))
	c.camera_at(feet + face * float(c.arg("dist", "3.0")) + down * side + Vector3.UP * float(c.arg("up", "1.0")),
			feet + Vector3.UP * 0.95 + down * float(c.arg("lead", "0.3")), float(c.arg("fov", "32")))
	await c.take()
	await c.seconds(0.4)
	Engine.time_scale = float(c.arg("slow", "0.25"))
	g.play_shot(1.0, 0.0)
	await c.seconds(float(c.arg("secs", "5")))
	Engine.time_scale = 1.0
