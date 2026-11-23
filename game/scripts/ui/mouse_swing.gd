class_name MouseSwingControl
extends Control
## Links 2003's PowerStroke mouse swing. Hold the left button and pull the
## mouse back towards you for the backswing, then push it forward, briskly
## and straight: the club follows on the meter and strikes the ball when it
## comes back down to the ball line. LinksMouse runs the game's own frames
## (60 a second) on the mouse's movement in screen pixels, so the swing feels
## like the original: the club has momentum on full swings, the speed through
## the ball sets the power, how far back you went caps it, and moving the
## mouse sideways hooks, slices or misses. The meter is the game's size for
## this screen width, drawn the same share of the screen's height.

signal backswing_started
signal stroke_finished(stroke: LinksMouse.Stroke)
signal stroke_cancelled

const FRAME := 1.0 / 60.0
## The game's meter is about this share of the screen's height.
const METER_SHARE := 0.46
## Our multiplier on mouse movement (1 is the original's).
var sensitivity := 1.0
## A putt's power from a full mouse backswing struck at the right speed
## (LinksMouse.swing: (f + 2) f / 3 * 14.6), against the meter's full putt.
const PUTT_FULL_SHARE := 14.6 / LinksShotModel.PUTT_POWER_AT_FULL
## Links 2003's Putting Assistant (Amateur): the putt's power, as a share of
## the meter's full putt (ShotModel power), marked on the backswing so the player knows how far back
## to take the putter. Below 0: no mark.
var target := -1.0:
	set(v):
		target = v
		queue_redraw()
var club: LinksMouse.MouseClub = null
## Where on screen the meter may go (the HUD keeps it clear of its other
## pieces); empty: the right of the screen, half way down.
var area := Rect2():
	set(v):
		if v != area:
			area = v
			queue_redraw()
## While aiming with the mouse swing: the empty meter, so the player sees
## which swing is in hand before pressing the button.
var idle := false:
	set(v):
		if v != idle:
			idle = v
			queue_redraw()
## SwingGuide's demonstration club, 0 to 1 up the backswing; below 0 none.
var ghost := -1.0:
	set(v):
		if v != ghost:
			ghost = v
			queue_redraw()
var _rng := LinksLaunch.Rand.new(randi())
var _pending := Vector2.ZERO  ## mouse movement not yet given to a frame
var _clock := 0.0
var _started := false
var _result := ""
var _last := LinksMouse.Phase.BACKSWING


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func is_swinging() -> bool:
	return club != null and not club.done()


func reset() -> void:
	club = null
	_result = ""
	_pending = Vector2.ZERO
	_release_mouse()
	queue_redraw()


## The button went down: a swing with `club_number` (LinksMouse.PUTTER for
## the putter) at `skill`, a chip if `chip`. `capture` hides and holds the
## mouse pointer; a touch or thumbstick swing (AnalogSwing) leaves it alone.
func begin(club_number: int, skill: int, chip := false, capture := true) -> void:
	reset()
	var shot := LinksMouse.Shot.FULL
	if club_number >= LinksMouse.PUTTER:
		shot = LinksMouse.Shot.PUTT
	elif chip:
		shot = LinksMouse.Shot.CHIP
	var width := 1920
	if is_inside_tree() and DisplayServer.window_get_size().x > 0:
		width = DisplayServer.window_get_size().x
	club = LinksMouse.MouseClub.new(skill, shot, club_number, LinksMouse.meter_for(width))
	_started = false
	_clock = 0.0
	_last = LinksMouse.Phase.BACKSWING
	if capture and is_inside_tree() and not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_redraw()


## The mouse moved this many screen pixels (right and down) with the button held.
func motion(screen_relative: Vector2) -> void:
	if is_swinging():
		_pending += screen_relative * sensitivity


## The button came up. Before the downswing that calls the swing off; after
## it the club carries on (the game's swing ignores the button).
func release() -> void:
	if is_swinging() and club.phase == LinksMouse.Phase.BACKSWING:
		reset()
		stroke_cancelled.emit()


## Runs the game's frames for `delta` seconds of movement.
func advance(delta: float) -> void:
	if not is_swinging():
		return
	_clock += delta
	var frames := int(_clock / FRAME)
	if frames <= 0:
		return
	_clock -= frames * FRAME
	for i in frames:
		# The mouse's movement shared out over the frames, in whole pixels.
		var share := _pending / float(frames - i)
		var dx := int(share.x)
		var dy := int(share.y)
		_pending -= Vector2(dx, dy)
		club.step(dx, dy, _rng)
		if not _started and club.club_height() > club.meter.ball_line + 0.5:
			_started = true
			backswing_started.emit()
		if club.done():
			break
	queue_redraw()
	if club.phase == LinksMouse.Phase.IMPACT:
		_release_mouse()
		var m := club.stroke
		_result = _describe(m)
		stroke_finished.emit(m)
	elif club.phase == LinksMouse.Phase.FAILED:
		reset()
		stroke_cancelled.emit()


func _process(delta: float) -> void:
	advance(delta)


func _release_mouse() -> void:
	if is_inside_tree() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _describe(m: LinksMouse.Stroke) -> String:
	var x := -m.drift
	if absf(x) > 18.0:
		return "Miss!"
	if absf(x) > 10.0:
		return "Hook" if x > 0.0 else "Slice"
	return "%d%%" % roundi(m.backswing * 100.0)


