class_name CaddieAdvice
extends RefCounted
## The caddie's read of one shot (Settings > Caddie): the yardage, what it
## plays like, the club and, on the green, the break and pace. The plan
## behind it is the tour-level computer golfer's (ComputerGolfer), run
## through the round's own physics, wind and course, so the caddie never
## knows less than the game does. How much of that it says follows the
## swing skill setting (detail_for_skill): the easier levels hear the line
## and the break to the inch, Links 2003's hardest only the numbers a real
## caddie reads off the yardage book, so the caddie doesn't make the hard
## levels easier than the original.
##
## Planning runs in small steps (step) so the browser build never stalls.

enum Detail { FULL, STANDARD, SPARSE }

const YARDS_PER_METRE := 1.0936133
const FEET_PER_METRE := 3.2808399
const MPS_PER_MPH := 0.44704
const PLANNER_SEED := 2003
const TAP_IN_M := 0.9  ## "knock it in"

var detail: int = Detail.FULL
## What the caddie says, once is_ready().
var text := ""
## The plan, once is_ready(): the club, power and line it would play.
## `power` is the shot model's (a share of the club's full swing, a chip's
## own units, a share of the full putt meter); `meter` is what the player's
## meter reads for it, the number the caddie says.
var club_index := 0
var power := 1.0
var meter := 1.0
var aim_deg := 0.0

var _cpu: ComputerGolfer
var _clubs: Array[Club] = []
var _hole: HoleData
var _from := Vector3.ZERO
var _lie: int = Surface.Type.FAIRWAY
var _wind := Vector3.ZERO
var _model: ShotModel
var _ready := false
var _chip := false
var _putt_meter := PuttMeterScale.bare()


## Skill levels 0 and 1 hear everything, 2 the side to favour and the size
## of the break in words, 3 (Links 2003's hardest) the numbers only.
static func detail_for_skill(skill: int) -> int:
	const BY_SKILL := [Detail.FULL, Detail.FULL, Detail.STANDARD, Detail.SPARSE]
	return BY_SKILL[clampi(skill, 0, BY_SKILL.size() - 1)]


## Starts reading a shot from `from` on `lie`, with `wind` the wind's
## velocity for this shot. `putt_meter` is the putting meter in use
## (Quick pace's fixed meters read in feet), null for the bare meter.
func start(model: ShotModel, clubs: Array[Club], hole: HoleData, from: Vector3, lie: int, wind: Vector3, skill: int, putt_meter: PuttMeterScale = null) -> void:
	detail = detail_for_skill(skill)
	_model = model
	_clubs = clubs
	_hole = hole
	_from = from
	_lie = lie
	_wind = wind
	_ready = false
	_chip = ComputerGolfer.is_chip(from, hole.pin, lie)
	_putt_meter = putt_meter if putt_meter != null else PuttMeterScale.bare()
	text = ""
	if _flat(from, hole.pin) < TAP_IN_M and _is_putting_lie(lie, _flat(from, hole.pin)):
		club_index = clubs.size() - 1
		_ready = true
		text = "That's a tap-in. Knock it in."
		return
	_cpu = ComputerGolfer.new(OpponentSkill.Level.TOUR, PLANNER_SEED, TourPro.new())  # a neutral golfer: no shape or bias
	# A person's chip can't go past the chip meter's top.
	_cpu.chip_top = chip_top()
	_cpu.plan(model, clubs, hole, from, lie, wind)


## Plans for about `budget_ms`; true once the advice is ready.
func step(budget_ms := 4.0) -> bool:
	if _ready:
		return true
	if _cpu == null or not _cpu.step(budget_ms):
		return false
	club_index = _cpu.club_index
	power = _cpu.power
	aim_deg = _cpu.aim_deg
	_cpu = null
	_ready = true
	text = _compose()
	meter = meter_value(power, _clubs[club_index].is_putter, _chip, _putt_meter)
	return true


