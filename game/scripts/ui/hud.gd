class_name Hud
extends Control
## On-screen text: hole and shot info, messages, controls, and the meter.
## In the Broadcast presentation the TV graphics (BroadcastOverlay) take the
## place of the info text and bars, and messages become captions.

var info: Label
var message: Label
## Settings > Captions: what the golfer and the crowd say, in brackets.
var sound_caption: Label
## Broadcast and Tour fold the key hints away after the first hole, as TV
## style golf games do: a small "F1: controls" stays in their place.
var hints_folded := false
var hint_tab: Label
var _sound_caption_time := 0.0
var hint: Label
var _hint_relabelled := ""
var meter: SwingMeter
var mouse_swing: MouseSwingControl
## The first time with the mouse (finger, stick) swing: how it goes.
var swing_guide: SwingGuide
## The mouse swing's tall meter is up (aiming with it, or swinging): the
## three-click meter steps aside and "View target" takes its place.
var mouse_meter := false:
	set(v):
		if v != mouse_meter:
			mouse_meter = v
			_place_target_button()
## Aim, club and menu buttons on a touch screen (hidden elsewhere).
var touch_pad: TouchPad
var swing_button: TouchPad.SwingButton
## "View target" (TargetView), just above the swing meter.
var target_button: TargetButton
var wind: WindIndicator
var spin: SpinBall
var scorecard: ScorecardPanel
var hand_over: HandOverPanel
## With the player's own interface art: one chrome bar per line of `info`.
var art: HudArt
var _bars: Array[InfoBar] = []
## With the player's own interface art: the PowerStroke panel and swing
## gizmo (bottom left), and the wind, elevation and lie windows (top right).
var shot_panel: ShotPanel
var windows: ShotWindows
var overlay: BroadcastOverlay
## The aim point and carry drawn over the picture (main._update_reticle).
var aim_reticle: AimReticle
var tour: TourGraphics
var broadcast := false
## BIRDIE, EAGLE, CHIP-IN, PURE: the big word for a good moment.
var badge: ScoreBadge

var _message_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	info = _label(20)
	info.position = Vector2(16, 12)
	add_child(info)

	message = _label(28)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(message, Control.PRESET_CENTER_TOP, Rect2(-400, 70, 800, 90))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)

	badge = ScoreBadge.new()
	add_child(badge)

	sound_caption = _label(20)
	sound_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(sound_caption, Control.PRESET_CENTER_BOTTOM, Rect2(-300, -150, 600, 30))
	add_child(sound_caption)

	hint = _label(16)
	_place(hint, Control.PRESET_BOTTOM_LEFT, Rect2(16, -34, 900, 26))
	add_child(hint)
	hint_tab = _label(13)
	hint_tab.text = "F1: controls"
	hint_tab.modulate = Color(1, 1, 1, 0.7)
	hint_tab.visible = false
	add_child(hint_tab)

	wind = WindIndicator.new()
	_place(wind, Control.PRESET_TOP_RIGHT, Rect2(-106, 12, 90, 112))
	add_child(wind)

	spin = SpinBall.new()
	spin.visible = false
	add_child(spin)
	_place_spin()

	meter = SwingMeter.new()
	_place(meter, Control.PRESET_BOTTOM_RIGHT, Rect2(-240, -240, 220, 220))
	add_child(meter)
	target_button = TargetButton.new()
	target_button.visible = false
	add_child(target_button)
	_place_target_button()

	mouse_swing = MouseSwingControl.new()
	add_child(mouse_swing)
	swing_guide = SwingGuide.new()
	add_child(swing_guide)

	touch_pad = TouchPad.new()
	var pad := Vector2(TouchPad.SIZE * 2 + TouchPad.GAP, TouchPad.SIZE * 3 + TouchPad.GAP * 2)
	_place(touch_pad, Control.PRESET_CENTER_LEFT, Rect2(16, -pad.y * 0.5, pad.x, pad.y))
	touch_pad.visible = DisplayServer.is_touchscreen_available()
	add_child(touch_pad)
	# Right side, half way up: room below it to drag back for the swipe
	# swing, clear of the wind (top) and the meter (bottom).
	swing_button = TouchPad.SwingButton.new()
	var d := TouchPad.SwingButton.DIAMETER
	_place(swing_button, Control.PRESET_CENTER_RIGHT, Rect2(-d - 24.0, -d * 0.5 - 20.0, d, d))
	swing_button.visible = false
	add_child(swing_button)

	overlay = BroadcastOverlay.new()
	overlay.visible = false
	add_child(overlay)
	move_child(overlay, 0)
	tour = TourGraphics.new()
	tour.visible = false
	add_child(tour)
	move_child(tour, 1)
	aim_reticle = AimReticle.new()
	add_child(aim_reticle)
	move_child(aim_reticle, 0)

	# Under the scorecard, so Tab still shows the card while it is up.
	hand_over = HandOverPanel.new()
	add_child(hand_over)

	scorecard = ScorecardPanel.new()
	scorecard.visible = false
	add_child(scorecard)


