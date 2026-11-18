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

var _cover: ColorRect
var _note: Label
var _card: Control


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
		t.parallel().tween_property(_card, "modulate:a", 1.0, OUT_S)
		# Let the card reach the screen before the next scene's build holds
		# up the frames.
		t.tween_interval(0.1)
	t.tween_callback(func() -> void: get_tree().change_scene_to_file(path))
	# Give the new scene a frame to build before revealing it.
	t.tween_interval(0.05)
	t.tween_property(_cover, "color:a", 0.0, IN_S)
	if _card != null:
		t.parallel().tween_property(_card, "modulate:a", 0.0, IN_S * 0.6)
	t.tween_callback(queue_free)