## Like step(), but where the game has threads the whole plan runs on a
## worker thread instead (ComputerGolfer.step_background, on a model of its
## own): each club it tries is a full flight and roll, 50 ms and more on a
## fast desktop, so even step()'s budget let whole frames stall while
## aiming. True once the advice is ready.
func step_background(budget_ms := 4.0) -> bool:
	if _ready:
		return true
	if _cpu == null or not _cpu.step_background(budget_ms):
		return false
	return step(budget_ms)


## Waits for every read still running on a worker thread (BackgroundWork).
static func wait_all() -> void:
	BackgroundWork.wait_all()


## Plans to the end, waiting for the worker thread if step_background()
## started one, so the plan is never stepped from two threads at once.
func finish() -> void:
	if _ready or _cpu == null:
		return
	_cpu.finish()
	step(1e9)


func is_ready() -> bool:
	return _ready


func _compose() -> String:
	var club := _clubs[club_index]
	var dist := _flat(_from, _hole.pin)
	var heading := rad_to_deg(atan2(_hole.pin.x - _from.x, _hole.pin.z - _from.z))
	var aim_off := dist * tan(deg_to_rad(clampf(wrapf(aim_deg - heading, -180.0, 180.0), -60.0, 60.0)))
	if club.is_putter:
		return putt_text(detail, dist, _hole.pin.y - _from.y, aim_off, meter_value(power, true, false, _putt_meter))
	var dir := Vector3(sin(deg_to_rad(heading)), 0.0, cos(deg_to_rad(heading)))
	var left := Vector3.UP.cross(dir)
	var reach := _reach(club)
	# With the pin in range and a club whose full swing fits what the shot
	# plays like, a caddie names that club rather than the planner's soft
	# long one; otherwise the planner's club and power stand, as they were
	# worked out through the physics. Reaches are the ones the game shows
	# (the shot model's club rating and lie power): a full pitching wedge
	# was offered for 110 yards when it flies 138.
	var plays := plays_like_m(dist, _hole.pin.y - _from.y, _wind.dot(dir))
	var full := club_for(_clubs, plays, _lie, _model)
	if not _chip and full >= 0 and _reach(_clubs[full]) <= plays * FULL_FIT and dist <= _reach(_clubs[0]):
		club_index = full
		club = _clubs[full]
		power = 1.0
		reach = _reach(club)
	return shot_text(detail, {
		"to_pin_m": dist, "rise_m": _hole.pin.y - _from.y,
		"wind_along_mps": _wind.dot(dir), "wind_cross_mps": _wind.dot(left),
		"club": club.full_name, "power": meter_value(power, false, _chip, _putt_meter), "aim_off_m": aim_off,
		"in_range": dist <= reach * 1.08, "lie": _lie, "par": _hole.par,
		"lie_power": _model.lie_power(_lie, club) if _model != null else Surface.lie_power(_lie), "reach_m": reach,
		"tee": _lie == Surface.Type.TEE,
	})


## The chip meter's top, in the shot model's power (LinksPowerStroke.chip_power
## at the meter's last position, / 100): about 0.35.
static func chip_top() -> float:
	return LinksPowerStroke.chip_power(LinksPowerStroke.LAST) / 100.0


## What the player's meter reads for `p`, the shot model's power: the
## same for a full swing; a chip's power comes from the chip meter's own
## table (LinksPowerStroke.chip_power, 0.07 at the snap line to about 0.35
## at the top), so 0.2 is about half the chip meter; a putt reads on
## `putt_meter` (Quick pace's fixed meters are in feet). A caddie that said
## the model's number sent chips and Quick pace putts well short.
static func meter_value(p: float, putter: bool, chip: bool, putt_meter: PuttMeterScale = null) -> float:
	if putter:
		return putt_meter.value_for_power(p) if putt_meter != null else clampf(p, 0.0, 1.0)
	if not chip:
		return p
	var span := LinksPowerStroke.LAST - LinksPowerStroke.SNAP
	var best := LinksPowerStroke.SNAP
	var gap := INF
	for pos in range(LinksPowerStroke.SNAP, LinksPowerStroke.LAST + 1):
		var d := absf(LinksPowerStroke.chip_power(pos) / 100.0 - p)
		if d < gap:
			gap = d
			best = pos
	return float(best - LinksPowerStroke.SNAP) / float(span)


