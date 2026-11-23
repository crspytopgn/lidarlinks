class_name PuttMeterScale
extends RefCounted
## The Broadcast and Tour putting meter in Quick pace: a few FIXED meters,
## each a ruler in feet on a level green, so the same stroke always rolls
## the same distance and the player can learn them.
##
## It used to size the meter to each putt (four sizes picked from the
## hole's distance, with power growing as the square of the stroke), so a
## stroke to the same point of the bar rolled a different distance from
## one putt to the next. Now there are three meters with fixed tops (15 ft,
## 40 ft and the putter's full stroke), picked by the hole's distance, and
## along each one the distance grows evenly: halfway up the 15 ft meter is
## 7.5 ft on the level, every time, on every course and green speed. The
## stroke itself still goes through the round's own physics (slope, green
## speed, the putt miss); only the meter's reading of power is ours, as the
## original's own scale from meter to power is not known (putting-decode).
##
## Classic Links, the Classic pace and the mouse swing keep the bare meter:
## power along the bar as the full putt meter has it (`top_ft` 0).

## The fixed meters' tops in feet on the level, shortest first; the last
## meter is the putter's full stroke.
const METERS_FT: Array[float] = [15.0, 40.0]
## A meter is used for holes up to its top over this, leaving room for an
## uphill putt: the 15 ft meter to 9 feet, the 40 ft one to 25 feet.
const ROOM := 1.6

## Feet a putt rolls on the level at shares 0, 1/20 ... 1 of the full putt
## meter's power (GolfRound.putt_roll_feet; share 0 is sampled at 0.02).
var full := PackedFloat32Array()
## This meter's top in feet on the level; 0 for the bare meter.
var top_ft := 0.0


static func bare() -> PuttMeterScale:
	return PuttMeterScale.new()


## The fixed meter for a hole `hole_ft` away, from the full scale.
static func for_hole(full_feet: PackedFloat32Array, hole_ft: float) -> PuttMeterScale:
	var s := PuttMeterScale.new()
	s.full = full_feet
	s.top_ft = top_for(full_feet, hole_ft)
	return s


## The top in feet of the meter used for a hole `hole_ft` away.
static func top_for(full_feet: PackedFloat32Array, hole_ft: float) -> float:
	if full_feet.size() < 2:
		return 0.0
	var longest := full_feet[full_feet.size() - 1]
	for t in METERS_FT:
		if t < longest and hole_ft * ROOM <= t:
			return t
	return longest


func is_bare() -> bool:
	return top_ft <= 0.0 or full.size() < 2


## The meter's short name for the bar ("15 FT"), empty for the bare meter.
func label() -> String:
	return "" if is_bare() else "%d FT" % roundi(top_ft)


## The share of the full putt meter's power that meter value `v` (0 at the
## snap line, 1 at the top) strikes the ball with.
func power_for_value(v: float) -> float:
	if is_bare():
		return v
	return power_for_feet(clampf(v, 0.0, 1.0) * top_ft)


## The meter value that strikes with share `p` of the full meter's power.
func value_for_power(p: float) -> float:
	if is_bare():
		return clampf(p, 0.0, 1.0)
	return clampf(feet_for_power(p) / top_ft, 0.0, 1.0)


## Feet on the level for meter values 0, 1/20 ... 1, for SwingMeter's
## scale: evenly spaced on a fixed meter.
func feet_scale() -> PackedFloat32Array:
	if is_bare():
		return full
	var out := PackedFloat32Array()
	for i in 21:
		out.append(top_ft * i / 20.0)
	return out


func _share(i: int) -> float:
	return maxf(float(i) / float(full.size() - 1), 0.02)


## The share of full power that rolls `ft` on the level (from the full
## scale, read between its samples: the roll is smooth in the stroke).
func power_for_feet(ft: float) -> float:
	if ft <= 0.0:
		return 0.0
	if ft <= full[0]:
		# Below the first sample the roll goes about as the stroke squared.
		return _share(0) * sqrt(ft / maxf(full[0], 1e-6))
	for i in range(1, full.size()):
		if full[i] >= ft:
			var a := full[i - 1]
			var t := 0.0 if full[i] <= a else (ft - a) / (full[i] - a)
			return lerpf(_share(i - 1), _share(i), t)
	return 1.0


## Feet on the level for share `p` of full power.
func feet_for_power(p: float) -> float:
	if p <= _share(0):
		return full[0] * pow(maxf(p, 0.0) / _share(0), 2.0)
	for i in range(1, full.size()):
		if p <= _share(i):
			return lerpf(full[i - 1], full[i], (p - _share(i - 1)) / (_share(i) - _share(i - 1)))
	return full[full.size() - 1]
