extends RefCounted
## An approach from `m` metres that finishes near the pin. Args: hole, m,
## hud, secs.
const Common := preload("common.gd")


func run(c) -> void:
	await Common.open_hole(c)
	var g: GolfRound = c.game
	c.ball_from_pin(float(c.arg("m", "120")))
	await c.frames(5)
	# The club and power (the auto club and one either side) that finish
	# nearest the pin.
	var best := 1.0
	var best_club := g.club_index
	var best_d := INF
	var auto := g.club_index
	for ci in range(maxi(auto - 1, 0), mini(auto + 2, g.clubs.size())):
		if g.clubs[ci].is_putter:
			continue
		g.club_index = ci
		for i in 41:
			var p := 0.6 + i * 0.01
			var r: ShotResult = c.predict(p)
			var dd := Vector2(r.rest.x - g.hole.pin.x, r.rest.z - g.hole.pin.z).length()
			if r.outcome == ShotResult.Outcome.HOLED:
				dd = 0.5  # nice, but rarer than close
			if dd < best_d:
				best_d = dd
				best = p
				best_club = ci
	g.club_index = best_club
	print("PROMO approach: club %s, power %.2f, %.1f m from the pin" % [g.clubs[g.club_index].short_name, best, best_d])
	await c.settle()
	await c.take()
	await c.seconds(float(c.arg("lead", "1.5")))
	g.play_shot(best, 0.0)
	await c.seconds(float(c.arg("secs", "9")))
