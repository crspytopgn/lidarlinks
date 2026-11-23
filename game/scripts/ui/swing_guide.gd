class_name SwingGuide
extends Control
## The first time a player has the mouse swing (or the finger or stick
## swing), a small card next to its meter shows how it goes, for someone who
## has never played a golf game: a mouse drawn pulling back towards the
## player and pushing forward in a straight line, in step with a ghost club
## on the meter, and three short steps. It goes once the player has made a
## swing that way, or clicks "Got it", and is never shown again (saved under
## [tips] in the settings file, one key per way of swinging). Plain dark TV
## panel like ScoreBadge: no bounce, no colours, so the game stays a sim.

signal dismissed(kind: Kind)

enum Kind { MOUSE, TOUCH, STICK }

const SECTION := "tips"
const KEYS: Array[String] = ["swing_guide_mouse", "swing_guide_touch", "swing_guide_stick"]
const TITLE := "HOW TO SWING"
const STEPS: Array = [
	["Hold down the left mouse button", "Pull the mouse slowly back towards you", "Push it forward, smoothly and straight"],
	["Put your finger on the Swing button", "Drag it slowly down towards you", "Flick it up, smoothly and straight"],
	["Pull the right stick slowly back", "Push it forward, smoothly and straight", "Let it go after the shot"],
]
const NOTES: Array[String] = [
	"Keep it straight: moving sideways curves the ball",
	"A tap on the button gives the 3-click meter",
	"B calls the swing off before you push",
]
## The demonstration's loop, in seconds: pull back, a pause at the top, the
## push through, then a rest at the ball.
const BACK_S := 1.4
const TOP_S := 0.3
const DOWN_S := 0.4
const REST_S := 1.1
const CARD_W := 300.0  ## at least; wider for the words
const PANEL := Color(0.04, 0.06, 0.08, 0.78)
const TEXT_X := 88.0

var kind := Kind.MOUSE
var _t := 0.0
var _button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_button = Button.new()
	_button.text = "Got it"
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.add_theme_font_override("font", GlassTheme.font(600))
	_button.add_theme_font_size_override("font_size", 14)
	for state: String in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.10 if state == "normal" else 0.22)
		box.border_color = Color(1, 1, 1, 0.55)
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		box.content_margin_left = 14.0
		box.content_margin_right = 14.0
		box.content_margin_top = 4.0
		box.content_margin_bottom = 4.0
		_button.add_theme_stylebox_override(state, box)
	_button.pressed.connect(func() -> void: dismiss())
	add_child(_button)


