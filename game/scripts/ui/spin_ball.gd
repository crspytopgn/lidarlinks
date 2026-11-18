class_name SpinBall
extends BaseButton
## The ball-spin picker: click or tap a spot on the ball (or drag over it) to
## set the shot's spin, the way Links 2003's Advanced Shot Setup sets the
## trajectory and opens or closes the face and stance (ShotShape). The dot
## shows where the club meets the ball: low on the ball is a higher shot with
## more backspin, high on the ball a lower one with less; left of centre
## draws (far left hooks), right fades (far right slices). Right-click,
## double-click or a tap in the middle puts it back to square. Q/E/W/S do
## the same from the keyboard.

signal spin_picked(curve: int, height: int)

const PILL_H := 22.0
const DOT := Color(1.0, 0.36, 0.25)

## The glass disc and pill (Broadcast presentation).
var modern := false:
	set(v):
		modern = v
		queue_redraw()

var _curve := 0
var _height := 0
var _glass: FrostedGlass


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE  # Space must stay the swing key
	tooltip_text = "Ball spin: click where the club meets the ball (right-click resets)"
	_glass = FrostedGlass.new()
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glass)


func show_shape(shape: ShotShape) -> void:
	if shape.curve == _curve and shape.height == _height:
		return
	_curve = shape.curve
	_height = shape.height
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click):
			_pick(0, 0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_pick_at(mb.position)
		accept_event()
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_pick_at((event as InputEventMouseMotion).position)
		accept_event()


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
	return minf(size.x, size.y - PILL_H - 6.0) * 0.5 - 2.0


func _centre() -> Vector2:
	return Vector2(size.x * 0.5, _radius() + 2.0)


## "Normal spin", "More backspin, fade 2"...
func describe() -> String:
	var parts: Array[String] = []
	if _height != 0:
		parts.append("%s backspin" % ("More" if _height > 0 else "Less"))
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
	var font := GlassTheme.display_font(600) if modern else get_theme_default_font()
	var fs := 14 if modern else 12
	var text := describe().to_upper() if modern else describe()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(c.x - w * 0.5, c.y + r + 16.0)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
