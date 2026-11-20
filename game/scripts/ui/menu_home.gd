class_name MenuHome
extends ScrollContainer
## The main menu's home page: a course photo filling the screen, a big
## PLAY title, picture tiles for the ways to play, and a floating glass bar
## along the top with Players and Settings.
##
## Its glass is cheap enough for every device: the photo behind is still, so
## a tiny copy of it, made once, stands in for the blur. Each glass shape
## reads that copy once a pixel (no screen copy, no extra pass), in Forward+,
## Compatibility and the web alike.

const ART_DIR := "res://assets/ui/menu/"
## Menu items shown as picture tiles: label -> [picture, line under it].
const TILES := {
	"Play now": ["play", "Kettle Hollow, ready to go"],
	"Daily round": ["tournament", "Today's course, the same for everyone"],
	"Play a round": ["play", "Pick a course and tees"],
	"Resume round": ["play", "Carry on where you stopped"],
	"Play online": ["online", "Rounds and leaderboards"],
	"Tour event": ["tournament", "72 holes against the pros"],
	"Career": ["career", "Tours, cuts, prize money"],
	"Tournament": ["tournament", "Build your own event"],
	"Course designer": ["designer", "Make your own course"],
}
## Menu items that go in the top bar instead.
const NAV := ["Select golfer", "Courses", "Players", "Settings", "Quit"]
const GOLD := Color(0.914, 0.78, 0.4)
const TILE_SIZE := Vector2(212, 196)
const RADIUS := 22.0
## Glass showing round each tile's photo: a thin edge, not a coloured mat.
const FRAME := 3.0

const GLASS_SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D blurred : filter_linear, repeat_disable;
uniform vec2 cover_scale = vec2(1.0);
uniform vec2 box_size = vec2(100.0);
uniform float radius = 22.0;
uniform vec4 tint : source_color = vec4(0.05, 0.07, 0.06, 0.38);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 0.55);
uniform float rim_width = 1.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float box_sdf(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 h = box_size * 0.5;
	vec2 p = local - h;
	float r = min(radius, min(h.x, h.y));
	float d = box_sdf(p, h, r);
	float a = clamp(0.5 - d, 0.0, 1.0);
	if (a <= 0.0) {
		discard;
	}
	vec3 c = texture(blurred, (SCREEN_UV - 0.5) * cover_scale + 0.5).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(luma), c, 1.35);
	c = mix(c, tint.rgb, tint.a);
	// A sheen down from the top edge, and a rim lit from the top left.
	c += vec3(0.1) * (1.0 - smoothstep(0.0, 0.6, local.y / max(box_size.y, 1.0)));
	float rim = 1.0 - smoothstep(0.0, rim_width + 0.8, -d);
	vec2 n = normalize(p / max(h, vec2(1.0)) + vec2(0.0001));
	float facing = 0.4 + 0.6 * max(dot(n, normalize(vec2(-0.45, -1.0))), 0.0);
	c = mix(c, rim_color.rgb, clamp(rim * rim_color.a * facing, 0.0, 1.0));
	COLOR = vec4(c, a);
}
"""

## A rounded picture.
const PICTURE_SHADER := """
shader_type canvas_item;

