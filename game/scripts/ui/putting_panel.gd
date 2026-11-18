class_name PuttingPanel
extends PanelContainer
## The panel on the right while putting: what the green reads like (its
## speed, the slope under the ball, the read view) and, on the practice
## green, the drill and buttons for everything the keys do, so it works
## with a mouse or a finger too.

signal action(id: StringName)

## Button id, label, key shown in the tooltip.
const PRACTICE_BUTTONS := [
	[&"new_spot", "New spot", "N"], [&"closer", "- ft", "["], [&"further", "+ ft", "]"],
	[&"slope", "Slope", "L"], [&"drill", "Drill", "P"], [&"next_cup", "Next cup", "T"],
	[&"next_green", "Next green", "H"],
]
const WIDTH := 470.0
const READ_BUTTON := [&"read", "Read the green", "V"]
## Lines "Key: value" that show as a read-out (short caps key, then the
## value) instead of sentences, as TV and console golf show a green read.
const ROWS := {"Greens": "GREENS", "Slope at the ball": "SLOPE", "Putt": "PUTT", "View": "VIEW"}
const GOLD := Color(0.914, 0.78, 0.4)

var label: Label
var _head: Label
var _rows: GridContainer
var _buttons: HFlowContainer
var _practice_buttons: Array[Button] = []
var _read: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	Glass.apply(self, 16, 12.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_head = Label.new()
	_head.text = "GREEN READ"
	_head.add_theme_font_override("font", GlassTheme.display_font(700))
	_head.add_theme_font_size_override("font_size", 15)
	_head.add_theme_color_override("font_color", GOLD)
	box.add_child(_head)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 14)
	_rows.add_theme_constant_override("v_separation", 4)
	box.add_child(_rows)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 3)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	label.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	_buttons = HFlowContainer.new()
	_buttons.add_theme_constant_override("h_separation", 6)
	_buttons.add_theme_constant_override("v_separation", 6)
	box.add_child(_buttons)
	for b: Array in PRACTICE_BUTTONS:
		_practice_buttons.append(_button(b))
	_read = _button(READ_BUTTON)
	visible = false


func _button(spec: Array) -> Button:
	var b := Button.new()
	b.text = spec[1]
	b.tooltip_text = "Key: %s" % spec[2]
	b.focus_mode = Control.FOCUS_NONE  # Space swings; it mustn't press these
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(0, 32)
	var id: StringName = spec[0]
	b.pressed.connect(func() -> void: action.emit(id))
	_buttons.add_child(b)
	return b


## Shows `text`, the practice buttons when `practice`, and the read button
## when `can_read`. Hidden when there's nothing to show.
func show_panel(text: String, practice: bool, can_read: bool) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var rest: Array[String] = []
	for line in text.split("\n"):
		var at := line.find(": ")
		var key := line.substr(0, at) if at > 0 else ""
		if ROWS.has(key):
			_row(ROWS[key], line.substr(at + 2))
		else:
			rest.append(line)
	label.text = "\n".join(rest)
	label.visible = not label.text.is_empty()
	_head.visible = _rows.get_child_count() > 0
	_rows.visible = _head.visible
	for b in _practice_buttons:
		b.visible = practice
	_read.visible = can_read
	_buttons.visible = practice or can_read
	visible = not text.is_empty() or _buttons.visible


func _row(key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	k.add_theme_font_override("font", GlassTheme.display_font(600))
	k.add_theme_font_size_override("font_size", 15)
	k.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_rows.add_child(k)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 16)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size.x = WIDTH - 110.0
	_rows.add_child(v)
