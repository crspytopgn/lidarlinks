class_name PhotoMode
extends Node
## Photo mode: the round stops, the HUD goes, and a free camera flies over
## the course to frame a picture. The time of day can be changed on the
## spot (dawn to sunset), the lens zoomed, and on the desktop renderer a
## depth of field focuses on whatever sits in the middle of the frame.
## Costs nothing until it is opened; it adds no work to normal play.
##
## Keys: WASD or arrows move, Q/E down and up, Shift faster; drag the mouse
## to look, the wheel zooms; T and Shift+T step the time of day; F turns the
## depth of field on and off; H hides the help bar; Enter saves the picture;
## Esc or P leaves. On a touch screen: one finger looks, two fingers drag to
## move and pinch to zoom, and the bar's buttons do the rest.

signal closed
## The time of day was stepped to `time` (a GraphicsSettings.TimeOfDay).
signal time_changed(time: int)

const MOVE_SPEED := 6.0  # m/s; Shift is FAST times that
const FAST := 5.0
const LOOK_RATE := 0.0035  # radians per pixel dragged
const MIN_FOV := 12.0
const MAX_FOV := 80.0
const MIN_CLEARANCE := 0.12  # how close to the ground the lens may go, m
const MAX_HEIGHT := 150.0  # above the ground, m
const MAX_RANGE := 600.0  # from where photo mode opened, m
const FOCUS_RAY := 600.0
## The times the T key steps through, in the order of a day.
const DAY := [
	GraphicsSettings.TimeOfDay.DAWN, GraphicsSettings.TimeOfDay.MORNING, GraphicsSettings.TimeOfDay.MIDDAY,
	GraphicsSettings.TimeOfDay.AFTERNOON, GraphicsSettings.TimeOfDay.GOLDEN, GraphicsSettings.TimeOfDay.SUNSET,
]

var active := false
## The ground height under (x, z); keeps the lens out of the turf and finds
## the focus. Defaults to flat ground at 0.
var height_at: Callable = func(_x: float, _z: float) -> float: return 0.0
var time_of_day: int = GraphicsSettings.TimeOfDay.AFTERNOON

var camera: Camera3D
var _back_to: Camera3D
var _origin := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _dof := false
var _focus := 30.0
var _dragging := false
var _touches := {}
var _hidden: Array[CanvasItem] = []
var _hidden_layers: Array[CanvasLayer] = []
var _hidden_3d: Array[Node3D] = []
var _layer: CanvasLayer
var _bar: PanelContainer
var _info: Label
var _saving := false


func _ready() -> void:
	set_process(false)
	set_process_input(false)


## Opens photo mode from where `from` is looking; `hide_nodes` are the HUD
## layers and 3D aids to take away while it is open (put back on close()).
func open(from: Camera3D, hide_nodes: Array) -> void:
	if active:
		return
	active = true
	_back_to = from
	if camera == null:
		camera = Camera3D.new()
		camera.name = "PhotoCamera"
		add_child(camera)
	camera.global_transform = from.global_transform
	camera.fov = from.fov
	camera.near = from.near
	camera.far = from.far
	camera.environment = from.environment
	_origin = from.global_position
	var e := from.global_transform.basis.get_euler(EULER_ORDER_YXZ)
	_pitch = e.x
	_yaw = e.y
	camera.make_current()
	_hidden.clear()
	_hidden_layers.clear()
	for n in hide_nodes:
		if n is CanvasLayer and (n as CanvasLayer).visible:
			(n as CanvasLayer).visible = false
			_hidden_layers.append(n)
		elif n is CanvasItem and (n as CanvasItem).visible:
			(n as CanvasItem).visible = false
			_hidden.append(n)
		elif n is Node3D and (n as Node3D).visible:
			(n as Node3D).visible = false
			_hidden_3d.append(n)
	_build_ui()
	_layer.visible = true
	_update_dof()
	_show_info()
	set_process(true)
	set_process_input(true)