uniform vec2 box_size = vec2(100.0);
uniform float radius = 16.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 h = box_size * 0.5;
	vec2 q = abs(local - h) - h + vec2(radius);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	vec4 c = texture(TEXTURE, UV);
	// Darker towards the bottom, where the label sits.
	c.rgb *= mix(1.0, 0.28, smoothstep(0.35, 1.0, UV.y));
	COLOR = vec4(c.rgb, c.a * clamp(0.5 - d, 0.0, 1.0));
}
"""

static var _glass_shader: Shader
static var _picture_shader: Shader
static var _art_cache := {}

## Where the caller puts the status line, progress bar, extra buttons and
## community links.
var info: VBoxContainer
var title: Label
var _tiles: GridContainer
var _extras: HFlowContainer
var _nav: HBoxContainer
var _blurred: Texture2D
var _photo_size := Vector2(1280, 720)
var _glass: Array[ShaderMaterial] = []
var _items: Array[RID] = []
var _page: VBoxContainer


func _init() -> void:
	name = "MenuHome"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# A console menu fits the screen; a scroll bar reads as a web page. It
	# still scrolls (wheel, touch, focus) on a very short window.
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 14)
	margin.add_child(_page)
	_page.add_child(_top_bar())
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.custom_minimum_size = Vector2(0, 24)
	_page.add_child(gap)
	var hero := VBoxContainer.new()
	hero.add_theme_constant_override("separation", 6)
	var hero_margin := MarginContainer.new()
	hero_margin.add_theme_constant_override("margin_left", 32)
	hero_margin.add_child(hero)
	_page.add_child(hero_margin)
	title = Label.new()
	title.text = "PLAY"
	title.add_theme_font_override("font", GlassTheme.display_font(700))
	title.add_theme_font_size_override("font_size", 112)
	title.add_theme_constant_override("line_spacing", -20)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	title.add_theme_constant_override("shadow_offset_y", 3)
	hero.add_child(title)
	info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	info.custom_minimum_size = Vector2(minf(720, 560), 0)
	info.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hero.add_child(info)
	_extras = HFlowContainer.new()
	_extras.add_theme_constant_override("h_separation", 10)
	_extras.add_theme_constant_override("v_separation", 10)
	hero.add_child(_extras)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 18)
	_page.add_child(gap2)
	# An even grid: one row up to four tiles, else two equal rows, so no
	# tile is left stretched alone on a row.
	_tiles = GridContainer.new()
	_tiles.add_theme_constant_override("h_separation", 18)
	_tiles.add_theme_constant_override("v_separation", 18)
	var tiles_margin := MarginContainer.new()
	tiles_margin.add_theme_constant_override("margin_left", 32)
	tiles_margin.add_theme_constant_override("margin_right", 32)
	tiles_margin.add_theme_constant_override("margin_top", 12)
	tiles_margin.add_child(_tiles)
	_page.add_child(tiles_margin)


## Small print under the tiles.
func add_footer(c: Control) -> void:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 32)
	m.add_child(c)
	_page.add_child(m)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


## The photo behind the menu, covering the screen with a dark wash where the
## type sits; also makes the glass's tiny copy of it.
func backdrop() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var photo := _art("hero")
	if photo == null:
		return root
	_photo_size = photo.get_size()
	var img := photo.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		img.resize(80, 45, Image.INTERPOLATE_CUBIC)
		_blurred = ImageTexture.create_from_image(img)
	var rect := TextureRect.new()
	rect.texture = photo
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)
	root.add_child(_wash(Vector2(0, 0.5), Vector2(0.7, 0.5), Color(0.02, 0.03, 0.03, 0.8)))
	root.add_child(_wash(Vector2(0.5, 1.0), Vector2(0.5, 0.42), Color(0.02, 0.03, 0.03, 0.85)))
	root.add_child(_wash(Vector2(0.5, 0.0), Vector2(0.5, 0.2), Color(0.02, 0.03, 0.03, 0.4)))
	return root


## Fills the page from the menu's items ([label, callable] pairs): picture
## tiles, top bar links and small glass buttons for the rest. Returns the
## button made for item `primary` (or null) so the caller can focus it.
func set_items(items: Array, primary: int) -> Button:
	for box: Control in [_tiles, _extras, _nav]:
		for child in box.get_children():
			child.queue_free()
	var focus: Button = null
	var n := 0
	for i in items.size():
		var item: Array = items[i]
		var label: String = item[0]
		var b: Button
		if TILES.has(label):
			b = _tile(label, TILES[label][0], TILES[label][1])
			_tiles.add_child(b)
			_enter(b, n)
			n += 1
			_tiles.columns = n if n <= 4 else ceili(n / 2.0)
		elif label in NAV:
			b = _nav_button(label)
			_nav.add_child(b)
		else:
			b = _pill(label)
			_extras.add_child(b)
		b.pressed.connect(item[1])
		if i == primary:
			focus = b
	_fit()
	return focus


# --- Pieces --------------------------------------------------------------------

func _top_bar() -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 58)
	_glass_under(bar, 29.0)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -18
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var icon := TextureRect.new()
	icon.texture = load("res://icon.png") if ResourceLoader.exists("res://icon.png") else null
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(34, 34)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var word := RichTextLabel.new()
	word.bbcode_enabled = true
	word.fit_content = true
	word.scroll_active = false
	word.autowrap_mode = TextServer.AUTOWRAP_OFF
	word.custom_minimum_size = Vector2(200, 0)
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	word.add_theme_font_override("normal_font", GlassTheme.font(600))
	word.add_theme_font_override("italics_font", GlassTheme.font(300))
	word.add_theme_font_size_override("normal_font_size", 20)
	word.add_theme_font_size_override("italics_font_size", 20)
	word.text = "Lidar[i][color=#ffffffbb]Links[/color][/i]"
	row.add_child(word)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spring)
	_nav = HBoxContainer.new()
	_nav.add_theme_constant_override("separation", 8)
	row.add_child(_nav)
	return bar


func _nav_button(label: String) -> Button:
	var b := Button.new()
	b.text = label.to_upper()
	b.flat = true
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", GlassTheme.display_font(600))
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_constant_override("outline_size", 0)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", GOLD)
	for state in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(1, 1, 1, 0.0 if state == "normal" else 0.1)
		s.set_corner_radius_all(18)
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.anti_aliasing = true
		b.add_theme_stylebox_override(state, s)
	return b


func _pill(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 42)
	b.add_theme_font_size_override("font_size", 15)
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0, 0, 0, 0)
	empty.set_corner_radius_all(21)
	empty.content_margin_left = 18
	empty.content_margin_right = 18
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, empty)
	var focus := empty.duplicate() as StyleBoxFlat
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("focus", focus)
	var mat := _glass_under(b, 21.0)
	b.mouse_entered.connect(func() -> void: mat.set_shader_parameter("tint", Color(0.12, 0.14, 0.13, 0.22)))
	b.mouse_exited.connect(func() -> void: mat.set_shader_parameter("tint", Color(0.05, 0.07, 0.06, 0.38)))
	return b


## A picture tile: the photo in a glass frame, its name in big condensed
## capitals and a line under it. Focus or hover lifts it and lights the rim
## gold.
func _tile(label: String, art: String, line: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = TILE_SIZE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = line
	var none := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, none)
	var mat := _glass_under(b, RADIUS)
	var pic := TextureRect.new()
	pic.texture = _art(art)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top"]:
		pic.set("offset_" + side, FRAME)
	for side in ["right", "bottom"]:
		pic.set("offset_" + side, -FRAME)
	if _picture_shader == null:
		_picture_shader = Shader.new()
		_picture_shader.code = PICTURE_SHADER
	var pm := ShaderMaterial.new()
	pm.shader = _picture_shader
	pm.set_shader_parameter("radius", RADIUS - FRAME)
	pic.material = pm
	pic.resized.connect(func() -> void: pm.set_shader_parameter("box_size", pic.size))
	b.add_child(pic)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	text.offset_left = 22
	text.offset_right = -16
	text.offset_bottom = -18
	text.grow_vertical = Control.GROW_DIRECTION_BEGIN
	text.add_theme_constant_override("separation", 0)
	b.add_child(text)
	var name_label := Label.new()
	name_label.text = label.to_upper()
	name_label.add_theme_font_override("font", GlassTheme.display_font(700))
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(name_label)
	var sub := Label.new()
	sub.text = line
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(sub)
	var lift := func(on: bool) -> void:
		mat.set_shader_parameter("rim_color", Color(GOLD, 0.95) if on else Color(1, 1, 1, 0.55))
		mat.set_shader_parameter("rim_width", 2.2 if on else 1.0)
		b.pivot_offset = b.size * 0.5
		var t := b.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "scale", Vector2.ONE * (1.035 if on else 1.0), 0.18)
	b.focus_entered.connect(lift.bind(true))
	b.focus_exited.connect(func() -> void: lift.call(b.is_hovered()))
	b.mouse_entered.connect(lift.bind(true))
	b.mouse_exited.connect(func() -> void: lift.call(b.has_focus()))
	return b


## Tiles rise in one after another when the page fills.
func _enter(c: Control, index: int) -> void:
	c.modulate.a = 0.0
	var t := c.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.05 * index)
	t.tween_property(c, "modulate:a", 1.0, 0.3)


## Glass drawn behind `c` (its own size, rounded by `radius`), without a
## node, so containers don't lay it out.
func _glass_under(c: Control, radius: float) -> ShaderMaterial:
	if _glass_shader == null:
		_glass_shader = Shader.new()
		_glass_shader.code = GLASS_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _glass_shader
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("blurred", _blurred)
	_glass.append(mat)
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, c.get_canvas_item())
	_items.append(item)
	RenderingServer.canvas_item_set_draw_behind_parent(item, true)
	RenderingServer.canvas_item_set_material(item, mat.get_rid())
	var redraw := func() -> void:
		RenderingServer.canvas_item_clear(item)
		mat.set_shader_parameter("box_size", c.size)
		RenderingServer.canvas_item_add_rect(item, Rect2(Vector2.ZERO, c.size), Color.WHITE)
	c.resized.connect(redraw)
	c.tree_exited.connect(func() -> void:
		if c.is_queued_for_deletion() and _items.has(item):
			RenderingServer.free_rid(item)
			_items.erase(item)
			_glass.erase(mat))
	redraw.call()
	_fit_one(mat)
	return mat


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for item in _items:
			RenderingServer.free_rid(item)
		_items.clear()


func _fit() -> void:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	_page.custom_minimum_size.y = vp.y - 42.0
	info.custom_minimum_size.x = minf(720.0, vp.x - 120.0)
	# Tiles share what the hero leaves, so the page fits without scrolling.
	var tiles := _tiles.get_children().filter(func(t: Node) -> bool: return not t.is_queued_for_deletion())
	var rows := 1 if tiles.size() <= 4 else 2
	title.add_theme_font_size_override("font_size", int(clampf(vp.y * 0.125, 76.0, 112.0)))
	var h := clampf((vp.y - 480.0) / rows - 18.0, 104.0, TILE_SIZE.y + 24.0)
	for t: Control in tiles:
		t.custom_minimum_size.y = h
	for mat in _glass:
		_fit_one(mat)


## The glass reads the tiny photo where the full one shows on screen
## (STRETCH_KEEP_ASPECT_COVERED, centred).
func _fit_one(mat: ShaderMaterial) -> void:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var s := maxf(vp.x / _photo_size.x, vp.y / _photo_size.y)
	mat.set_shader_parameter("cover_scale", vp / (_photo_size * s))
	if mat.get_shader_parameter("blurred") == null:
		mat.set_shader_parameter("blurred", _blurred)


## A menu photo. They are plain JPEG files (.oljpg, so Godot doesn't import
## them as lossless textures four times their size) read at runtime.
static func _art(art: String) -> Texture2D:
	if _art_cache.has(art):
		return _art_cache[art]
	var bytes := FileAccess.get_file_as_bytes(ART_DIR + art + ".oljpg")
	var img := Image.new()
	if bytes.is_empty() or img.load_jpg_from_buffer(bytes) != OK:
		return null
	_art_cache[art] = ImageTexture.create_from_image(img)
	return _art_cache[art]


## A dark wash from `from` fading out by `to` (UV in the screen).
static func _wash(from: Vector2, to: Vector2, col: Color) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([col, Color(col, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = from
	tex.fill_to = to
	tex.width = 64
	tex.height = 64
	var r := TextureRect.new()
	r.texture = tex
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