## The meter height (game pixels) of the Putting Assistant's mark: where the
## backswing reads the putt's power. A full backswing gives
## PUTT_FULL_SHARE of the meter's full putt, and the putt's reading is (2 + b) b / 3 of
## the backswing b, so b = sqrt(1 + 3 p) - 1. Below 0: no mark (no putt).
func target_height() -> float:
	if club == null or target < 0.0 or club._shot != LinksMouse.Shot.PUTT:
		return -1.0
	var b := sqrt(1.0 + 3.0 * clampf(target / PUTT_FULL_SHARE, 0.0, 1.0)) - 1.0
	return club.meter.ball_line + b * (club._top - club.meter.ball_line)


## Room above the meter for its percentage, and either side of it for the
## club's sideways drift.
const LABEL_H := 30.0
const SIDE := 2.6


## The meter's rectangle on screen and its pixels per game meter pixel.
func meter_rect() -> Rect2:
	var vh := get_viewport_rect().size.y if is_inside_tree() else 600.0
	var vw := get_viewport_rect().size.x if is_inside_tree() else 800.0
	return rect_in(Vector2(vw, vh), area)


## The meter's rectangle on a `screen` this size, inside `room` (or, with
## no room given, at the right of the screen half way down).
static func rect_in(screen: Vector2, room: Rect2) -> Rect2:
	var h := screen.y * METER_SHARE
	if room.size.y <= 0.0:
		var w0 := h * 0.12
		return Rect2(screen.x - w0 - screen.x * 0.06, (screen.y - h) * 0.5, w0, h)
	h = minf(h, room.size.y - LABEL_H - 8.0)
	h = maxf(h, 60.0)
	var w := h * 0.12
	var x := room.end.x - w * SIDE
	var y := room.position.y + LABEL_H + (room.size.y - LABEL_H - h) * 0.5
	return Rect2(x, y, w, h)


## How wide a column the meter takes, drift and labels included, for a
## meter `h` pixels tall.
static func column_width(h: float) -> float:
	return h * 0.12 * (SIDE * 2.0 - 1.0) + 24.0


func _draw() -> void:
	if club == null:
		if idle:
			_draw_idle()
		return
	var r := meter_rect()
	var px := r.size.y / club.meter.height
	var y_of := func(meter_px: float) -> float: return r.end.y - meter_px * px
	draw_rect(r.grow(3), Color(0, 0, 0, 0.45))
	draw_rect(r, Color(1, 1, 1, 0.12))
	draw_rect(r, Color(1, 1, 1, 0.7), false, 2.0)
	var ball_y: float = y_of.call(club.meter.ball_line)
	var top_y: float = y_of.call(club.meter.height - 10)
	var club_y: float = y_of.call(club.club_height())
	# The backswing so far, from the ball line up to the club.
	var fill_top := minf(club_y, ball_y)
	draw_rect(Rect2(r.position.x, fill_top, r.size.x, ball_y - fill_top), Color(1.0, 0.82, 0.25, 0.55))
	draw_line(Vector2(r.position.x - 6, top_y), Vector2(r.end.x + 6, top_y), Color(1, 1, 1, 0.5), 1.5)
	draw_line(Vector2(r.position.x - 10, ball_y), Vector2(r.end.x + 10, ball_y), Color.WHITE, 3.0)
	# The club, shifted by the sideways drift (red past the hook and slice line).
	var x := -club.drift()
	var off := clampf(x / 18.0, -1.0, 1.0) * r.size.x * 1.5
	var colour := Color(1, 0.3, 0.25) if absf(x) > 10.0 else Color.WHITE
	draw_rect(Rect2(r.position.x - 4 + off, club_y - 3, r.size.x + 8, 6), colour)
	var mark := target_height()
	if mark >= 0.0:
		var my: float = y_of.call(mark)
		draw_circle(Vector2(r.position.x - 12, my), 5.0, Color(0.95, 0.15, 0.12))
		draw_line(Vector2(r.position.x - 6, my), Vector2(r.end.x, my), Color(0.95, 0.15, 0.12, 0.8), 2.0)
	var font := ThemeDB.fallback_font
	var text := _result if not _result.is_empty() else "%d%%" % roundi(club.backswing_percent())
	var at := Vector2(r.position.x - 4, r.position.y - 12)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)


## The meter before the button goes down: the track, the ball line and the
## top, fainter, and "Mouse swing" over it; SwingGuide's ghost club moving
## on it the first time.
func _draw_idle() -> void:
	var r := meter_rect()
	var width := 1920
	if is_inside_tree() and DisplayServer.window_get_size().x > 0:
		width = DisplayServer.window_get_size().x
	var m := LinksMouse.meter_for(width)
	var px := r.size.y / m.height
	var ball_y := r.end.y - m.ball_line * px
	var top_y := r.end.y - (m.height - 10) * px
	draw_rect(r.grow(3), Color(0, 0, 0, 0.3))
	draw_rect(r, Color(1, 1, 1, 0.08))
	draw_rect(r, Color(1, 1, 1, 0.45), false, 1.5)
	draw_line(Vector2(r.position.x - 6, top_y), Vector2(r.end.x + 6, top_y), Color(1, 1, 1, 0.35), 1.5)
	draw_line(Vector2(r.position.x - 10, ball_y), Vector2(r.end.x + 10, ball_y), Color(1, 1, 1, 0.8), 2.0)
	if ghost >= 0.0:
		var gy := lerpf(ball_y, top_y, ghost)
		draw_rect(Rect2(r.position.x, gy, r.size.x, ball_y - gy), Color(1.0, 0.82, 0.25, 0.28))
		draw_rect(Rect2(r.position.x - 4, gy - 3, r.size.x + 8, 6), Color(1, 1, 1, 0.75))
	var font := GlassTheme.font(600)
	var text := "MOUSE SWING"
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var at := Vector2(r.get_center().x - tw * 0.5, r.position.y - 12)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.6))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8))
