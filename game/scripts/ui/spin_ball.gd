class_name SpinBall
extends BaseButton
## The ball-spin picker: click or tap a spot on the ball (or drag over it) to
## set the shot's spin, the way Links 2003's Advanced Shot Setup sets the
## trajectory and opens or closes the face and stance (ShotShape). The dot
## shows where the club meets the ball: low on the ball is a higher shot with
## more spin, high on the ball a lower one with less; left of centre
## draws (far left hooks), right fades (far right slices). Right-click,
## double-click or a tap in the middle puts it back to square. Q/E/W/S do
## the same from the keyboard.
##
## Away from Classic Links (which has no backspin setting) a slider to the
## right of the ball adds backspin: drag it up for more, enough for a wedge to
## check or spin back on the green, down for less (ShotShape.spin).

signal spin_picked(curve: int, height: int)
signal backspin_picked(steps: int)

const PILL_H := 22.0
const DOT := Color(1.0, 0.36, 0.25)
## The backspin slider's width, and the room it takes right of the ball.
const BAR_W := 10.0
const BAR_ROOM := 30.0

## The glass disc and pill (Broadcast presentation), and the backspin
## slider with them.
var modern := false:
	set(v):
		modern = v
		queue_redraw()

var _curve := 0
var _height := 0
var _spin := 0
var _dragging_bar := false
var _glass: FrostedGlass


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE  # Space must stay the swing key
	tooltip_text = "Ball spin: click where the club meets the ball; drag the slider for backspin (right-click resets)"
	_glass = FrostedGlass.new()
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glass)


func show_shape(shape: ShotShape) -> void:
	if shape.curve == _curve and shape.height == _height and shape.spin == _spin:
		return
	_curve = shape.curve
	_height = shape.height
	_spin = shape.spin
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			_dragging_bar = false
			return
		var on_bar := _on_bar(mb.position)
		if mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click):
			if on_bar:
				_pick_spin(0)
			else:
				_pick(0, 0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging_bar = on_bar
			if on_bar:
				_pick_spin(_bar_steps_at(mb.position.y))
			else:
				_pick_at(mb.position)
		accept_event()
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var at := (event as InputEventMouseMotion).position
		if _dragging_bar:
			_pick_spin(_bar_steps_at(at.y))
		else:
			_pick_at(at)
		accept_event()


## The backspin steps at height `y` on a slider from `top` to `bottom`:
## the top is the most backspin.
static func bar_steps_at(y: float, top: float, bottom: float) -> int:
	var k := clampf((y - top) / maxf(bottom - top, 1.0), 0.0, 1.0)
	return roundi((0.5 - k) * 2.0 * ShotShape.MAX_SPIN)


func _on_bar(local: Vector2) -> bool:
	return modern and local.x >= _bar_x() - BAR_ROOM * 0.5 and local.y <= _bar_bottom() + 6.0


func _bar_steps_at(y: float) -> int:
	return bar_steps_at(y, _bar_top(), _bar_bottom())


func _bar_x() -> float:
	return size.x - BAR_ROOM * 0.5


func _bar_top() -> float:
	return 8.0


func _bar_bottom() -> float:
	return _radius() * 2.0


func _pick_spin(steps: int) -> void:
	if steps == _spin:
		return
	_spin = steps
	queue_redraw()
	backspin_picked.emit(steps)


## The steps under `local`: across the ball is the curve, down it the height.
static func steps_at(local: Vector2, centre: Vector2, radius: float) -> Vector2i:
	var d := (local - centre) / maxf(radius, 1.0)
	if d.length() > 1.0:
		d = d.normalized()
	return Vector2i(roundi(d.x * ShotShape.MAX_CURVE), roundi(d.y * ShotShape.MAX_HEIGHT))


func _pick_at(local: Vector2) -> void:
	var s := steps_at(local, _centre(), _radius())
	_pick(s.x, s.y)


func _pick(curve: int, height: int) -> void:
	if curve == _curve and height == _height:
		return
	_curve = curve
	_height = height
	queue_redraw()
	spin_picked.emit(curve, height)


func _radius() -> float:
	return minf(size.x - (BAR_ROOM * 2.0 if modern else 0.0), size.y - PILL_H - 6.0) * 0.5 - 2.0


func _centre() -> Vector2:
	return Vector2(size.x * 0.5 - (BAR_ROOM * 0.5 if modern else 0.0), _radius() + 2.0)


## "Normal spin", "Backspin 2, fade 2", "Higher 1"...
func describe() -> String:
	var parts: Array[String] = []
	if _spin != 0 and modern:
		parts.append("%s %d" % ["backspin" if _spin > 0 else "less spin", absi(_spin)])
	if _height != 0:
		parts.append("%s %d" % ["higher" if _height > 0 else "lower", absi(_height)])
	if _curve != 0:
		var big := absi(_curve) * 2 > ShotShape.MAX_CURVE
		var word := ("slice" if big else "fade") if _curve > 0 else ("hook" if big else "draw")
		parts.append("%s %d" % [word, absi(_curve)])
	if parts.is_empty():
		return "Normal spin"
	var text := ", ".join(parts)
	return text.substr(0, 1).to_upper() + text.substr(1)


func _draw() -> void:
	var r := _radius()
	var c := _centre()
	_glass.begin()
	if modern:
		_glass.add(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), 1.0, Vector4.ONE * r)
	_glass.commit()
	if not modern:
		draw_circle(c, r, Color(0, 0, 0, 0.35))
	# The ball: a soft white face with a thin rim and faint centre lines.
	draw_circle(c, r * 0.78, Color(1, 1, 1, 0.16))
	draw_arc(c, r * 0.78, 0.0, TAU, 48, Color(1, 1, 1, 0.75), 1.5, true)
	var faint := Color(1, 1, 1, 0.25)
	draw_line(c - Vector2(r * 0.78, 0), c + Vector2(r * 0.78, 0), faint, 1.0, true)
	draw_line(c - Vector2(0, r * 0.78), c + Vector2(0, r * 0.78), faint, 1.0, true)
	# Where the club meets the ball (the same mapping as steps_at).
	var at := c + Vector2(float(_curve) / ShotShape.MAX_CURVE, float(_height) / ShotShape.MAX_HEIGHT) * r * 0.78
	draw_circle(at, 5.0, DOT)
	draw_arc(at, 5.0, 0.0, TAU, 16, Color(0, 0, 0, 0.6), 1.0, true)
	if modern:
		_draw_bar()
	var font := GlassTheme.display_font(600) if modern else get_theme_default_font()
	var fs := 14 if modern else 12
	var text := describe().to_upper() if modern else describe()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(c.x - w * 0.5, c.y + r + 16.0)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## The backspin slider: a slim track with a tick per step, a curl at the top
