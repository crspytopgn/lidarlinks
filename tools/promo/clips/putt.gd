extends RefCounted
## A holed putt with the green grid. Args: hole, m (from the pin), grid
## (3: TV slope grid), hud, read (seconds before the stroke), secs.
const Common := preload("common.gd")


func run(c) -> void:
	await Common.open_hole(c)
	var g: GolfRound = c.game
	# A putt for birdie, not a hole in one.
	g.strokes = int(c.arg("strokes", "2"))
	g.players[g.current].shots = g.strokes
	c.ball_from_pin(float(c.arg("m", "6")))
	await c.frames(5)
	var club := g.clubs[g.club_index]
	var pin := g.hole.pin
	var d := Vector2(pin.x - g.ball_at.x, pin.z - g.ball_at.z).length()
	var guess := sqrt(2.0 * Surface.rolling_resistance(Surface.Type.GREEN) * BallPhysics.GRAVITY * (d + 0.3)) / club.ball_speed_mps
	var dir := Vector3(pin.x - g.ball_at.x, 0.0, pin.z - g.ball_at.z).normalized()
	var left := Vector3.UP.cross(dir)
	var power := -1.0
	for i in 61:
		var off := 0.05 * ceili(i / 2.0) * (1 if i % 2 == 0 else -1)
		g.aim_at(pin + left * off)
		power = c.holing_power(guess)
		if power > 0.0:
			print("PROMO putt: aim %.2f m, power %.3f" % [off, power])
			break
	if power < 0.0:
		print("PROMO putt: no holing line")
		power = guess
	await c.settle()
	await c.take()
	await c.seconds(float(c.arg("read", "2.5")))
	g.play_shot(power, 0.0)
	await c.seconds(float(c.arg("secs", "6")))