## Switches to the original's interface pieces from the player's files.
func use_art(hud_art: HudArt) -> void:
	art = hud_art
	if art == null:
		return
	info.visible = false
	meter.art = art
	_place_meter()
	shot_panel = ShotPanel.new(art)
	var panel := shot_panel.wanted_size()
	_place(shot_panel, Control.PRESET_BOTTOM_LEFT, Rect2(12, -panel.y - 40.0, panel.x, panel.y))
	add_child(shot_panel)
	move_child(shot_panel, 0)
	windows = ShotWindows.new(art)
	var box := ShotWindows.wanted_size()
	_place(windows, Control.PRESET_TOP_RIGHT, Rect2(-box.x - 12.0, 12, box.x, box.y))
	add_child(windows)
	move_child(windows, 0)
	_show_classic()
	_place_spin()


## The club, its reach, the aim point's height above the ball and the lie,
## for the original's panels (nothing without the player's art).
func show_shot(club: Club, reach_text: String, rise_m: float, lie_name: String, lie_power: float) -> void:
	if art == null:
		return
	shot_panel.show_club(HudArt.club_kind(club.full_name, club.is_putter), club.full_name, reach_text)
	windows.show_shot(rise_m, lie_name, lie_power)


## The wind, on the arrow or in the original's wind window.
func show_wind(w: Wind, aim_deg: float) -> void:
	wind.show_wind(w, aim_deg)
	if windows != null:
		windows.show_wind(w, aim_deg)


func _show_classic() -> void:
	var classic := art != null and not broadcast
	if shot_panel != null:
		shot_panel.visible = classic
		windows.visible = classic
	wind.visible = (windows == null or broadcast) and not tour.visible  # Tour has its own dial


## Switches between the Classic interface and the broadcast graphics.
func set_broadcast(on: bool, tour_on := false) -> void:
	broadcast = on
	overlay.visible = on
	overlay.tour = on and tour_on
	tour.visible = on and tour_on
	info.visible = not on and art == null
	for bar in _bars:
		bar.visible = false
	_show_classic()
	if on:
		message.text = ""
	else:
		overlay.caption("")
	# The wind sits below the LIVE bug, and the hints above the ticker.
	_place(wind, Control.PRESET_TOP_RIGHT, Rect2(-106, 50 if on else 12, 90, 112))
	# Tour's shot-data bar and putt read run along the bottom: the hints sit
	# above them, smaller, clear of the meter.
	hint.add_theme_font_size_override("font_size", 14 if tour.visible else 16)
	if tour.visible:
		_place(hint, Control.PRESET_BOTTOM_LEFT, Rect2(TourGraphics.RAIL_W + 24.0, -176, 760, 22))
	else:
		# Across the screen, wrapping upwards onto a second line rather than
		# running off the right edge on a narrower screen (an iPad).
		_place(hint, Control.PRESET_BOTTOM_WIDE, Rect2(16, -62 if on else -34, 0, 26))
		# Classic's meter sits in the bottom right corner: stop short of it.
		hint.offset_right = -16.0 if on else -260.0
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF if tour.visible else TextServer.AUTOWRAP_WORD_SMART
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_place(hint_tab, Control.PRESET_BOTTOM_LEFT, Rect2(hint.offset_left, hint.offset_top + 6, 200, 20))
	fold_hints(hints_folded)
	meter.modern = on
	wind.modern = on
	spin.modern = on
	_place_meter()
	_place_spin()


## The spin ball: top right, under the wind (or the original's windows);
## in Tour, left of the hole map.
func _place_spin() -> void:
	var w := 140.0
	var h := 112.0
	if tour != null and tour.visible:
		var map_w := HoleMap.WIDTH * TourGraphics.MAP_SCALE
		_place(spin, Control.PRESET_TOP_RIGHT, Rect2(-map_w - 24.0 - w - 12.0, 58, w, h))
	elif windows != null and windows.visible:
		_place(spin, Control.PRESET_TOP_RIGHT, Rect2(-w - 32.0, 24.0 + ShotWindows.wanted_size().y, w, h))
	else:
		_place(spin, Control.PRESET_TOP_RIGHT, Rect2(-w - 6.0, (50.0 if broadcast else 12.0) + 124.0, w, h))