func close() -> void:
	if not active:
		return
	active = false
	set_process(false)
	set_process_input(false)
	_touches.clear()
	_dragging = false
	if _back_to != null and is_instance_valid(_back_to):
		_back_to.make_current()
	for n in _hidden_layers:
		if is_instance_valid(n):
			n.visible = true
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	for n in _hidden_3d:
		if is_instance_valid(n):
			n.visible = true
	_hidden_layers.clear()
	_hidden.clear()
	_hidden_3d.clear()
	if _layer != null:
		_layer.visible = false
	closed.emit()


## Depth of field needs the desktop (Forward+) renderer.
static func dof_available() -> bool:
	return GraphicsSettings.is_forward_plus()


## The next (or with `step` -1 the previous) time of day in DAY order.
static func step_time(time: int, step: int) -> int:
	var i := DAY.find(time)
	if i < 0:
		return DAY[3] if step > 0 else DAY[2]  # "Through the round" goes to afternoon
	return DAY[posmod(i + step, DAY.size())]


## Where the middle of the frame meets the ground, metres along the view;
## FOCUS_RAY when it never does (the sky).
static func focus_distance(origin: Vector3, dir: Vector3, ground: Callable) -> float:
	var d := 0.5
	var step := 0.25
	while d < FOCUS_RAY:
		var p := origin + dir * d
		if p.y <= float(ground.call(p.x, p.z)):
			return d
		d += step
		step = minf(step * 1.08, 4.0)
	return FOCUS_RAY


func _process(delta: float) -> void:
	if camera == null:
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_E):
		move.y += 1.0
	if Input.is_key_pressed(KEY_Q):
		move.y -= 1.0
	if move != Vector3.ZERO:
		var speed := MOVE_SPEED * (FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		_move(move.normalized() * speed * delta)
	camera.global_basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0), EULER_ORDER_YXZ)
	if _dof:
		var f := focus_distance(camera.global_position, -camera.global_basis.z, height_at)
		_focus = lerpf(_focus, f, minf(1.0, delta * 6.0))
		_set_focus(_focus)


## Moves the lens by `local` (x right, y up, z back along the view, on the
## level), keeping it over the ground and near the course.
func _move(local: Vector3) -> void:
	var flat := Basis(Vector3.UP, _yaw)
	var p := camera.global_position + flat * Vector3(local.x, 0.0, local.z) + Vector3.UP * local.y
	var off := Vector2(p.x - _origin.x, p.z - _origin.z)
	if off.length() > MAX_RANGE:
		off = off.normalized() * MAX_RANGE
		p.x = _origin.x + off.x
		p.z = _origin.z + off.y
	var g := float(height_at.call(p.x, p.z))
	p.y = clampf(p.y, g + MIN_CLEARANCE, g + MAX_HEIGHT)
	camera.global_position = p


func _look(rel: Vector2) -> void:
	_yaw -= rel.x * LOOK_RATE
	_pitch = clampf(_pitch - rel.y * LOOK_RATE, -1.45, 1.45)


