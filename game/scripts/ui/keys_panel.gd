class_name KeysPanel
extends MarginContainer
## Settings > Keys: each control with the key that plays it (KeyRemap).
## Click a key, then press the new one (Esc cancels); a key that already
## did something swaps with it. Reset puts every key back.

signal closed

var _buttons: Array[Button] = []
var _waiting := -1  ## the ACTIONS row waiting for a key, or -1
var _note: Label


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = "Keys"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for i in KeyRemap.ACTIONS.size():
		var label := Label.new()
		label.text = KeyRemap.ACTIONS[i][0]
		grid.add_child(label)
		var b := MenuStyle.button("")
		b.custom_minimum_size.x = 150
		b.pressed.connect(_wait_for.bind(i))
		grid.add_child(b)
		_buttons.append(b)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 14)
	_note.modulate = Color(1, 1, 1, 0.7)
	_note.text = "Click a key, then press the new one. The on-screen hints keep the usual keys."
	box.add_child(_note)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	box.add_child(footer)
	var done := MenuStyle.button("Done")
	done.custom_minimum_size.x = 120
	done.pressed.connect(close_keys)
	footer.add_child(done)
	var reset := MenuStyle.button("Usual keys")
	reset.pressed.connect(func() -> void:
		KeyRemap.reset()
		KeyRemap.save_keys()
		_refresh())
	footer.add_child(reset)
	_refresh()


func open() -> void:
	_waiting = -1
	KeyRemap.capturing = false
	_refresh()
	visible = true


func close_keys() -> void:
	_waiting = -1
	KeyRemap.capturing = false
	visible = false
	closed.emit()


func _refresh() -> void:
	for i in _buttons.size():
		_buttons[i].text = "Press a key..." if i == _waiting else KeyRemap.key_name(KeyRemap.key_for(KeyRemap.ACTIONS[i][1]))


func _wait_for(i: int) -> void:
	_waiting = i
	KeyRemap.capturing = true
	_refresh()


func _input(event: InputEvent) -> void:
	if not visible or _waiting < 0 or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	# Esc, F1 and F11 keep their jobs (menu, help, fullscreen).
	if code not in [KEY_ESCAPE, KEY_F1, KEY_F11]:
		KeyRemap.assign(KeyRemap.ACTIONS[_waiting][1], code)
		KeyRemap.save_keys()
	_waiting = -1
	KeyRemap.capturing = false
	_refresh()
