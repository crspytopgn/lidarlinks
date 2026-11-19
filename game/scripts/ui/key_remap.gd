class_name KeyRemap
extends Node
## Settings > Keys: the player's own keys for the round's controls. The game
## still reads its usual keys (Space, the arrows, Q/E/W/S...): this node sits
## last under the root, so it sees each key first, and turns the key the
## player chose back into the usual one. Choosing a key that already does
## something swaps the two, so every key still does exactly one thing.
## Nothing is changed while a text box has the focus, so typing a name
## still types what is pressed.

const SECTION := "keys"
## The controls that can be moved: their name and usual key.
const ACTIONS: Array = [
	["Swing (3-click meter)", KEY_SPACE],
	["Aim left", KEY_LEFT],
	["Aim right", KEY_RIGHT],
	["Longer club", KEY_UP],
	["Shorter club", KEY_DOWN],
	["Spin: draw", KEY_Q],
	["Spin: fade", KEY_E],
	["Spin: high", KEY_W],
	["Spin: low", KEY_S],
	["View target", KEY_Y],
	["Drop (unplayable)", KEY_D],
	["Free drop", KEY_F],
	["Mulligan", KEY_U],
	["Replay", KEY_R],
	["Scorecard", KEY_TAB],
	["Shot details", KEY_I],
	["Mouse swing or 3-click", KEY_K],
	["Next hole (practice)", KEY_N],
	["Last hole (practice)", KEY_B],
]

## The key pressed -> the usual key it stands for. Only keys that differ.
static var swaps := {}
## True while Settings > Keys waits for a key: keys pass unchanged.
static var capturing := false
static var _node: KeyRemap


## Adds the remapping node under the root once and loads the player's keys.
static func install(tree: SceneTree, path := GraphicsSettings.PATH) -> void:
	load_keys(path)
	if _node != null and is_instance_valid(_node):
		return
	_node = KeyRemap.new()
	_node.name = "KeyRemap"
	tree.root.add_child.call_deferred(_node)


static func load_keys(path := GraphicsSettings.PATH) -> void:
	swaps.clear()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not cfg.has_section(SECTION):
		return
	for k: String in cfg.get_section_keys(SECTION):
		var from := int(k)
		var to := int(cfg.get_value(SECTION, k, from))
		if from > 0 and to > 0 and from != to:
			swaps[from] = to


static func save_keys(path := GraphicsSettings.PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep the other sections
	if cfg.has_section(SECTION):
		cfg.erase_section(SECTION)
	for from: int in swaps:
		cfg.set_value(SECTION, str(from), swaps[from])
	cfg.save(path)


## The usual key `pressed` stands for.
static func translate(pressed: int) -> int:
	return int(swaps.get(pressed, pressed))


## The key the player presses for the control whose usual key is `usual`.
static func key_for(usual: int) -> int:
	for from: int in swaps:
		if swaps[from] == usual:
			return from
	return usual if not swaps.has(usual) else 0


## Makes `pressed` do what `usual` does; whatever `pressed` did moves to the
## key `usual` was on, so the two swap.
static func assign(usual: int, pressed: int) -> void:
	var old_key := key_for(usual)
	var displaced := translate(pressed)
	if old_key == pressed:
		return
	swaps[pressed] = usual
	if old_key != 0:
		swaps[old_key] = displaced
	for k: int in swaps.keys():
		if swaps[k] == k:
			swaps.erase(k)


static func reset() -> void:
	swaps.clear()


## True while the control whose usual key is `usual` is held: its chosen
## key, or (`action`) a game pad's button for it. Held keys are read from
## Input, which sees the keys as pressed, so they are looked up here.
static func held(usual: int, action := "") -> bool:
	if swaps.is_empty():
		return Input.is_key_pressed(usual as Key) or (not action.is_empty() and Input.is_action_pressed(action))
	var k := key_for(usual)
	if k != 0 and Input.is_key_pressed(k as Key):
		return true
	if action.is_empty():
		return false
	# The pad's buttons for the action, not its keyboard keys (moved).
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			for pad in Input.get_connected_joypads():
				if Input.is_joy_button_pressed(pad, (e as InputEventJoypadButton).button_index):
					return true
	return false


static func key_name(code: int) -> String:
	return "-" if code == 0 else OS.get_keycode_string(code)


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


## A new scene (or anything else under the root) would take the keys first:
## stay the last child.
func _on_node_added(node: Node) -> void:
	if node != self and node.get_parent() == get_parent():
		get_parent().move_child.call_deferred(self, -1)


func _input(event: InputEvent) -> void:
	if capturing or swaps.is_empty() or not (event is InputEventKey):
		return
	var vp := get_viewport()
	var focus: Control = vp.gui_get_focus_owner() if vp != null else null
	if focus is LineEdit or focus is TextEdit:
		return
	var key := event as InputEventKey
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	if swaps.has(code):
		var to: int = swaps[code]
		key.keycode = to as Key
		key.physical_keycode = to as Key
