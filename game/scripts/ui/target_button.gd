class_name TargetButton
extends Button
## The on-screen "View target" button (TargetView): a glass pill with a
## small crosshair drawn beside the words, so it needs no symbol font. It
## reads "Back to ball" while the camera is out at the target. Key Y, pad Y.

const SIZE := Vector2(176, 42)
const ICON := 9.0  ## crosshair ring radius
const PAD_LEFT := 40.0

## True while the camera is out at the target (the label then offers the way back).
var out := false:
	set(v):
		if v != out:
			out = v
			text = "BACK TO BALL" if v else "VIEW TARGET"
			queue_redraw()


func _init() -> void:
	text = "VIEW TARGET"
	tooltip_text = "Look at where you're aiming (key Y, pad Y)"
	focus_mode = Control.FOCUS_NONE  # Space swings; it mustn't press this
	custom_minimum_size = SIZE
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_font_override("font", GlassTheme.display_font(700))
	add_theme_font_size_override("font_size", 17)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, _style(state))


func _ready() -> void:
	if Glass.blurs():
		Glass.backdrop(self, int(SIZE.y * 0.5))


func _style(state: String) -> StyleBox:
	if state == "focus":
		return StyleBoxEmpty.new()
	var s := Glass.panel_style(int(SIZE.y * 0.5), 0.0)
	s.content_margin_left = PAD_LEFT
	s.content_margin_right = 16.0
	match state:
		"hover":
			s.bg_color = s.bg_color.lightened(0.12)
		"pressed":
			s.bg_color = s.bg_color.lightened(0.24)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 3)
	return s


func _draw() -> void:
	var c := Vector2(PAD_LEFT * 0.5 + 4.0, size.y * 0.5)
	var col := GlassTheme.TEXT
	if out:
		# A small arrow back to the golfer.
		var w := ICON
		draw_polyline(PackedVector2Array([c + Vector2(w * 0.3, -w), c + Vector2(-w * 0.6, 0), c + Vector2(w * 0.3, w)]), col, 2.2, true)
		draw_line(c + Vector2(-w * 0.6, 0), c + Vector2(w, 0), col, 2.2, true)
		return
	draw_arc(c, ICON, 0.0, TAU, 32, col, 1.8, true)
	draw_circle(c, 2.0, col)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * (ICON - 3.5), c + d * (ICON + 4.0), col, 1.8, true)
