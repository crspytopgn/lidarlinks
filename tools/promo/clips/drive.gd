extends RefCounted
## A tee shot from the round's own cameras (tracer, landing cam). Args:
## hole, hud, power, acc, secs.
const Common := preload("common.gd")


func run(c) -> void:
	await Common.open_hole(c)
	var g: GolfRound = c.game
	await c.take()
	await c.seconds(float(c.arg("lead", "1.5")))
	g.play_shot(float(c.arg("power", "1.0")), float(c.arg("acc", "0.0")))
	await c.seconds(float(c.arg("secs", "9")))
