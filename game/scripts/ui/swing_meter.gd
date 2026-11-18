class_name SwingMeter
extends Control
## The classic three-click power meter. In the Broadcast presentation it is
## a slim modern bar on a glass panel (Glass: blurred where it can be). In Classic it is drawn as an
## arc in the style of Links or, with the player's own interface art
## (HudArt), as the original's chrome bar. On the bars power runs right
## from the snap line and accuracy left of it.
##
## Click 1 starts the backswing: the marker climbs from the snap line
## towards 100% and on into the overswing. Click 2 sets the power; the
## marker comes back down past the snap line into the accuracy zone. Click 3
## sets accuracy: on the snap line is straight, early (above it) pulls and
## hooks, late (past it) pushes and slices. The marker moves as Links 2003's
## does (LinksPowerStroke): one of the game's 69 positions at a time, at the
## game's speeds, with the snap line 15 positions up. Chips and putts have
## their own meters, set with `mode` before the first click. The marker is
## drawn gliding between the game's positions (Run.smooth_value) so it moves
## smoothly every frame; the clicks still land on the game's own positions.
##
## Putts get their own look: a PUTT stroke scale with fine ticks every 5
## percent of the backstroke (labelled at 25, 50 and 75) instead of the
## full swing's quarter marks, a cooler fill, and a putt's miss named as a
## pull or a push, which is all a PowerStroke miss does to a putt (the face
## turns, docs/formats/physics.md).

signal backswing_started
signal swing_finished(power: float, accuracy: float)

enum Phase { IDLE, BACKSWING, DOWNSWING, DONE }

const ACCURACY_ZONE := 0.06  ## the highlighted band either side of the snap line
const RADIUS := 82.0
const WIDTH := 16.0

## Bar layout with the original art: the art is drawn at this scale.
const ART_SCALE := 1.2
const BAR_LENGTH := 330.0

## The modern bar: panel size, and the track's inset from the panel's sides.
const MODERN_SIZE := Vector2(480, 78)
const MODERN_INSET := 28.0
const MODERN_RADIUS := 20
const TRACK := Color(1, 1, 1, 0.16)
const SWING := Color(1, 1, 1, 0.92)
const GOLD := Color(0.98, 0.76, 0.28)
const GOOD := Color(0.45, 0.9, 0.55)
## Settings > Colour-blind safe: blue instead of green and white instead of
## red, so the meter reads the same with red-green colour blindness.
static var colour_safe := false


static func good() -> Color:
	return Color(0.4, 0.7, 1.0) if colour_safe else GOOD


static func _fill() -> Color:
	return Color(0.3, 0.55, 1.0) if colour_safe else Color(0.3, 0.8, 0.35)


## The putting meter's backstroke fill.
const PUTT_FILL := Color(0.62, 0.92, 0.84, 0.92)


static func _marker() -> Color:
	return Color(1, 1, 1) if colour_safe else Color(0.9, 0.1, 0.1)

var phase: Phase = Phase.IDLE
var value := 0.0  ## marker position: 0 = snap line, 1 = full power
var power := 0.0
var accuracy := 0.0
## The meter for the next swing (LinksPowerStroke.Mode).
var mode := LinksPowerStroke.Mode.FULL:
	set(v):
		if v != mode:
			mode = v
			queue_redraw()
## Where the marker is drawn: `value`, gliding between the game's positions.
var shown := 0.0
## Where the power click landed, in the game's positions (for chips, whose
## power comes from their own table: LinksPowerStroke.chip_power).
var power_position := 0
var run: LinksPowerStroke.Run = null
## The player's interface art; null draws the plain arc.
var art: HudArt
## Draws the modern bar (Broadcast presentation) whatever the art.
var modern := false
## Links 2003's Amateur Putting Assistant: a red dot on the meter at the
## power the putt wants (a meter value, as `power`); below 0 there is none.
var target := -1.0:
	set(v):
		target = v
		queue_redraw()
