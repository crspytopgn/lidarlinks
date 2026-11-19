class_name CoursesPanel
extends PanelContainer
## The "Courses" page: every course the game can play, what it is, and
## Add, Delete, Hide and Update (CourseLibrary, RealCourseUpdate). Delete and
## Update ask once more on the same button. Built-in courses come with the
## game and update with it; the player's Links 2003 courses are hidden from
## the course lists, never deleted. See docs/course-library.md.

signal back_pressed
## Browser: pick a Links course's .zip or .crz (the boot screen's picker).
signal add_links_pressed
## Browser: remove an added Links course (boot asks WebGameFiles).
signal remove_web_pressed(rel: String)
## The course list changed (added, deleted, hidden, updated).
signal changed

var _list: VBoxContainer
var _status: Label
var _back: Button
var _cancel: Button
var _add: Button
var _add_links: Button
var _files: DesignerFiles
var _updater: RealCourseUpdate
var _game_courses := PackedStringArray()
var _web_added := PackedStringArray()
var _confirm := ""  ## "delete:<path>" or "update:<path>" pressed once
var _web := false

## Each row's course picture.
const ROW_PICTURE := Vector2(128, 72)


func _ready() -> void:
	MenuStyle.panel(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(760, 0)
	add_child(box)
	box.add_child(MenuStyle.heading("Courses", 30))
	var help := Label.new()
	help.text = "Every course you can play. Add course files, delete the ones you no longer want, and Update a real course to rebuild it with the newest course builder. Built-in courses update with the game."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 15)
	help.modulate = Color(1, 1, 1, 0.75)
	box.add_child(help)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", MenuStyle.ACCENT)
	_status.visible = false
	box.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_add = MenuStyle.button("Add a course...")
	_add.pressed.connect(_on_add)
	buttons.add_child(_add)
	_add_links = MenuStyle.button("Add a Links course (.zip, .crz)...")
	_add_links.pressed.connect(add_links_pressed.emit)
	buttons.add_child(_add_links)
	_cancel = MenuStyle.button("Cancel update")
	_cancel.visible = false
	_cancel.pressed.connect(func() -> void:
		_cancel.text = "Cancelling..."
		_cancel.disabled = true
		_updater.cancel())
	buttons.add_child(_cancel)
	_back = MenuStyle.button("Back")
	_back.pressed.connect(func() -> void:
		if not _updater.busy:
			back_pressed.emit())
	buttons.add_child(_back)

	_files = DesignerFiles.new()
	_files.imported.connect(_on_imported)
	add_child(_files)
	_updater = RealCourseUpdate.new()
	_updater.progress.connect(func(_t: String) -> void: _show_update_progress())
	_updater.finished.connect(_on_updated)
	add_child(_updater)
	visible = false


## Shows the page. `game_courses`: the game's course files (desktop paths or
## the browser's stored paths); `web_added`: those the player added in the
## browser. `web`: the browser build, which also offers Add a Links course.
func open(game_courses: PackedStringArray, web_added := PackedStringArray(), web := false) -> void:
	_game_courses = game_courses
	_web_added = web_added
	_web = web
	_confirm = ""
	_add.text = "Add a course file (.olc)..." if web else "Add a course..."
	_add_links.visible = web
	_fill()
	visible = true
	_back.grab_focus.call_deferred()


func close() -> void:
	visible = false


## The game's course files changed (browser add or remove).
func refresh(game_courses: PackedStringArray, web_added := PackedStringArray(), message := "") -> void:
	_game_courses = game_courses
	_web_added = web_added
	_confirm = ""
	_fill()
	if not message.is_empty():
		_set_status(message)


func busy() -> bool:
	return _updater.busy


func entries() -> Array[Dictionary]:
	return CourseLibrary.entries(_game_courses + CourseLibrary.added_courses(), _web_added)


func _fill() -> void:
	for child in _list.get_children():
		child.queue_free()
	for e in entries():
		_list.add_child(_row(e))


