class_name MenuSounds
extends Node
## Menu clicks and music from the player's own SOUNDS.LS
## (docs/formats/ls-archive.md): every Button in the scene clicks when
## pressed, and the menu can play the game's menu music on a loop. Read on
## a worker thread (at once in the single-threaded browser build). Without the game files the buttons click with a free
## recorded click (game/assets/sounds/ui_click.ogg) and there is no music.

const CLICK := "BC_CLICK.WAV"
const FREE_CLICK := "res://assets/sounds/ui_click.ogg"
const MUSIC := "MUSIC1.WAV"
const MUSIC_DB := -10.0
const CLICK_DB := -4.0
## The soft tick as focus or the pointer moves onto a button, as console
## menus give: made here (a short, quickly damped 2.4 kHz blip), so it
## needs no file. Not more than one per TICK_GAP_MS.
const TICK_DB := -21.0
const TICK_GAP_MS := 45

var play_music := false
var _path := ""
var _task := -1
var _click: AudioStream
var _music: AudioStreamWAV
var _click_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _tick_player: AudioStreamPlayer
var _last_tick := -1000


## The game's own sounds from SOUNDS.LS in the game folder, or the free
## click when there is none or the disc sounds are turned off.
static func from_game_folder(with_music: bool) -> MenuSounds:
	var path := ""
	if GraphicsSettings.disc_sounds():
		path = GameFolder.find_file(PackedStringArray(["sounds.ls", "SOUNDS.LS"]))
	var m := MenuSounds.new()
	m._path = path
	m.play_music = with_music
	return m


func _ready() -> void:
	_click_player = AudioStreamPlayer.new()
	_click_player.volume_db = CLICK_DB
	add_child(_click_player)
	_tick_player = AudioStreamPlayer.new()
	_tick_player.volume_db = TICK_DB
	_tick_player.stream = tick_stream()
	add_child(_tick_player)
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = MUSIC_DB + AudioSettings.music_db()
	add_child(_music_player)
	if _path.is_empty():
		_click = load(FREE_CLICK) as AudioStream
		set_process(false)
	elif OS.has_feature("web"):
		_load()  # single-threaded build
	else:
		_task = WorkerThreadPool.add_task(_load)
	get_tree().node_added.connect(_hook)
	_hook_all(get_tree().current_scene if get_tree().current_scene != null else get_parent())


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if get_tree().node_added.is_connected(_hook):
		get_tree().node_added.disconnect(_hook)


func _load() -> void:
	var archive := LsArchiveFile.open(_path)
	if archive == null:
		return
	_click = _stream(archive.read(CLICK))
	if play_music:
		_music = _stream(archive.read(MUSIC))
		if _music != null:
			_music.loop_mode = AudioStreamWAV.LOOP_FORWARD
			_music.loop_end = _music.data.size() / (2 * (2 if _music.stereo else 1))


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _music != null:
			_music_player.stream = _music
			_music_player.play()
		set_process(false)


func click() -> void:
	if _click != null:
		_click_player.stream = _click
		_click_player.play()


## A focus tick, skipped while the click is playing or right after one.
func tick() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_tick < TICK_GAP_MS or _click_player.playing:
		return
	_last_tick = now
	_tick_player.play()


## 30 ms of a damped 2.4 kHz sine with a lower partial, 16-bit mono.
static func tick_stream() -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * 0.03)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 190.0) * minf(1.0, t * 4000.0)
		var v := (sin(TAU * 2400.0 * t) * 0.7 + sin(TAU * 1200.0 * t) * 0.3) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func _hook_all(n: Node) -> void:
	if n == null:
		return
	_hook(n)
	for c in n.get_children():
		_hook_all(c)


func _hook(n: Node) -> void:
	if n is BaseButton and not (n as BaseButton).pressed.is_connected(click):
		var b := n as BaseButton
		b.pressed.connect(click)
		b.focus_entered.connect(tick)
		b.mouse_entered.connect(func() -> void:
			if not b.disabled:
				tick())


## The WAV starts at its RIFF tag. Readers before the untagged-entry fix
## returned SOUNDS.LS entries with their 0x37-byte block header in front, so
## that offset is still accepted.
static func _stream(entry: PackedByteArray) -> AudioStreamWAV:
	for at in [0, LsArchiveFile.BLOCK_HEADER_SIZE]:
		if entry.size() > at + 12 and entry.slice(at, at + 4).get_string_from_ascii() == "RIFF":
			return SsfBank.wav_to_stream(entry.slice(at))
	return null
