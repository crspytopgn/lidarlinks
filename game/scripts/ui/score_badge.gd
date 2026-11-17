class_name ScoreBadge
extends Control
## The moment a good thing happens, in the style of a TV golf graphic: a
## small dark panel low in the picture with the score (BIRDIE, EAGLE, HOLE
## IN ONE) and a line under it (chip-in, the putt's length), a thin colour
## bar for the score as on broadcast scorecards. It fades in and out; no
## bounce, no big words, so the game stays a sim.

const BIRDIE := Color(0.98, 0.34, 0.30)
const EAGLE := Color(1.0, 0.78, 0.22)
const ACE := Color(0.55, 0.85, 1.0)
const PURE := Color(0.70, 1.0, 0.72)
## Seconds: fading in, held, fading out.
const POP_S := 0.25
const HOLD_S := 2.4
const FADE_S := 0.5

var _title := ""
var _sub := ""
var _colour := Color.WHITE
var _big := true
var _t := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows `title` (and a smaller `sub` line) with a `colour` bar; small
## ones sit at the lower left.
func pop(title: String, sub := "", colour := Color.WHITE, big := true) -> void:
	_title = title.to_upper()
	_sub = sub
	_colour = colour
	_big = big
	_t = 0.0
	queue_redraw()


func showing() -> bool:
	return _t >= 0.0


func clear() -> void:
	_t = -1.0
	queue_redraw()


## The badge's slide (0 to 1, how far it has risen into place) and
## opacity `t` seconds in. Opacity 0 once it is over.
static func look_at_time(t: float) -> Vector2:
	if t < 0.0:
		return Vector2(1.0, 0.0)
	if t < POP_S:
		var u := t / POP_S
		return Vector2(1.0 - pow(1.0 - u, 3.0), u)
	if t < POP_S + HOLD_S:
		return Vector2(1.0, 1.0)
	var f := (t - POP_S - HOLD_S) / FADE_S
	return Vector2(1.0, clampf(1.0 - f, 0.0, 1.0))


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	if _t > POP_S + HOLD_S + FADE_S:
		_t = -1.0
	queue_redraw()


func _draw() -> void:
	if _t < 0.0:
		return
	var look := look_at_time(_t)
	var vs := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var size := roundi(vs.y * (0.034 if _big else 0.022))
	var ss := maxi(11, roundi(size * 0.5))
	var font := GlassTheme.font(700)
	var sub_font := GlassTheme.font(500)
	var w := maxf(font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x,
			sub_font.get_string_size(_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x if not _sub.is_empty() else 0.0)
	var pad := size * 0.6
	var h := size * 1.5 + (ss * 1.5 if not _sub.is_empty() else 0.0)
	var r := Rect2(vs.x * 0.5 - w * 0.5 - pad, vs.y * 0.74 + (1.0 - look.x) * size, w + pad * 2.0, h)
	if not _big:
		r.position = Vector2(vs.x * 0.06, vs.y * 0.70 + (1.0 - look.x) * size)
	var a := look.y
	draw_rect(r, Color(0.04, 0.06, 0.08, 0.72 * a))
	draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(2.0, size * 0.09))), Color(_colour, a))
	draw_string(font, r.position + Vector2(pad, size * 1.2), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.96 * a))
	if not _sub.is_empty():
		draw_string(sub_font, r.position + Vector2(pad, size * 1.2 + ss * 1.45), _sub,
				HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(0.82, 0.86, 0.9, 0.9 * a))


## The hole-out badge for a score: title, colour and whether it is worth
## one (nothing for par or worse, except a long putt or chip-in, which
## the caller asks for itself).
static func for_score(hole_strokes: int, par: int) -> Array:
	if hole_strokes == 1:
		return ["Hole in one", ACE]
	var diff := hole_strokes - par
	if diff <= -2:
		return [Scorecard.SCORE_NAMES.get(diff, "Albatross"), EAGLE]
	if diff == -1:
		return ["Birdie", BIRDIE]
	return []