## A full swing suits the shot when the club goes no further than this
## share past what it plays like.
const FULL_FIT := 1.05


## The shortest club whose full swing from `lie` reaches `plays_m`, or -1;
## with `model`, by the reach the game shows for it.
static func club_for(clubs: Array[Club], plays_m: float, lie: int, model: ShotModel = null) -> int:
	var best := -1
	for i in clubs.size():
		if not clubs[i].is_putter and _reach_of(clubs[i], lie, model) >= plays_m:
			best = i
	return best


static func _reach_of(club: Club, lie: int, model: ShotModel) -> float:
	if model == null:
		return club.total_m * Surface.lie_power(lie)
	return club.total_m * model.reach_scale(club) * model.lie_power(lie, club)


func _reach(club: Club) -> float:
	return _reach_of(club, _lie, _model)


## What a shot of `distance_m` plays like, with the pin `rise_m` above the
## ball and `wind_along_mps` of wind down the line (negative: into the
## face). The caddie's rules of thumb: a yard per yard of rise, one per cent
## per mph into the wind and half that helping.
static func plays_like_m(distance_m: float, rise_m: float, wind_along_mps: float) -> float:
	var mph := wind_along_mps / MPS_PER_MPH
	var factor := -0.005 * mph if mph > 0.0 else -0.01 * mph
	return distance_m * (1.0 + factor) + rise_m


## A full shot's advice. `info` keys: to_pin_m, rise_m, wind_along_mps,
## wind_cross_mps (+ blows towards the golfer's left), club (its name),
## power (0..1), aim_off_m (+ left of the pin), in_range (the pin is within
## the club's reach), lie (Surface.Type), par, tee.
static func shot_text(level: int, info: Dictionary) -> String:
	var parts := PackedStringArray()
	var yards := Units.long_value(float(info.to_pin_m))
	var first := "%d to the pin" % yards
	if bool(info.in_range):
		var plays := Units.long_value(plays_like_m(info.to_pin_m, info.rise_m, info.wind_along_mps))
		if absi(plays - yards) >= 3:
			first += ", playing %d %s" % [plays, _why(info)]
	elif bool(info.get("tee", false)) and int(info.get("par", 0)) >= 4:
		first += ", par %d" % int(info.par)
	parts.append(first + ".")
	var lie_words := lie_text(info)
	if not lie_words.is_empty():
		parts.append(lie_words)
	parts.append(_club_words(str(info.club), float(info.power)) + ".")
	if level == Detail.SPARSE:
		return " ".join(parts)
	var off_yd := float(info.aim_off_m) * YARDS_PER_METRE
	var cross_mph := absf(float(info.wind_cross_mps)) / MPS_PER_MPH
	var for_wind := " for the wind" if cross_mph >= 4.0 else ""
	if absf(off_yd) >= 2.0:
		var side := "left" if off_yd > 0.0 else "right"
		if level == Detail.FULL:
			parts.append("Start it %s %s%s." % [Units.long_words(absf(float(info.aim_off_m))), side, for_wind])
		else:
			parts.append("Favour the %s side%s." % [side, for_wind])
	elif bool(info.in_range) and level == Detail.FULL:
		parts.append("Straight at the flag.")
	return " ".join(parts)