## (more backspin) and the picked step as a bright knob.
func _draw_bar() -> void:
	var x := _bar_x()
	var top := _bar_top()
	var bottom := _bar_bottom()
	var mid := (top + bottom) * 0.5
	var track := Rect2(x - BAR_W * 0.5, top, BAR_W, bottom - top)
	draw_rect(track, Color(0, 0, 0, 0.35))
	draw_rect(track, Color(1, 1, 1, 0.5), false, 1.0)
	for i in range(-ShotShape.MAX_SPIN, ShotShape.MAX_SPIN + 1):
		var y := mid - float(i) / ShotShape.MAX_SPIN * (bottom - top) * 0.5
		var w := BAR_W * (0.9 if i == 0 else 0.5)
		draw_line(Vector2(x - w * 0.5, y), Vector2(x + w * 0.5, y), Color(1, 1, 1, 0.35), 1.0)
	var at := mid - float(_spin) / ShotShape.MAX_SPIN * (bottom - top) * 0.5
	if _spin != 0:
		draw_rect(Rect2(x - BAR_W * 0.5 + 2.0, minf(at, mid), BAR_W - 4.0, absf(at - mid)), Color(DOT, 0.7))
	draw_circle(Vector2(x, at), 6.0, DOT)
	draw_arc(Vector2(x, at), 6.0, 0.0, TAU, 16, Color(0, 0, 0, 0.6), 1.0, true)
	draw_arc(Vector2(x, top - 3.0), 3.5, PI * 0.15, PI * 1.6, 10, Color(1, 1, 1, 0.8), 1.5, true)