const TARGET := Color(0.95, 0.12, 0.1)
## The putting meter's distance scale: feet a putt rolls on a level green
## at meter values 0, 1/20 ... 1 (GolfRound.putt_roll_feet), empty for none,
## and the hole's distance in feet (below 0 for none).
var putt_feet := PackedFloat32Array()
var hole_feet := -1.0
## Quick pace for chips and putts (LinksPowerStroke.Run.quick); false is
## Classic, the original's timing.
var quick := true
## A full swing's or chip's distance scale: the carry in yards, on the flat
## with no wind, at meter values `yard_at` (rising, from above 0),
## empty for none (GolfRound.carry_yards). The Broadcast and Tour bars
## label their quarter marks with it and read the swing in yards.
var yard_at := PackedFloat32Array()
var yards := PackedFloat32Array()


func set_yard_scale(at: PackedFloat32Array, yd: PackedFloat32Array) -> void:
	if at == yard_at and yd == yards:
		return
	yard_at = at
	yards = yd
	queue_redraw()


## Carry yards for meter value `v` by the scale (0 at the snap line and
## below), or -1 with no scale.
func yards_for_value(v: float) -> float:
	if yards.is_empty() or yards.size() != yard_at.size():
		return -1.0
	var a := 0.0
	var ya := 0.0
	for i in yards.size():
		if v <= yard_at[i]:
			var t := 0.0 if yard_at[i] <= a else (v - a) / (yard_at[i] - a)
			return lerpf(ya, yards[i], clampf(t, 0.0, 1.0))
		a = yard_at[i]
		ya = yards[i]
	return yards[yards.size() - 1]


func _reads_yards() -> bool:
	return not putting() and not yards.is_empty() and yards.size() == yard_at.size()


func set_putt_scale(feet: PackedFloat32Array, hole_ft: float) -> void:
	if feet == putt_feet and is_equal_approx(hole_ft, hole_feet):
		return
	putt_feet = feet
	hole_feet = hole_ft
	queue_redraw()


## The meter value that rolls `feet` on the level (by the scale), or -1
## past its ends.
func value_for_feet(feet: float) -> float:
	for i in range(1, putt_feet.size()):
		if putt_feet[i] >= feet:
			var a := putt_feet[i - 1]
			var t := 0.0 if putt_feet[i] <= a else (feet - a) / (putt_feet[i] - a)
			return (i - 1 + clampf(t, 0.0, 1.0)) / float(putt_feet.size() - 1)
	return -1.0


## Feet on the level for meter value `v`, by the scale.
func feet_for_value(v: float) -> float:
	if putt_feet.size() < 2:
		return 0.0
	var x := clampf(v, 0.0, 1.0) * (putt_feet.size() - 1)
	var i := mini(int(x), putt_feet.size() - 2)
	return lerpf(putt_feet[i], putt_feet[i + 1], x - i)

## The blurred picture behind the modern bar (FrostedGlass), and its panel
## style, rebuilt when the blur is turned on or off.
var _glass: FrostedGlass
var _panel: StyleBoxFlat
var _panel_blurs := false


func _ready() -> void:
	custom_minimum_size = Vector2(220, 220)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass = FrostedGlass.new()
	add_child(_glass)


## Size the meter needs: the arc, or the bar with the original art.
func wanted_size() -> Vector2:
	if modern:
		return MODERN_SIZE
	if art == null:
		return Vector2(220, 220)
	return Vector2(HudArt.METER_CAP.size.x * ART_SCALE + BAR_LENGTH + 8.0, HudArt.METER_CAP.size.y * ART_SCALE)


func reset() -> void:
	phase = Phase.IDLE
	run = null
	power_position = 0
	value = 0.0
	shown = 0.0
	power = 0.0
	accuracy = 0.0
	queue_redraw()


func is_swinging() -> bool:
	return phase == Phase.BACKSWING or phase == Phase.DOWNSWING


## Advances the meter by one click.
func click() -> void:
	match phase:
		Phase.IDLE, Phase.DONE:
			phase = Phase.BACKSWING
			run = LinksPowerStroke.Run.new(mode, quick)
			value = run.value()
			shown = run.smooth_value()
			power = 0.0
			power_position = 0
			accuracy = 0.0
			backswing_started.emit()
		Phase.BACKSWING:
			run.click_power()
			_follow()
		Phase.DOWNSWING:
			run.click_snap()
			_follow()
	queue_redraw()


func _process(delta: float) -> void:
	if phase == Phase.BACKSWING or phase == Phase.DOWNSWING:
		run.advance(delta)
		_follow()
		queue_redraw()