## The meter: the modern bar bottom right, above the ticker (or above
## Tour's shot-data bar and hints); the original's bar centred at the
## bottom; or the arc bottom right.
func _place_meter() -> void:
	var want := meter.wanted_size()
	meter.custom_minimum_size = want
	if meter.modern:
		var lift := 200.0 if tour.visible else 100.0
		_place(meter, Control.PRESET_BOTTOM_RIGHT, Rect2(-want.x - 24.0, -want.y - lift, want.x, want.y))
	elif art == null or tour.visible:
		if art == null:
			want = Vector2(220, 220)
			meter.custom_minimum_size = want
		_place(meter, Control.PRESET_BOTTOM_RIGHT, Rect2(-want.x - 20.0, -want.y - 20.0, want.x, want.y))
	else:
		_place(meter, Control.PRESET_CENTER_BOTTOM, Rect2(-want.x * 0.5, -want.y - 44.0, want.x, want.y))
	meter.queue_redraw()
	_place_target_button()


## "View target" sits just above the meter, lined up with its right edge;
## over the original's centred meter, in the bottom right corner instead.
## (Clear of the touch swing button, half way up the right side, and the
## wind and spin ball at the top.)
func _place_target_button() -> void:
	if target_button == null:
		return
	var s := TargetButton.SIZE
	if mouse_meter and meter.anchor_left == 1.0:
		# The three-click meter is away: down to where it sat.
		_place(target_button, Control.PRESET_BOTTOM_RIGHT, Rect2(meter.offset_right - s.x, meter.offset_bottom - s.y, s.x, s.y))
	elif meter.anchor_left == 1.0:
		_place(target_button, Control.PRESET_BOTTOM_RIGHT, Rect2(meter.offset_right - s.x, meter.offset_top - s.y - 12.0, s.x, s.y))
	else:
		_place(target_button, Control.PRESET_BOTTOM_RIGHT, Rect2(-s.x - 24.0, -s.y - 44.0, s.x, s.y))


func _process(delta: float) -> void:
	# The hints name the player's own keys (Settings > Keys).
	if hint.text != _hint_relabelled:
		hint.text = KeyRemap.relabel(hint.text)
		_hint_relabelled = hint.text
	if art != null and not broadcast:
		_update_bars()
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message.text = ""
	if _sound_caption_time > 0.0:
		_sound_caption_time -= delta
		if _sound_caption_time <= 0.0:
			sound_caption.text = ""
	# Keep the card centred as its contents change size.
	# It also shrinks back to fit (a PanelContainer keeps the size of its
	# tallest contents, which left an empty band under a shorter card), and
	# moves up clear of a Broadcast caption, such as the end-of-round
	# result, which it used to cover.
	if scorecard.visible:
		scorecard.reset_size()
		var at := (size - scorecard.size) * 0.5
		if broadcast:
			at.y = maxf(8.0, minf(at.y, overlay.caption_top() - scorecard.size.y - 12.0))
		scorecard.position = at
	_clear_hints()
	_fold_detail()


## Broadcast folds the shot detail away a few seconds into each shot
## (BroadcastOverlay.detail): the caddie's read and the key hint fade out,
## and the spin ball dims but can still be clicked.
func _fold_detail() -> void:
	var k := overlay.detail() if broadcast else 1.0
	for c in get_children():
		if c is CaddieNote:
			(c as Control).modulate.a = k
	spin.modulate.a = lerpf(0.4, 1.0, k)
	hint_tab.modulate.a = 0.7 * k


## The key hints wrap onto a second line on a narrower screen (anything
## under ~1400 px wide, an iPad), growing upwards: the caddie's note and
## Broadcast's lower third sit above wherever their top edge is, rather than
## where one line would put it, so the hints don't run through them (and
## the lower third above the caddie's note too).
func _clear_hints() -> void:
	var top := size.y
	if hint.visible and not hint.text.is_empty():
		top = hint.position.y
	elif hint_tab.visible:
		top = hint_tab.position.y
	var above := top
	for c in get_children():
		if c is CaddieNote:
			var note := c as Control
			note.offset_bottom = minf(CaddieNote.BOTTOM, top - size.y - 6.0)
			if note.visible:
				above = minf(above, note.position.y)
	overlay.hints_top = above


## Shows a message; seconds <= 0 keeps it until the next one.
func show_message(text: String, seconds := 0.0) -> void:
	if broadcast:
		overlay.caption(text, seconds)
		message.text = ""
		_message_time = 0.0
		return
	message.text = text
	_message_time = seconds


