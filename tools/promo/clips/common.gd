extends RefCounted
## Shared steps for the clips.


## Starts hole `c.arg("hole")` (1-based) with the flyover skipped and the
## HUD shown only with hud=1.
static func open_hole(c) -> void:
	var g: GolfRound = c.game
	g.start_hole(int(c.arg("hole", "1")) - 1)
	await c.frames(2)
	g.camera.end_flyover()
	g.hud.hand_over.close()
	c.hud(c.arg("hud", "0") == "1")
	await c.settle()
