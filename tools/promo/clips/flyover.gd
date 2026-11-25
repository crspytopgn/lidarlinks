extends RefCounted
## The hole's broadcast flyover, no HUD. Args: hole, secs.
const Common := preload("common.gd")


func run(c) -> void:
	await Common.open_hole(c)
	var g: GolfRound = c.game
	g.camera.start_flyover(g.hole)
	await c.frames(int(c.arg("skip", "0")))
	await c.take()
	await c.seconds(float(c.arg("secs", "6")))