## Takes the meter's state from the run.
func _follow() -> void:
	value = run.value()
	shown = run.smooth_value()
	if run.power_pos != 0 and power_position == 0:
		power_position = run.power_pos
		power = run.value_of(run.power_pos)
		if mode == LinksPowerStroke.Mode.FULL:
			power = LinksPowerStroke.full_power(run.power_pos)
		power = maxf(power, 0.02)
		phase = Phase.DOWNSWING
	if run.done and phase != Phase.DONE:
		if run.snap_pos >= 0:
			value = run.value_of(run.snap_pos)
			shown = value
		accuracy = run.accuracy()
		phase = Phase.DONE
		swing_finished.emit(power, accuracy)


func putting() -> bool:
	return mode == LinksPowerStroke.Mode.PUTT or mode == LinksPowerStroke.Mode.SHORT_PUTT


## The scale's marks, as meter values: quarters for a full swing or chip,
## every 5 percent of the stroke for a putt.
func marks() -> Array[float]:
	var out: Array[float] = []
	var n := 20 if putting() else 4
	for i in range(1, n + 1):
		out.append(float(i) / n)
	return out


## A mark the scale makes bigger (and, on a putt, labels).
static func major(v: float) -> bool:
	return absf(v * 4.0 - roundf(v * 4.0)) < 1e-3


func title() -> String:
	return "PUTT" if putting() else "POWER"


## The result of the snap, in the meter's words: a putt only pulls or
## pushes (the face turns); a full swing or chip hooks or slices.
func miss_text() -> String:
	var pct := roundi(absf(accuracy) * 100.0)
	if accuracy == 0.0:
		return "SQUARE" if putting() else "PERFECT"
	if putting():
		return ("PULL %d%%" if accuracy < 0.0 else "PUSH %d%%") % pct
	return ("HOOK %d%%" if accuracy < 0.0 else "SLICE %d%%") % pct


## The meter's span below the snap line and above it, in meter values: the
## game's positions 0 to 67 (68 for chips and putts).
func _low() -> float:
	var full := LinksPowerStroke.FULL_POWER if mode == LinksPowerStroke.Mode.FULL else LinksPowerStroke.LAST
	return float(LinksPowerStroke.SNAP) / float(full - LinksPowerStroke.SNAP)


func _high() -> float:
	if mode == LinksPowerStroke.Mode.FULL:
		return float(LinksPowerStroke.TOP - LinksPowerStroke.SNAP) / float(LinksPowerStroke.FULL_POWER - LinksPowerStroke.SNAP)
	return 1.0


## Screen angle of a meter value: 0 at the bottom, 1 at the top, running up
## the left side.
static func _angle(v: float) -> float:
	return PI * 0.5 + v * PI


func _arc(from: float, to: float, color: Color, width: float) -> void:
	var a := _angle(minf(from, to))
	var b := _angle(maxf(from, to))
	var points := maxi(4, int((b - a) * 24.0))
	draw_arc(size * 0.5, RADIUS, a, b, points, color, width, true)


func _tick(v: float, color: Color, inner: float, outer: float, width: float) -> void:
	var dir := Vector2.from_angle(_angle(v))
	var c := size * 0.5
	draw_line(c + dir * (RADIUS - inner), c + dir * (RADIUS + outer), color, width, true)


## Lists the glass behind the modern bar (none behind the classic ones).
func update_glass() -> void:
	_glass.begin()
	if modern:
		_glass.add(Rect2(Vector2.ZERO, size), 1.0, Vector4.ONE * MODERN_RADIUS)
	_glass.commit()


