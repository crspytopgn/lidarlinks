class_name CoursePicture
extends Control
## A course's picture in a course picker (CoursePictures), cropped to fill
## the box, with a thin frame. A course with no picture yet gets a plain
## card: a fairway and flag drawn in the menu colours and a line saying the
## picture comes after the first round there.

const FRAME := Color(1, 1, 1, 0.16)
const SKY_TOP := Color(0.11, 0.20, 0.15)
const SKY_LOW := Color(0.06, 0.11, 0.08)
const FAIRWAY := Color(0.20, 0.34, 0.20)
const GREEN := Color(0.30, 0.47, 0.27)

var key := ""
var _tex: Texture2D
var _note := ""


func _init(size_px := Vector2(240, 135)) -> void:
	custom_minimum_size = size_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


## Puts a picture of `picture_size` to the left of `node` (or its right), in
## a row taking `node`'s place in its parent (which `node` must be in).
static func beside(node: Control, picture_size: Vector2, separation := 16, on_left := true) -> CoursePicture:
	var parent := node.get_parent()
	var at := node.get_index()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	parent.remove_child(node)
	parent.add_child(row)
	parent.move_child(row, at)
	var pic := CoursePicture.new(picture_size)
	pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(node)
	row.add_child(pic)
	if on_left:
		row.move_child(pic, 0)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return pic


## Shows course `course_key`'s picture (or the placeholder card).
func show_course(course_key: String) -> void:
	key = course_key
	_tex = CoursePictures.texture_for(course_key)
	_note = "" if _tex != null else "Picture after your first round here"
	queue_redraw()


func has_picture() -> bool:
	return _tex != null


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _tex != null:
		# Cover the box, centred, keeping the picture's shape.
		var ts := _tex.get_size()
		var s := maxf(r.size.x / ts.x, r.size.y / ts.y)
		var src_size := r.size / s
		draw_texture_rect_region(_tex, r, Rect2((ts - src_size) * 0.5, src_size))
	else:
		_draw_card(r)
	draw_rect(r, FRAME, false, 1.0)


func _draw_card(r: Rect2) -> void:
	var w := r.size.x
	var h := r.size.y
	var top := PackedColorArray([SKY_TOP, SKY_TOP, SKY_LOW, SKY_LOW])
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), top)
	# A fairway sweeping away to a green, as seen from the tee.
	var fairway := PackedVector2Array([
		Vector2(w * 0.30, h), Vector2(w * 0.40, h * 0.72), Vector2(w * 0.55, h * 0.52), Vector2(w * 0.60, h * 0.42),
		Vector2(w * 0.66, h * 0.42), Vector2(w * 0.66, h * 0.52), Vector2(w * 0.62, h * 0.72), Vector2(w * 0.70, h)])
	draw_colored_polygon(fairway, FAIRWAY)
	var green_at := Vector2(w * 0.63, h * 0.40)
	_draw_ellipse(green_at, Vector2(w * 0.07, h * 0.035), GREEN)
	# The flag.
	var pole := green_at + Vector2(w * 0.005, 0)
	var pole_top := pole - Vector2(0, h * 0.20)
	draw_line(pole, pole_top, Color(0.92, 0.92, 0.88), maxf(1.0, w / 240.0))
	draw_colored_polygon(PackedVector2Array([pole_top, pole_top + Vector2(w * 0.06, h * 0.035), pole_top + Vector2(0, h * 0.07)]), MenuStyle.ACCENT)
	if not _note.is_empty() and h >= 60:
		var font := GlassTheme.font(500)
		var fs := clampi(int(h / 11.0), 10, 15)
		var tw := font.get_string_size(_note, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > w - 12.0:
			return
		draw_string(font, Vector2((w - tw) * 0.5, h - fs * 0.8), _note, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.55))


func _draw_ellipse(c: Vector2, radius: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(pts, col)