func _zoom(factor: float) -> void:
	camera.fov = clampf(camera.fov * factor, MIN_FOV, MAX_FOV)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			match k.keycode:
				KEY_ESCAPE, KEY_P:
					close()
				KEY_T:
					_step_time(-1 if k.shift_pressed else 1)
				KEY_F:
					_toggle_dof()
				KEY_H:
					_bar.visible = not _bar.visible
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					save_photo()
				KEY_EQUAL, KEY_KP_ADD:
					_zoom(0.9)
				KEY_MINUS, KEY_KP_SUBTRACT:
					_zoom(1.0 / 0.9)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Clicks on the bar's buttons go to the bar.
		if _bar.visible and _bar.get_global_rect().has_point(mb.position):
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(0.92)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / 0.92)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _dragging and _touches.is_empty():
			_look((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / maxf((event as InputEventMagnifyGesture).factor, 0.01))
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_move(Vector3(pg.delta.x, 0.0, pg.delta.y) * 0.5)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _bar.visible and _bar.get_global_rect().has_point(t.position):
			return
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if not _touches.has(d.index):
			return
		if _touches.size() == 1:
			_look(d.relative)
		elif _touches.size() == 2:
			var other: Vector2 = Vector2.ZERO
			for i in _touches:
				if i != d.index:
					other = _touches[i]
			var before := (_touches[d.index] as Vector2).distance_to(other)
			var after := d.position.distance_to(other)
			if before > 1.0 and after > 1.0:
				_zoom(before / after)
			# Both fingers dragged together move the lens; each finger's
			# share is half the move.
			_move(Vector3(-d.relative.x, 0.0, -d.relative.y) * 0.02)
		_touches[d.index] = d.position
		get_viewport().set_input_as_handled()


func _step_time(step: int) -> void:
	time_of_day = step_time(time_of_day, step)
	time_changed.emit(time_of_day)
	_show_info()


func _toggle_dof() -> void:
	if not dof_available():
		_show_info("Depth of field needs the desktop renderer")
		return
	_dof = not _dof
	if _dof:
		_focus = focus_distance(camera.global_position, -camera.global_basis.z, height_at)
	_update_dof()
	_show_info()


func _update_dof() -> void:
	if not _dof or not dof_available():
		camera.attributes = _back_to.attributes if _back_to != null else null
		return
	var a := CameraAttributesPractical.new()
	a.dof_blur_far_enabled = true
	a.dof_blur_near_enabled = true
	camera.attributes = a
	_set_focus(_focus)


## A lens focused at `d` metres: sharp from about two thirds of it to half
## as far again, softening either side, more so for a close subject.
func _set_focus(d: float) -> void:
	var a := camera.attributes as CameraAttributesPractical
	if a == null:
		return
	a.dof_blur_far_distance = d * 1.35 + 1.0
	a.dof_blur_far_transition = d * 1.5 + 2.0
	a.dof_blur_near_distance = maxf(d * 0.6, 0.05)
	a.dof_blur_near_transition = maxf(d * 0.4, 0.05)
	a.dof_blur_amount = clampf(0.16 - d * 0.0006, 0.06, 0.16)


## Saves the frame without the bar: to the user folder's photos/ on the
## desktop, or as a download in a browser.
func save_photo() -> void:
	if _saving:
		return
	_saving = true
	var bar_was := _bar.visible
	_bar.visible = false
	_info.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_bar.visible = bar_was
	_info.visible = true
	_saving = false
	if img == null or img.is_empty():
		_show_info("Couldn't take the picture")
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	var file := "lidarlinks-%s.png" % stamp
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(img.save_png_to_buffer(), file, "image/png")
		_show_info("Saved %s to your downloads" % file)
		return
	DirAccess.make_dir_recursive_absolute("user://photos")
	var path := "user://photos/" + file
	if img.save_png(path) != OK:
		_show_info("Couldn't save the picture")
		return
	_show_info("Saved to %s" % ProjectSettings.globalize_path(path))


func _show_info(note := "") -> void:
	if _info == null:
		return
	var time_name: String = GraphicsSettings.TIME_NAMES[time_of_day] if time_of_day < GraphicsSettings.TIME_NAMES.size() else ""
	var lines := "Photo mode · %s" % time_name
	if _dof:
		lines += " · depth of field"
	if note != "":
		lines += "\n" + note
	_info.text = lines


func _build_ui() -> void:
	if _layer != null:
		return
	_layer = CanvasLayer.new()
	_layer.name = "PhotoModeUI"
	_layer.layer = 20
	add_child(_layer)
	_info = Label.new()
	_info.position = Vector2(24, 18)
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_info.add_theme_constant_override("shadow_offset_x", 1)
	_info.add_theme_constant_override("shadow_offset_y", 1)
	_layer.add_child(_info)
	_bar = PanelContainer.new()
	MenuStyle.panel(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_bar.add_child(row)
	_bar_button(row, "◀ Time", func() -> void: _step_time(-1))
	_bar_button(row, "Time ▶", func() -> void: _step_time(1))
	_bar_button(row, "Focus", _toggle_dof)
	_bar_button(row, "Save photo", save_photo)
	_bar_button(row, "Done", close)
	var help := Label.new()
	help.text = "Drag to look · WASD move · Q/E down/up · wheel zoom · T time · F focus · H hide · Enter save"
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.75)
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not DisplayServer.is_touchscreen_available():
		row.add_child(help)
	_layer.add_child(_bar)


func _bar_button(row: HBoxContainer, text: String, action: Callable) -> void:
	var b := MenuStyle.button(text)
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	row.add_child(b)