## A putt's advice: `distance_m` to the hole, the hole `rise_m` above the
## ball, and `aim_off_m` how far left (+) or right of the hole to start it.
static func putt_text(level: int, distance_m: float, rise_m: float, aim_off_m: float, power := -1.0) -> String:
	if distance_m < TAP_IN_M:
		return "That's a tap-in. Knock it in."
	var parts := PackedStringArray()
	var pct := rise_m / maxf(distance_m, 0.1) * 100.0
	var slope := "fairly flat"
	if pct >= 2.0:
		slope = "uphill"
	elif pct >= 0.5:
		slope = "slightly uphill"
	elif pct <= -2.0:
		slope = "downhill"
	elif pct <= -0.5:
		slope = "slightly downhill"
	var how_far := ("%d feet" % roundi(distance_m * FEET_PER_METRE)) if not Units.metric else (("%.1f metres" % distance_m) if distance_m < 10.0 else ("%d metres" % roundi(distance_m)))
	parts.append("%s, %s." % [how_far, slope])
	var inches := absf(aim_off_m) * 39.3701
	# Starting it left of the hole means it breaks back to the right.
	var way := "left to right" if aim_off_m > 0.0 else "right to left"
	match level:
		Detail.FULL:
			if inches < 2.0:
				parts.append("Inside the hole, it's straight.")
			else:
				parts.append("Breaks %s, start it %s of the hole." % [way, PuttRead.aim_text(aim_off_m)])
		Detail.STANDARD:
			if inches < 2.0:
				parts.append("Looks straight.")
			else:
				var size := "a touch"
				if inches >= 18.0:
					size = "a lot"
				elif inches >= 6.0:
					size = "a fair bit"
				parts.append("Breaks %s %s." % [size, way])
		_:
			parts.append("Looks straight." if inches < 4.0 else "Breaks %s." % way)
	if level != Detail.SPARSE:
		if pct >= 1.5:
			parts.append("Be firm with it.")
		elif pct <= -1.5:
			parts.append("Just get it rolling.")
	if power > 0.0:
		parts.append("Hit it %s." % power_words(power))
	return " ".join(parts)


## What the lie does to the shot: how much of a full swing's distance it
## takes off (the shot model's lie power, which the game's flight uses) and
## how far the club then goes from here. Empty from a clean lie. `info`
## keys as shot_text, plus lie_power (0..1), reach_m (the club's full swing
## from this lie) and club.
static func lie_text(info: Dictionary) -> String:
	var lie: int = info.get("lie", Surface.Type.FAIRWAY)
	var p := float(info.get("lie_power", 1.0))
	var lost := roundi((1.0 - p) * 100.0)
	if lost < 1:
		return ""
	var where := "From here"
	if lie == Surface.Type.SAND:
		where = "Out of the sand"
	elif lie == Surface.Type.DEEP_ROUGH:
		where = "From the deep rough"
	elif lie == Surface.Type.ROUGH:
		where = "From the rough"
	var words := "%s you lose about %d%%" % [where, lost]
	if info.has("reach_m"):
		words += ", so a full %s goes %d" % [str(info.club).to_lower(), Units.long_value(float(info.reach_m))]
	return words + "."


## Why it plays longer or shorter: the bigger of the slope and the wind.
static func _why(info: Dictionary) -> String:
	var rise_yd := float(info.rise_m) * YARDS_PER_METRE
	var dist := float(info.to_pin_m)
	var wind_yd := (plays_like_m(dist, 0.0, info.wind_along_mps) - dist) * YARDS_PER_METRE
	if absf(rise_yd) >= absf(wind_yd):
		return "uphill" if rise_yd > 0.0 else "downhill"
	return "into the wind" if wind_yd > 0.0 else "downwind"


## The club and how hard to hit it, as the power the meter reads.
static func _club_words(club_name: String, p: float) -> String:
	if p >= 0.97:
		return club_name + ", full swing"
	return "%s, %s" % [club_name, power_words(p)]


## The power to swing at, as the meter's percentage reads it.
static func power_words(p: float) -> String:
	return "about %d%% power" % roundi(clampf(p, 0.0, 1.0) * 100.0)


static func _is_putting_lie(lie: int, to_pin: float) -> bool:
	return lie == Surface.Type.GREEN or (lie == Surface.Type.FRINGE and to_pin < 15.0)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