func _draw() -> void:
	update_glass()
	if modern:
		_draw_modern()
		return
	if art != null:
		_draw_bar()
		return
	_arc(-_low(), _high(), Color(0, 0, 0, 0.55), WIDTH + 6.0)
	_arc(-ACCURACY_ZONE, ACCURACY_ZONE, Color(0.95, 0.85, 0.3, 0.9), WIDTH)
	_arc(ACCURACY_ZONE, _high(), Color(0.85, 0.85, 0.85, 0.35), WIDTH)
	match phase:
		Phase.BACKSWING:
			_arc(0.0, shown, PUTT_FILL if putting() else _fill(), WIDTH)
		Phase.DOWNSWING, Phase.DONE:
			_arc(0.0, power, Color(0.95, 0.55, 0.2), WIDTH)
	for m in marks():
		if major(m):
			_tick(m, Color(1, 1, 1, 0.7), WIDTH * 0.5, 4.0, 1.5)
		else:
			_tick(m, Color(1, 1, 1, 0.45), WIDTH * 0.5, 0.0, 1.0)
	_tick(0.0, Color.WHITE, WIDTH * 0.5 + 4.0, 8.0, 3.0)
	if target >= 0.0:
		draw_circle(size * 0.5 + Vector2.from_angle(_angle(target)) * (RADIUS + WIDTH * 0.5 + 8.0), 5.0, TARGET)
	if phase != Phase.IDLE:
		_tick(shown, _marker(), WIDTH * 0.5 + 2.0, 10.0, 4.0)

	var font := ThemeDB.fallback_font
	var c := size * 0.5
	var text := title()
	if phase == Phase.DOWNSWING or phase == Phase.DONE:
		text = "%d%%" % roundi(power * 100.0)
	draw_string(font, c + Vector2(-40, 6), text, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 18)
	if phase == Phase.DONE:
		var label := miss_text().capitalize()
		draw_string(font, c + Vector2(-50, 28), label, HORIZONTAL_ALIGNMENT_CENTER, 100.0, 14)


# --- The original's bar ----------------------------------------------------------

## Screen x of a meter value along the bar.
func _bar_x(v: float) -> float:
	var left := HudArt.METER_CAP.size.x * ART_SCALE - 4.0
	return left + (v + _low()) / (_high() + _low()) * BAR_LENGTH


