extends RefCounted
## A slow, low drone shot down the hole: from behind the tee (back metres,
## up metres high) gliding `travel` of the way to the pin over `secs`,
## looking ahead at the green. No HUD. Args: hole, back, up, travel, secs,
## fov, side (metres to the right of the line), golfer=1 keeps the golfer.
const Common := preload("common.gd")


func run(c) -> void:
	await Common.open_hole(c)
	var g: GolfRound = c.game
	# A beauty shot: no aim ring or green grid.
	g.aim_marker.visible = false
	g.green_grid.visible = false
	var tee := g.hole.tee
	var pin := g.hole.pin
	var dir := Vector3(pin.x - tee.x, 0.0, pin.z - tee.z)
	var length := dir.length()
	dir /= length
	var right := dir.cross(Vector3.UP)
	var back := float(c.arg("back", "30"))
	var up := float(c.arg("up", "18"))
	var side := float(c.arg("side", "0"))
	var travel := float(c.arg("travel", "0.35"))
	var secs := float(c.arg("secs", "6"))
	var fov := float(c.arg("fov", "50"))
	var look_up := float(c.arg("look_up", "0"))
	if c.arg("golfer", "0") != "1" and g.golfer != null:
		g.golfer.visible = false
	var t := g.hole.terrain
	var n := roundi(secs * 30.0)
	var start := tee - dir * back + right * side
	var end := tee + dir * (length * travel) + right * side * 0.5
	var cam: Camera3D = null
	for i in n + 1:
		var u := float(i) / n
		var e := u * u * (3.0 - 2.0 * u) * 0.5 + u * 0.5  # gentle ease in and out
		var p := start.lerp(end, e)
		p.y = maxf(t.height_at(p.x, p.z), tee.y) + up
		var look := pin + Vector3.UP * look_up
		cam = c.camera_at(p, look, fov)
		if i == 0:
			await c.settle()
			await c.take()
		await c.frames(1)