func _row(e: Dictionary) -> Control:
	var path: String = e["path"]
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	row.add_child(top)
	var title := Label.new()
	title.text = str(e["name"])
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_font_override("font", GlassTheme.font(600))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if e["hidden"]:
		title.modulate = Color(1, 1, 1, 0.5)
	top.add_child(title)
	var kind := Label.new()
	var kind_text: String = CourseLibrary.KIND_LABELS[e["kind"]]
	if int(e["holes"]) > 0:
		kind_text += "   %d holes" % int(e["holes"])
	if e["hidden"]:
		kind_text += "   hidden"
	kind.text = kind_text
	kind.add_theme_font_size_override("font_size", 14)
	kind.modulate = Color(1, 1, 1, 0.7)
	top.add_child(kind)
	if e["updatable"]:
		var update := Button.new()
		update.text = "Sure? Update" if _confirm == "update:" + path else "Update"
		update.tooltip_text = "Rebuilds the course from the map with the newest builder. Changes made in the designer are replaced."
		update.disabled = _updater.busy
		update.pressed.connect(_on_update.bind(path))
		top.add_child(update)
	if e["hideable"]:
		var hide_button := Button.new()
		hide_button.text = "Show" if e["hidden"] else "Hide"
		hide_button.disabled = _updater.busy
		hide_button.pressed.connect(_on_hide.bind(path, not e["hidden"]))
		top.add_child(hide_button)
	if e["deletable"]:
		var delete := Button.new()
		delete.text = "Sure? Delete" if _confirm == "delete:" + path else "Delete"
		delete.disabled = _updater.busy
		delete.pressed.connect(_on_delete.bind(path))
		top.add_child(delete)
	var note_text: String = e["note"]
	if _confirm == "update:" + path:
		note_text = "Press again to rebuild it from the map with the newest builder. Changes you made in the designer will be replaced."
	elif _confirm == "delete:" + path:
		note_text = "Press again to delete it for good."
	if not note_text.is_empty():
		var note := Label.new()
		note.text = note_text
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 13)
		note.modulate = Color(1, 1, 1, 0.6)
		if _confirm.ends_with(":" + path):
			note.modulate = MenuStyle.WARNING
		row.add_child(note)
	# The course's picture at the left of its row.
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	var pic := CoursePicture.new(ROW_PICTURE)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.show_course(path)
	if e["hidden"]:
		pic.modulate = Color(1, 1, 1, 0.5)
	line.add_child(pic)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(row)
	return line


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()


func _on_delete(path: String) -> void:
	if _confirm != "delete:" + path:
		_confirm = "delete:" + path
		_fill()
		return
	_confirm = ""
	var name := CourseFiles.display_name(path)
	if _web_added.has(path):
		remove_web_pressed.emit(path)
		return
	var err := CourseLibrary.delete_course(path)
	if err == OK:
		CoursePictures.forget(path)
	if CourseDesigner.last_path == path:
		CourseDesigner.last_path = ""
	_set_status("Deleted %s." % name if err == OK else "Couldn't delete %s (%s)." % [name, error_string(err)])
	_fill()
	changed.emit()


func _on_hide(path: String, hide_it: bool) -> void:
	CourseLibrary.set_hidden(path, hide_it)
	_confirm = ""
	_set_status(("%s is hidden from the course lists." if hide_it else "%s is back on the course lists.") % path.get_file().get_basename())
	_fill()
	changed.emit()


func _on_update(path: String) -> void:
	if _updater.busy:
		return
	if _confirm != "update:" + path:
		_confirm = "update:" + path
		_fill()
		return
	_confirm = ""
	_cancel.text = "Cancel update"
	_cancel.disabled = false
	_cancel.visible = true
	set_process(true)
	_updater.run(path)
	_fill()


## The step under way and the time taken, kept ticking while it waits.
func _process(_delta: float) -> void:
	if _updater.busy:
		_show_update_progress()
	else:
		set_process(false)


func _show_update_progress() -> void:
	var secs := floori((Time.get_ticks_msec() - _updater.started_ms) / 1000.0)
	_set_status("%s  %d:%02d. Big courses take a few minutes; Cancel update stops it and leaves the course as it was." % [
		_updater.step if not _updater.step.is_empty() else "Starting...", floori(secs / 60.0), secs % 60])


func _on_updated(_ok: bool, text: String) -> void:
	set_process(false)
	_cancel.visible = false
	_set_status(text)
	_fill()
	changed.emit()


func _on_add() -> void:
	if _web:
		_files.import_file()
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.title = "Add courses"
	dlg.filters = PackedStringArray(["*.olc, *.crz, *.rng, *.zip ; Courses"] + CourseLibrary.ADD_FILTERS)
	dlg.files_selected.connect(_on_files_chosen)
	dlg.close_requested.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered_ratio(0.6)


func _on_files_chosen(paths: PackedStringArray) -> void:
	var lines: Array[String] = []
	for p in paths:
		lines.append(str(CourseLibrary.add_file(p)["message"]))
	_set_status(" ".join(lines))
	_fill()
	changed.emit()


## Browser: an .olc picked with the browser's file picker.
func _on_imported(text: String, file_name: String) -> void:
	_set_status(str(CourseLibrary.add_design(text.to_utf8_buffer(), file_name)["message"]))
	_fill()
	changed.emit()