func _draw_bar() -> void:
	var s := ART_SCALE
	var cap := HudArt.METER_CAP
	var bar := HudArt.METER_BAR
	var bar_top := (bar.position.y - cap.position.y) * s
	var bar_h := bar.size.y * s
	var left := cap.size.x * s - 2.0
	var right := _bar_x(_high()) + 4.0
	draw_texture_rect_region(art.meter, Rect2(left, bar_top, right - left, bar_h), bar)
	draw_texture_rect_region(art.meter, Rect2(Vector2.ZERO, cap.size * s), cap)
	var mid := bar_top + bar_h * 0.5
	var band := bar_h * 0.55
	# Accuracy zone, then how far the swing has gone.
	draw_rect(Rect2(_bar_x(-ACCURACY_ZONE), mid - band * 0.5, _bar_x(ACCURACY_ZONE) - _bar_x(-ACCURACY_ZONE), band), Color(1.0, 0.95, 0.5, 0.35))
	match phase:
		Phase.BACKSWING:
			_bar_fill(0.0, shown, Color(PUTT_FILL if putting() else _fill(), 0.75), mid, band)
		Phase.DOWNSWING, Phase.DONE:
			_bar_fill(0.0, power, Color(1.0, 0.6, 0.15, 0.75), mid, band)
	for m in marks():
		var x := _bar_x(m)
		var reach := 0.6 if major(m) else 0.3
		draw_line(Vector2(x, mid - bar_h * reach), Vector2(x, mid + bar_h * reach), Color(1, 1, 1, 0.8 if major(m) else 0.5), 1.5 if major(m) else 1.0)
	var snap := _bar_x(0.0)
	draw_line(Vector2(snap, mid - bar_h * 1.4), Vector2(snap, mid + bar_h * 1.4), Color.WHITE, 2.5)
	if target >= 0.0:
		draw_circle(Vector2(_bar_x(target), mid - bar_h * 1.4), 5.0, TARGET)
	if phase != Phase.IDLE:
		var x := _bar_x(shown)
		draw_line(Vector2(x, mid - bar_h * 1.1), Vector2(x, mid + bar_h * 1.1), _marker(), 4.0)

	var font := ThemeDB.fallback_font
	var text := ""
	if phase == Phase.DOWNSWING or phase == Phase.DONE:
		text = "%d%%" % roundi(power * 100.0)
	if phase == Phase.DONE:
		text += "   " + miss_text().capitalize()
	if not text.is_empty():
		draw_string_outline(font, Vector2(snap + 10.0, bar_top - 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(snap + 10.0, bar_top - 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)


func _bar_fill(from: float, to: float, color: Color, mid: float, band: float) -> void:
	var a := _bar_x(minf(from, to))
	var b := _bar_x(maxf(from, to))
	draw_rect(Rect2(a, mid - band * 0.5, b - a, band), color)


# --- The modern bar ---------------------------------------------------------------

func _modern_x(v: float) -> float:
	var w := size.x - MODERN_INSET * 2.0
	return MODERN_INSET + (v + _low()) / (_high() + _low()) * w


func _capsule(r: Rect2, color: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(minf(r.size.x, r.size.y) * 0.5))
	box.anti_aliasing = true
	draw_style_box(box, r)


func _draw_modern() -> void:
	if _panel == null or _panel_blurs != Glass.blurs():
		_panel_blurs = Glass.blurs()
		_panel = Glass.panel_style(MODERN_RADIUS, 0.0)
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	var mid := size.y * 0.62
	var h := 8.0
	var x0 := _modern_x(-_low())
	var x1 := _modern_x(_high())
	var snap := _modern_x(0.0)
	_capsule(Rect2(x0, mid - h * 0.5, x1 - x0, h), TRACK)
	# The accuracy zone: brighter, a hair taller, with a gold centre.
	var zone := Rect2(_modern_x(-ACCURACY_ZONE), mid - h * 0.75, _modern_x(ACCURACY_ZONE) - _modern_x(-ACCURACY_ZONE), h * 1.5)
	_capsule(zone, Color(1, 1, 1, 0.12))
	match phase:
		Phase.BACKSWING:
			_capsule(Rect2(snap, mid - h * 0.5, maxf(_modern_x(shown) - snap, h), h), PUTT_FILL if putting() else SWING)
		Phase.DOWNSWING, Phase.DONE:
			_capsule(Rect2(snap, mid - h * 0.5, maxf(_modern_x(power) - snap, h), h), GOLD)
	if putting() and putt_feet.size() > 1:
		_draw_feet_scale(mid, h)
	elif putting():
		# The stroke scale: a fine tick every 5 percent, 25/50/75 labelled.
		var small := GlassTheme.display_font(600)
		for m in marks():
			var x := _modern_x(m)
			var big := major(m)
			draw_line(Vector2(x, mid + h * 0.5 + 3.0), Vector2(x, mid + h * 0.5 + (9.0 if big else 6.0)), Color(1, 1, 1, 0.55 if big else 0.3), 1.0, true)
			if big and m < 0.999:
				draw_string(small, Vector2(x - 12.0, mid + h * 0.5 + 19.0), str(roundi(m * 100.0)), HORIZONTAL_ALIGNMENT_CENTER, 24.0, 11, Color(1, 1, 1, 0.45))
	else:
		var small := GlassTheme.display_font(600)
		for quarter in [0.25, 0.5, 0.75, 1.0]:
			draw_circle(Vector2(_modern_x(quarter), mid + h + 5.0), 1.6, Color(1, 1, 1, 0.45))
			if _reads_yards():
				# What each quarter of the swing carries with this club.
				draw_string(small, Vector2(_modern_x(quarter) - 14.0, mid + h + 18.0), str(roundi(yards_for_value(quarter))),
					HORIZONTAL_ALIGNMENT_CENTER, 28.0, 11, Color(1, 1, 1, 0.5))
	draw_line(Vector2(snap, mid - h * 1.6), Vector2(snap, mid + h * 1.6), Color(1, 1, 1, 0.85), 2.0, true)
	if target >= 0.0:
		draw_circle(Vector2(_modern_x(target), mid - h - 6.0), 4.5, TARGET)
	if phase != Phase.IDLE:
		var x := _modern_x(shown)
		_capsule(Rect2(x - 4.0, mid - 13.0, 8.0, 26.0), Color(1, 1, 1, 0.25))
		_capsule(Rect2(x - 2.0, mid - 11.0, 4.0, 22.0), Color.WHITE)

	var font := GlassTheme.display_font(700)
	var top := 24.0
	draw_string(font, Vector2(MODERN_INSET, top), title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.55))
	if putting() and putt_feet.size() > 1 and phase != Phase.IDLE:
		# A putt reads in feet on the level, as the scale does.
		var at := shown if phase == Phase.BACKSWING else power
		draw_string(font, Vector2(MODERN_INSET + 44.0, top), "%d FT" % roundi(feet_for_value(at)), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, GOLD if phase != Phase.BACKSWING else Color(1, 1, 1, 0.9))
	elif phase == Phase.BACKSWING:
		draw_string(font, Vector2(MODERN_INSET + 52.0, top), _reading(shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 1, 1, 0.9))
	elif phase == Phase.DOWNSWING or phase == Phase.DONE:
		draw_string(font, Vector2(MODERN_INSET + 52.0, top), _reading(value_of_power()), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, GOLD)
	if phase == Phase.DONE:
		var label := miss_text()
		var colour := good() if accuracy == 0.0 else GOLD
		draw_string(font, Vector2(0, top), label, HORIZONTAL_ALIGNMENT_RIGHT, size.x - MODERN_INSET, 19, colour)
	elif phase == Phase.IDLE and putting() and hole_feet >= 0.0:
		draw_string(font, Vector2(0, top), "HOLE %d FT" % roundi(hole_feet), HORIZONTAL_ALIGNMENT_RIGHT, size.x - MODERN_INSET, 14, Color(1, 1, 1, 0.6))
	elif phase == Phase.IDLE and _reads_yards():
		draw_string(font, Vector2(0, top), "FULL %d YD CARRY" % roundi(yards_for_value(1.0)), HORIZONTAL_ALIGNMENT_RIGHT, size.x - MODERN_INSET, 14, Color(1, 1, 1, 0.6))
	elif phase == Phase.IDLE:
		draw_string(font, Vector2(0, top), "CLICK TO PUTT" if putting() else "CLICK TO SWING", HORIZONTAL_ALIGNMENT_RIGHT, size.x - MODERN_INSET, 14, Color(1, 1, 1, 0.45))


## The meter value the power click landed on (`power` is a share of full
## power, which runs past the meter's value in the overswing).
func value_of_power() -> float:
	if run != null and run.power_pos != 0:
		return run.value_of(run.power_pos)
	return power


## The bar's live reading of the swing: the carry in yards with a scale,
## otherwise the percentage.
func _reading(v: float) -> String:
	if _reads_yards():
		# The yards, and the share of the swing the caddie talks in.
		var pct := v if phase == Phase.BACKSWING or mode != LinksPowerStroke.Mode.FULL else power
		return "%d YD   %d%%" % [roundi(yards_for_value(v)), roundi(maxf(pct, 0.0) * 100.0)]
	return "%d%%" % roundi((power if phase != Phase.BACKSWING else v) * 100.0)


## The putting meter's scale in feet on the level: ticks at round
## distances, labelled sparsely, and the hole's distance as a small flag.
func _draw_feet_scale(mid: float, h: float) -> void:
	var small := GlassTheme.display_font(600)
	var top_ft := putt_feet[putt_feet.size() - 1]
	var step := 5.0 if top_ft <= 60.0 else 10.0
	var label_every := 10.0 if top_ft <= 60.0 else 20.0
	var last_label := -100.0
	var ft := step
	while ft <= top_ft:
		var v := value_for_feet(ft)
		if v >= 0.0:
			var x := _modern_x(v)
			var big := is_zero_approx(fmod(ft, label_every))
			draw_line(Vector2(x, mid + h * 0.5 + 3.0), Vector2(x, mid + h * 0.5 + (9.0 if big else 6.0)), Color(1, 1, 1, 0.55 if big else 0.3), 1.0, true)
			if big and x - last_label > 26.0:
				draw_string(small, Vector2(x - 14.0, mid + h * 0.5 + 19.0), "%d'" % roundi(ft), HORIZONTAL_ALIGNMENT_CENTER, 28.0, 11, Color(1, 1, 1, 0.5))
				last_label = x
		ft += step
	if hole_feet >= 0.0:
		var hv := value_for_feet(hole_feet)
		if hv < 0.0:
			hv = 1.0
		var hx := _modern_x(hv)
		# A thin pin with a small flag, above the track.
		draw_line(Vector2(hx, mid - h * 0.5 - 2.0), Vector2(hx, mid - h - 10.0), Color(1, 1, 1, 0.85), 1.5, true)
		draw_colored_polygon(PackedVector2Array([Vector2(hx, mid - h - 10.0), Vector2(hx + 8.0, mid - h - 7.0), Vector2(hx, mid - h - 4.0)]), GOLD)
