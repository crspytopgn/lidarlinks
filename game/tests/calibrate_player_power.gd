extends SceneTree
## Measures PlayerPower.STANDARD_SPEED: for each hitting distance profile
## and club, the share of the club's ball speed whose full swing goes the
## profile's total on flat fairway with the stand-in physics. Run it after
## changing PlayerPower.TOTAL_YD or the stand-in physics, and paste the
## printed table into player_power.gd:
##   godot --headless --path game -s res://tests/calibrate_player_power.gd


func _init() -> void:
	var fairway := FlatTerrain.new(Surface.Type.FAIRWAY)
	for profile: int in PlayerPower.TOTAL_YD:
		var out := PackedStringArray()
		for c in Club.standard_set():
			if c.is_putter:
				continue
			var want := PlayerPower.total_m(profile, c)
			# Distance isn't always rising with speed (the bounce), so this
			# scans rather than halves.
			var best := 1.0
			var best_miss := INF
			for k in range(500, 1601):
				var b := Swing.launch_from_swing(c, 1.0, 0.0, 0.0, Surface.Type.FAIRWAY)
				b.velocity *= k * 0.001
				var miss := absf(BallPhysics.simulate_shot(b, fairway).total_m - want)
				if miss < best_miss:
					best_miss = miss
					best = k * 0.001
			out.append("%.3f" % best)
		print("\tProfile.%s: [%s]," % [PlayerPower.Profile.keys()[profile], ", ".join(out)])
	quit()
