class_name SceneFade
extends CanvasLayer
## Smooth transitions: a fade through black between scenes (the fade lives
## on the tree's root, so it carries across the change) and a quick fade-in
## for menu panels as they open.

const OUT_S := 0.22
const IN_S := 0.35
const PANEL_S := 0.18
const SPRING_S := 0.45
const SPRING_FROM := 0.94
const GOLD := Color(0.914, 0.78, 0.4)
## Written once a round has drawn its first frames on this computer. Until
## then the loading note warns that the first start takes longer: the
## graphics driver builds its shaders for this machine (on a Mac's Metal
## that can hold a black screen for a minute or more).
const WARM_MARK := "user://first_round_drawn"

## Longest a loading card waits for the next scene to say it is ready
## (release()) before showing it anyway.
const HOLD_MAX_S := 240.0

var _cover: ColorRect
var _note: Label
var _card: Control
var _status: Label
var _bar: ColorRect
var _bar_back: ColorRect
var _spinner: Control
var _released := false
var _held := 0.0


## Fades out, switches to the scene at `path`, then fades back in. A
## non-empty `message` shows on the black while the next scene builds, so
## a long load never looks like a frozen game.
static func change_scene(tree: SceneTree, path: String, message := "") -> void:
	if tree.root.has_node("SceneFade"):
		return  # already on the way somewhere
	var fade := SceneFade.new()
	fade.name = "SceneFade"
	tree.root.add_child(fade)
	fade._run(path, message)


## The loading card on screen, if any.
static func live(tree: SceneTree) -> SceneFade:
	return tree.root.get_node_or_null("SceneFade") as SceneFade


## Says what the loading card is waiting on, with how far along it is
## (0 to 1, or below 0 for no bar). Nothing without a card.
static func status(tree: SceneTree, text: String, fraction := -1.0) -> void:
	var f := live(tree)
	if f == null or f._status == null:
		return
	f._status.text = text
	f._bar_back.visible = fraction >= 0.0
	f._bar.size.x = f._bar_back.size.x * clampf(fraction, 0.0, 1.0)


## The scene behind a loading card is ready: the card fades away. Until then
## (or HOLD_MAX_S) it stays up, so a round that is still building, or
## drawing its first frames, never shows as a frozen half-built picture.
static func release(tree: SceneTree) -> void:
	var f := live(tree)
	if f != null:
		f._released = true


## Whether a loading card is up and waiting for release().
static func holding(tree: SceneTree) -> bool:
	var f := live(tree)
	return f != null and f._card != null and not f._released


## The loading note for a round: longer the first time on this computer.
static func round_message() -> String:
	if FileAccess.file_exists(WARM_MARK):
		return "Loading the course..."
	return "Loading the course...\nThe first time, the game also prepares its graphics for this computer.\nThis can take a minute or two."


## Called once a round is on screen, so later loads show the short note.
static func mark_warm() -> void:
	if FileAccess.file_exists(WARM_MARK):
		return
	var f := FileAccess.open(WARM_MARK, FileAccess.WRITE)
	if f != null:
		f.store_line(Time.get_datetime_string_from_system(true))


## Fades `c` in over a moment, for a panel that has just been shown, and
## springs it up from a touch smaller, as phone interfaces open a sheet.
static func pop_in(c: CanvasItem) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	var t := c.create_tween()
	t.tween_property(c, "modulate:a", 1.0, PANEL_S)
	if c is Control:
		var ctl := c as Control
		ctl.pivot_offset = ctl.size * 0.5
		ctl.scale = Vector2.ONE * SPRING_FROM
		t.parallel().tween_property(ctl, "scale", Vector2.ONE, SPRING_S).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)


func _init() -> void:
	layer = 128
	_cover = ColorRect.new()
	_cover.color = Color(0, 0, 0, 0)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_cover)


func _run(path: String, message: String) -> void:
	var t := create_tween()
	t.tween_property(_cover, "color:a", 1.0, OUT_S)
	if not message.is_empty():
		# A loading card, as console games show between menu and round: the
		# menu photo dimmed, a gold rule and the note in the broadcast type.
		_card = Control.new()
		_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_card.modulate.a = 0.0
		add_child(_card)
		var photo := TextureRect.new()
		photo.texture = MenuHome._art("hero")
		photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		photo.modulate = Color(0.42, 0.44, 0.43)
		photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_card.add_child(photo)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		box.grow_vertical = Control.GROW_DIRECTION_BEGIN
		box.offset_left = 72
		box.offset_bottom = -64
		_card.add_child(box)
		var head := Label.new()
		head.text = "LOADING"
		head.add_theme_font_override("font", GlassTheme.display_font(700))
		head.add_theme_font_size_override("font_size", 56)
		box.add_child(head)
		var rule := ColorRect.new()
		rule.color = GOLD
		rule.custom_minimum_size = Vector2(96, 3)
		rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(rule)
		_note = Label.new()
		_note.text = message.replace("Loading the course...", "").strip_edges()
		_note.add_theme_font_override("font", GlassTheme.font(500))
		_note.add_theme_font_size_override("font_size", 18)
		_note.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(_note)
		_note.visible = not _note.text.is_empty()
		# What it is doing now, a bar where the work can be counted, and a
		# turning ring that keeps moving whenever a frame is drawn.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		_spinner = Spinner.new()
		_spinner.custom_minimum_size = Vector2(22, 22)
		row.add_child(_spinner)
		_status = Label.new()
		_status.text = "Starting..."
		_status.add_theme_font_override("font", GlassTheme.font(500))
		_status.add_theme_font_size_override("font_size", 18)
		_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		row.add_child(_status)
		_bar_back = ColorRect.new()
		_bar_back.color = Color(1, 1, 1, 0.18)
		_bar_back.custom_minimum_size = Vector2(320, 4)
		_bar_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_bar_back.visible = false
		box.add_child(_bar_back)
		_bar = ColorRect.new()
		_bar.color = GOLD
		_bar.size = Vector2(0, 4)
		_bar_back.add_child(_bar)
		t.parallel().tween_property(_card, "modulate:a", 1.0, OUT_S)
		# Let the card reach the screen before the next scene's build holds
		# up the frames.
		t.tween_interval(0.1)
	t.tween_callback(func() -> void: get_tree().change_scene_to_file(path))
	# Give the new scene a frame to build before revealing it.
	t.tween_interval(0.05)
	if _card != null:
		# A round says when it is ready (release()); the card stays till then.
		t.tween_callback(_reveal_when_released)
		return
	t.tween_property(_cover, "color:a", 0.0, IN_S)
	t.tween_callback(queue_free)


func _reveal_when_released() -> void:
	while not _released and _held < HOLD_MAX_S:
		await get_tree().process_frame
		_held += get_process_delta_time()
	var t := create_tween()
	t.tween_property(_cover, "color:a", 0.0, IN_S)
	t.parallel().tween_property(_card, "modulate:a", 0.0, IN_S * 0.6)
	t.tween_callback(queue_free)



## A ring a quarter open, turning: it moves whenever the game draws a
## frame, so a card that is still turning is not a frozen game.
class Spinner extends Control:
	var _angle := 0.0

	func _process(delta: float) -> void:
		_angle = fmod(_angle + delta * TAU * 0.9, TAU)
		queue_redraw()

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_arc(size * 0.5, r, 0.0, TAU, 32, Color(1, 1, 1, 0.15), 3.0, true)
		draw_arc(size * 0.5, r, _angle, _angle + TAU * 0.75, 32, SceneFade.GOLD, 3.0, true)
