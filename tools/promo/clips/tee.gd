extends RefCounted
## The golfer on the tee from behind, the hole ahead, a slow push in; for
## the weather and birdsong shots. Args: hole, secs, back, up, fov, calls
## (bird calls to force, one every 1.5 s from the start).
const Common := preload("common.gd")


func run(c) -> void:
	await Common.open_hole(c)
	var g: GolfRound = c.game
	# A beauty shot: no aim ring or green grid.
	g.aim_marker.visible = false
	g.green_grid.visible = false
	var ball := g.ball_at
	var pin := g.hole.pin
	var dir := Vector3(pin.x - ball.x, 0.0, pin.z - ball.z).normalized()
	var right := dir.cross(Vector3.UP)
	var back := float(c.arg("back", "7"))
	var up := float(c.arg("up", "2.2"))
	var side := float(c.arg("side", "1.2"))
	var secs := float(c.arg("secs", "5"))
	var push := float(c.arg("push", "1.5"))
	var fov := float(c.arg("fov", "45"))
	var calls := int(c.arg("calls", "0"))
	var amb: FreeAmbience = g.free_ambience
	var n := roundi(secs * 30.0)
	var look := ball + dir * 120.0 + Vector3.UP * 6.0
	for i in n + 1:
		var u := float(i) / n
		var p := ball - dir * (back - push * u) + right * side + Vector3.UP * up
		c.camera_at(p, look, fov)
		if i == 0:
			await c.settle()
			await c.take()
		if calls > 0 and amb != null and i % 45 == 10 and i / 45 < calls:
			amb._bird_call()
		await c.frames(1)