## Folds the key hints away (or brings them back).
func fold_hints(folded: bool) -> void:
	hints_folded = folded
	hint.visible = not folded
	hint_tab.visible = folded


## Shows a caption for a sound, such as "[Golfer: Great Shot]".
func show_sound_caption(text: String, seconds := 2.5) -> void:
	sound_caption.text = text
	_sound_caption_time = seconds


## Anchors `c` to a corner or edge, then offsets it by `r` from that anchor.
## Where the mouse swing's meter can go: a column down the right of the
## screen clear of the wind, the spin ball, Tour's hole map and
## leaderboard, the caddie, "View target" and the rest; down the left edge
## when the right has too little room, and only then further in.
func mouse_meter_room() -> Rect2:
	var vs := get_viewport_rect().size
	var top := 50.0 if broadcast else 12.0
	var bottom := vs.y - (200.0 if tour.visible else (100.0 if broadcast else 20.0))
	var blocks: Array[Rect2] = []
	for c: Control in [wind, spin, target_button, swing_button, windows, shot_panel, meter, touch_pad]:
		if c != null and c.is_visible_in_tree():
			blocks.append(c.get_global_rect())
	for c in get_children():
		if c is CaddieNote and (c as Control).is_visible_in_tree():
			blocks.append((c as Control).get_global_rect())
	if tour.visible:
		for r: Rect2 in [tour.map_rect(), tour.rail_rect()]:
			if r.has_area():
				blocks.append(Rect2(tour.get_global_transform() * r.position, r.size))
	return room_for(vs, top, bottom, blocks)


## The column (see mouse_meter_room) on a `screen` this size between `top`
## and `bottom`, clear of `blocks`.
static func room_for(screen: Vector2, top: float, bottom: float, blocks: Array[Rect2]) -> Rect2:
	var want := screen.y * MouseSwingControl.METER_SHARE
	var w := MouseSwingControl.column_width(want)
	var need := minf(want, (bottom - top) * 0.8) * 0.65 + MouseSwingControl.LABEL_H
	var right_gap := _gap_down(Rect2(screen.x - 16.0 - w, top, w, bottom - top), blocks)
	if right_gap.size.y >= need:
		return right_gap
	var left_gap := _gap_down(Rect2(16.0, top, w, bottom - top), blocks)
	if left_gap.size.y >= need:
		return left_gap
	var best := right_gap if right_gap.size.y >= left_gap.size.y else left_gap
	var right := screen.x - 16.0
	for attempt in 4:
		var left := right
		for b in blocks:
			if b.position.x < right and b.end.x > right - w and b.end.y > top and b.position.y < bottom:
				left = minf(left, b.position.x)
		if left >= right:
			break
		right = left - 12.0
		if right - w < screen.x * 0.4:
			break
		var gap := _gap_down(Rect2(right - w, top, w, bottom - top), blocks)
		if gap.size.y >= need:
			return gap
		if gap.size.y > best.size.y:
			best = gap
	return best


## The tallest stretch of `col` that none of `blocks` covers.
static func _gap_down(col: Rect2, blocks: Array[Rect2]) -> Rect2:
	var in_way: Array[Rect2] = []
	for b in blocks:
		if b.position.x < col.end.x and b.end.x > col.position.x and b.end.y > col.position.y and b.position.y < col.end.y:
			in_way.append(b)
	in_way.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y < b.position.y)
	var y := col.position.y
	var gap := Rect2()
	for b in in_way:
		if b.position.y - y > gap.size.y:
			gap = Rect2(col.position.x, y, col.size.x, b.position.y - y)
		y = maxf(y, b.end.y)
	if col.end.y - y > gap.size.y:
		gap = Rect2(col.position.x, y, col.size.x, col.end.y - y)
	return gap.grow_individual(0, -8.0, 0, -8.0)


func _place(c: Control, preset: Control.LayoutPreset, r: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.position.x + r.size.x
	c.offset_bottom = r.position.y + r.size.y


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _update_bars() -> void:
	var lines := info.text.split("\n", false)
	while _bars.size() < lines.size():
		var bar := InfoBar.new(art)
		bar.position = Vector2(8, 6 + _bars.size() * (bar.size.y - 10.0))
		add_child(bar)
		move_child(bar, 0)
		_bars.append(bar)
	for i in _bars.size():
		_bars[i].visible = i < lines.size()
		if i < lines.size():
			_bars[i].text = lines[i].strip_edges()