## Whether the guide for `kind` has been shown and done with.
static func seen(which: Kind, path := GraphicsSettings.PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	return bool(cfg.get_value(SECTION, KEYS[which], false))


## Never show the guide for `kind` again (the rest of the file is kept).
static func mark_seen(which: Kind, path := GraphicsSettings.PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file is fine
	cfg.set_value(SECTION, KEYS[which], true)
	cfg.save(path)


## The demonstration `t` seconds in: x is how far the club is up the
## meter's backswing (0 at the ball line, 1 at the top), y how far the
## mouse (or finger, or stick) has been pulled back (0 home, 1 all the way).
static func demo_at(t: float) -> Vector2:
	var loop := BACK_S + TOP_S + DOWN_S + REST_S
	var u := fposmod(t, loop)
	var back := 0.0
	if u < BACK_S:
		back = smoothstep(0.0, 1.0, u / BACK_S)
	elif u < BACK_S + TOP_S:
		back = 1.0
	elif u < BACK_S + TOP_S + DOWN_S:
		var f := (u - BACK_S - TOP_S) / DOWN_S
		back = 1.0 - f * f  # quickening, as a real push through
	return Vector2(back, back)


func showing() -> bool:
	return visible


## Shows the guide for `which` beside the meter at `meter` (screen pixels).
func show_for(which: Kind, meter: Rect2) -> void:
	if not visible or which != kind:
		_t = 0.0
	kind = which
	var h := card_height()
	var w := card_width()
	var screen := get_viewport_rect().size
	var x := meter.position.x - w - 40.0
	if meter.get_center().x < screen.x * 0.5:  # the meter is down the left: the card to its right
		x = meter.end.x + 48.0
	var y := clampf(meter.get_center().y - h * 0.5, 8.0, maxf(8.0, screen.y - h - 8.0))
	if x < 8.0 or x + w > screen.x - 8.0:  # a narrow screen: above the meter instead
		x = maxf(8.0, meter.end.x - w)
		y = maxf(8.0, meter.position.y - h - 36.0)
	position = Vector2(x, y)
	size = Vector2(w, h)
	visible = true
	_button.position = Vector2(w - _button.get_combined_minimum_size().x - 14.0, h - 40.0)
	_button.size = _button.get_combined_minimum_size()


func hide_guide() -> void:
	visible = false


## "Got it", or the first swing made: never shown again.
func dismiss() -> void:
	if not visible:
		return
	visible = false
	dismissed.emit(kind)


func card_height() -> float:
	return 214.0


## Wide enough for the steps and the note on one line each.
func card_width() -> float:
	var font := GlassTheme.font(500)
	var w := CARD_W
	for line: String in STEPS[kind]:
		w = maxf(w, TEXT_X + 16.0 + font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0)
	var button := _button.get_combined_minimum_size().x if _button != null else 80.0
	return maxf(w, 44.0 + font.get_string_size(NOTES[kind], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + button)


## The ghost club on the meter, in step with the drawing (0 to 1 up the
## backswing).
func ghost() -> float:
	return demo_at(_t).x if visible else -1.0


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, PANEL)
	draw_rect(Rect2(0, 0, r.size.x, 2.0), Color(1, 1, 1, 0.85))
	var bold := GlassTheme.font(700)
	var font := GlassTheme.font(500)
	draw_string(bold, Vector2(16, 28), TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.75))
	# The drawing: a mouse (a finger, a stick) on a straight track, pulled
	# back towards the player, then pushed forward.
	var demo := demo_at(_t)
	var track_top := 48.0
	var track_len := 76.0
	var cx := 44.0
	draw_dashes(Vector2(cx, track_top - 4.0), Vector2(cx, track_top + track_len + 20.0))
	var at := Vector2(cx, track_top + 14.0 + demo.y * track_len * 0.75)
	match kind:
		Kind.MOUSE:
			_draw_mouse(at)
		Kind.TOUCH:
			draw_circle(at, 11.0, Color(1, 1, 1, 0.18))
			draw_circle(at, 7.0, Color(1, 1, 1, 0.9))
		Kind.STICK:
			draw_circle(Vector2(cx, track_top + 44.0), 26.0, Color(1, 1, 1, 0.12))
			draw_arc(Vector2(cx, track_top + 44.0), 26.0, 0, TAU, 32, Color(1, 1, 1, 0.4), 1.0, true)
			draw_circle(Vector2(cx, track_top + 44.0 + demo.y * 18.0), 12.0, Color(1, 1, 1, 0.85))
	# Which way it is going: back (down) or forward (up).
	var going_back := fposmod(_t, BACK_S + TOP_S + DOWN_S + REST_S) < BACK_S
	var going_through := not going_back and demo.y > 0.0 and demo.y < 1.0
	if going_back or going_through:
		var tip := Vector2(cx + 26.0, track_top + (track_len + 4.0 if going_back else 6.0))
		var dir := 1.0 if going_back else -1.0
		draw_line(tip - Vector2(0, dir * 28.0), tip, Color(1, 1, 1, 0.6), 2.0, true)
		draw_colored_polygon(PackedVector2Array([tip + Vector2(0, dir * 6.0), tip + Vector2(-5, -dir * 2.0), tip + Vector2(5, -dir * 2.0)]), Color(1, 1, 1, 0.6))
	var steps: Array = STEPS[kind]
	var tx := TEXT_X
	var step_now := 0 if kind != Kind.STICK else -1
	if going_back:
		step_now = 1 if kind != Kind.STICK else 0
	elif going_through:
		step_now = 2 if kind != Kind.STICK else 1
	for i in steps.size():
		var y := 66.0 + i * 30.0
		var lit := i == step_now or (kind == Kind.MOUSE and i == 0)
		var a := 0.98 if lit else 0.6
		draw_string(bold, Vector2(tx, y), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, a))
		draw_string(font, Vector2(tx + 16.0, y), steps[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, a))
	draw_line(Vector2(16, size.y - 52.0), Vector2(size.x - 16.0, size.y - 52.0), Color(1, 1, 1, 0.12), 1.0)
	draw_string(font, Vector2(16, size.y - 22.0), NOTES[kind], HORIZONTAL_ALIGNMENT_LEFT, size.x - _button.size.x - 44.0, 12, Color(0.82, 0.86, 0.9, 0.7))


func draw_dashes(from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	var d := 0.0
	while d < length:
		draw_line(from.lerp(to, d / length), from.lerp(to, minf(d + 4.0, length) / length), Color(1, 1, 1, 0.3), 1.0)
		d += 8.0


## A computer mouse seen from above, cable end up (away from the player).
func _draw_mouse(at: Vector2) -> void:
	var body := Rect2(at - Vector2(11, 16), Vector2(22, 32))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.9)
	box.set_corner_radius_all(11)
	box.anti_aliasing = true
	draw_style_box(box, body)
	# The left button, held down.
	var left := Rect2(body.position + Vector2(2, 2), Vector2(9, 11))
	var lb := StyleBoxFlat.new()
	lb.bg_color = Color(0.25, 0.3, 0.36, 0.95)
	lb.corner_radius_top_left = 9
	lb.anti_aliasing = true
	draw_style_box(lb, left)
	draw_line(Vector2(at.x, body.position.y + 2.0), Vector2(at.x, body.position.y + 13.0), Color(0.2, 0.22, 0.25, 0.7), 1.0)
