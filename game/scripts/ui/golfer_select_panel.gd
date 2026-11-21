class_name GolferSelectPanel
extends Control
## "Select golfer": which golfer a player plays as, with a live 3D preview
## (GolferPreview). One of the realistic people (PlayerLook.PEOPLE), or
## Custom, the body shaped in the player creator, and, for the whole
## round, the filmed golfer (Settings > Golfer > Photo). The choice is
## saved with the player's profile (PlayerProfiles), the same place the
## player creator keeps it, so it shows in every round under that name.
## Opened from the main menu's top bar and from each player's row on the
## round setup page.

## Closed; `player_name` is the player shown.
signal closed(player_name: String)
## Asks for the player creator on this player, to change their clothes,
## face and body.
signal edit_requested(player_name: String)

## The golfers, as [person id ("" for Custom), name, line under it].
static func choices() -> Array:
	var out: Array = []
	for p: Array in PlayerLook.PEOPLE:
		var line := "Real scanned person"
		if p[0] == PlayerLook.DEFAULT_PERSON:
			line += ", the default golfer"
		if p[0] == PlayerLook.MIXAMO_PERSON:
			line += " (Mixamo rig)"
		out.append([p[0], p[1], line])
	out.append(["", "Custom", "The body, face and hair you shape in the player creator"])
	return out


var player_name := ""
var look: PlayerLook
var _profiles := PlayerProfiles.new()
var _preview: GolferPreview
var _title: Label
var _list: VBoxContainer
var _buttons: Array[Button] = []
var _filmed: CheckButton
var _message: Label
var _select: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var bg := ColorRect.new()
	bg.color = MenuStyle.BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	row.add_child(left)
	_preview = GolferPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(300, 300)
	left.add_child(_preview)
	var views := HBoxContainer.new()
	views.alignment = BoxContainer.ALIGNMENT_CENTER
	views.add_theme_constant_override("separation", 10)
	left.add_child(views)
	var step_back := MenuStyle.button("‹ Previous")
	step_back.pressed.connect(func() -> void: _step(-1))
	views.add_child(step_back)
	var swing := MenuStyle.button("Swing")
	swing.pressed.connect(func() -> void: _preview.swing())
	views.add_child(swing)
	var face := MenuStyle.button("Face")
	face.toggle_mode = true
	face.toggled.connect(func(on: bool) -> void: _preview.set_face_view(on))
	views.add_child(face)
	var step_on := MenuStyle.button("Next ›")
	step_on.pressed.connect(func() -> void: _step(1))
	views.add_child(step_on)
	var drag := Label.new()
	drag.text = "Drag to turn the golfer round."
	drag.modulate = Color(1, 1, 1, 0.6)
	drag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(drag)

	var panel := PanelContainer.new()
	MenuStyle.panel(panel)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var heading := MenuStyle.heading("SELECT GOLFER", 36)
	heading.add_theme_font_override("font", GlassTheme.display_font(700))
	box.add_child(heading)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.modulate = Color(1, 1, 1, 0.8)
	box.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var group := ButtonGroup.new()
	for c: Array in choices():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 58)
		b.text = "%s\n%s" % [c[1], c[2]]
		b.add_theme_font_size_override("font_size", 17)
		var id: String = c[0]
		b.pressed.connect(func() -> void: _pick(id))
		_list.add_child(b)
		_buttons.append(b)
	_filmed = CheckButton.new()
	_filmed.text = "Filmed golfer (prototype): a real golfer filmed swinging, frame by frame, like the early Links games. For everyone in the round; the 3D golfer still putts and walks."
	_filmed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_filmed.custom_minimum_size = Vector2(0, 40)
	box.add_child(_filmed)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", MenuStyle.WARNING)
	box.add_child(_message)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	var edit := MenuStyle.button("Clothes, face and body...")
	edit.tooltip_text = "Open the player creator on this golfer"
	edit.pressed.connect(func() -> void:
		_save()
		close()
		edit_requested.emit(player_name))
	buttons.add_child(edit)
	var back := MenuStyle.button("Back")
	back.pressed.connect(cancel)
	buttons.add_child(back)
	_select = MenuStyle.button("Select")
	_select.pressed.connect(func() -> void:
		_save()
		close()
		closed.emit(player_name))
	buttons.add_child(_select)


## Shows `p_player_name`'s golfer: their saved look, or the standard golfer.
func open(p_player_name: String) -> void:
	player_name = p_player_name.strip_edges()
	if player_name.is_empty():
		player_name = RoundSetup.DEFAULT_NAMES[0]
	_profiles = PlayerProfiles.load_saved()
	var saved := _profiles.look_of(player_name)
	look = saved if saved != null else PlayerLook.default_look()
	_title.text = "Playing as %s" % player_name
	_filmed.set_pressed_no_signal(GraphicsSettings.load_saved().photo_golfer)
	_message.text = ""
	visible = true
	_mark()
	if not _preview.show_look(look):
		_message.text = "The golfer model is missing from this build, so there is nothing to preview."
	var at := _index()
	if at >= 0:
		_buttons[at].grab_focus.call_deferred()


func close() -> void:
	visible = false


func cancel() -> void:
	close()
	closed.emit(player_name)


## The look with person `id` ("" for Custom): a person brings their own
## sex and a typical height, as the player creator's Golfer tab does.
static func with_person(l: PlayerLook, id: String) -> PlayerLook:
	var out := l.duplicate_look()
	out.person = id
	if id != "":
		out.sex = PlayerLook.person_sex(id)
		out.height_cm = 168.0 if out.sex >= 0.5 else 180.0
	return out


func _pick(id: String) -> void:
	look = with_person(look, id)
	_mark()
	_preview.show_look(look)


func _step(step: int) -> void:
	var all := choices()
	var i := wrapi(maxi(_index(), 0) + step, 0, all.size())
	_pick(all[i][0])


func _index() -> int:
	var all := choices()
	for i in all.size():
		if all[i][0] == look.person:
			return i
	return -1


func _mark() -> void:
	var at := _index()
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == at)


func _save() -> void:
	_profiles = PlayerProfiles.load_saved()
	_profiles.set_look(player_name, look)
	_profiles.save()
	var settings := GraphicsSettings.load_saved()
	if settings.photo_golfer != _filmed.button_pressed:
		settings.photo_golfer = _filmed.button_pressed
		settings.save()
