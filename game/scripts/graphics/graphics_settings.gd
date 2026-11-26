class_name GraphicsSettings
extends RefCounted
## Display and quality settings, saved to user://settings.cfg under
## [graphics], plus the wind strength, the presentation and the swing skill
## level under [game].
## Other sections of that file (such as the game folder) are left alone.
##
## A "look" preset sets everything at once (see apply_look()); changing a
## single option makes the look Custom. On the first run the look is picked
## for the device (detect_look()), so phones and the browser start light and
## gaming PCs start on Photoreal. See docs/graphics.md.

enum Quality { LOW, MEDIUM, HIGH, ULTRA }
## Classic frames and dresses the round like Links 2003; Broadcast like a TV
## golf broadcast (ShotDirector cameras, tracer, replays, BroadcastOverlay).
## Tour is Broadcast with the tour graphics package (TourGraphics): the
## leaderboard rail, the shot-data bar, the driving zone and the putt read.
enum Presentation { CLASSIC, BROADCAST, TOUR }
enum Look { PHOTOREAL, NATURAL, CINEMATIC, CLASSIC, PERFORMANCE, CUSTOM }
enum Lighting { CLASSIC, PHOTOREAL }
enum Upscaler { OFF, FSR1, FSR2 }
enum Grade { NEUTRAL, VIVID, WARM, COOL, FILM }
## The Photoreal lighting's time of day (Scenery.TIMES); Through the round
## moves the sun from morning on the first hole to golden hour on the last.
## How computer golfers miss with Links 2003's physics: our errors measured
## against tour statistics, or the game's own computer miss generators.
enum ComputerPlay { REALISTIC, CLASSIC }
const COMPUTER_PLAY_NAMES := ["Realistic (tour statistics)", "Classic Links"]
enum TimeOfDay { AFTERNOON, MORNING, MIDDAY, GOLDEN, ROUND, DAWN, SUNSET, OVERCAST }
## Fullscreen as a borderless window the size of the screen (quick to switch
## away from) or exclusive fullscreen (can be a little faster on Windows).
enum DisplayMode { BORDERLESS, EXCLUSIVE }
## The round's weather: always a fine day (as before), a day drawn from the
## course's climate for the month (Climate), or the real weather there now
## where the course is a real place (LiveWeather; the climate elsewhere).
enum WeatherMode { FINE, LOCAL, LIVE }
const WEATHER_NAMES := ["Always fine", "Realistic for the course", "Live where it's real"]
const DISPLAY_MODE_NAMES := ["Borderless fullscreen", "Exclusive fullscreen"]
## Section of user://settings.cfg where the desktop launcher leaves requests
## for the next start (see apply_launcher_requests()).
const LAUNCHER_SECTION := "launcher"

const PATH := "user://settings.cfg"
## Raised when the looks change, so saved preset settings are redone.
const LOOK_VERSION := 3
const SECTION := "graphics"
const GAME_SECTION := "game"
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
const MSAA_CHOICES := [0, 2, 4, 8]
const RENDER_SCALES := [0.5, 0.75, 1.0, 1.25, 1.5]
const PRESENTATION_NAMES := ["Classic Links", "Broadcast", "Tour"]
const LOOK_NAMES := ["Photoreal", "Natural", "Cinematic", "Classic Links", "Performance", "Custom"]
const LIGHTING_NAMES := ["Classic Links", "Photoreal"]
const UPSCALER_NAMES := ["Off", "FSR 1", "FSR 2"]
const GRADE_NAMES := ["Neutral", "Vivid", "Warm afternoon", "Cool morning", "Film"]
const LEVEL_NAMES := ["Off", "Low", "Medium", "High"]
const PUTTING_GRID_NAMES := ["Off", "Yellow (Links)", "Coloured by height (Links)", "Coloured by slope (TV)"]
const TIME_NAMES := ["Afternoon", "Morning", "Midday", "Golden hour", "Through the round", "Dawn", "Sunset", "Soft overcast"]
## Trees: the course's own (classic) or 3D, by how far out they stay 3D
## before turning into impostors (TreeFactory.IMPOSTOR_DISTANCE).
const TREE_NAMES := ["Classic", "3D near", "3D", "3D far"]
const DYNAMIC_NAMES := ["Off", "Keep 30 fps", "Keep 60 fps"]
const DYNAMIC_FPS := [0, 30, 60]
## Strength of each level (Off, Low, Medium, High) of the post effects.
const SHARPEN_LEVELS := [0.0, 0.25, 0.5, 0.8]
## FSR 2's own sharpening (0 sharpest, 2 softest), and how much of ours is
## added on top of it.
const FSR2_SHARPNESS := 0.8
const FSR2_OUR_SHARPEN := 0.0
const BLOOM_LEVELS := [0.0, 0.15, 0.3, 0.55]
const VIGNETTE_LEVELS := [0.0, 0.15, 0.3, 0.5]
const GRAIN_LEVELS := [0.0, 0.025, 0.05, 0.1]

## Tests and the CI render check set this to fix the look (-1: as saved).
static var force_look := -1
## FrameBenchmark turns the pixel budget off to measure what it saves.
static var ignore_pixel_budget := false
## The launcher's window size has been applied this run.
static var _sized := false

var quality: int = Quality.HIGH
var fullscreen := false
## How fullscreen is done when `fullscreen` is on (an index into
## DISPLAY_MODE_NAMES); the launcher offers it. Windowed when it's off.
var display_mode: int = DisplayMode.BORDERLESS
## The window's size when windowed, from the launcher; zero leaves the
## project's default size (or whatever the player last dragged it to).
var window_size := Vector2i.ZERO
## Size of the menus and HUD (an index into UI_SCALES): bigger for phones and
## TVs, smaller for a big monitor up close.
var ui_scale := 1
const UI_SCALES := [0.85, 1.0, 1.15, 1.3]
const UI_SCALE_NAMES := ["Smaller", "Normal", "Larger", "Largest"]
## Colours that read with red-green colour blindness (SwingMeter.colour_safe).
var colour_safe := false
var vsync := true
var msaa := 2  ## samples: 0, 2, 4 or 8
var render_scale := 1.0  ## 3D resolution relative to the window
## Vertical field of view, degrees. A long lens, as TV golf and modern golf
## games use: the aim view steps back to keep the golfer's size
## (RoundCamera.lens_factor), so the hole behind is compressed.
var fov := 40.0
var wind: int = Wind.Level.MODERATE
var presentation: int = Presentation.BROADCAST
## Broadcast and Tour: one camera that follows the ball through its flight
## and roll (true) instead of TV-style cuts (ShotDirector follow_ball).
var follow_ball := true
## Web only: copy the disc's crowd, menu and golfer voice sounds into memory
## at startup (tens of MB) instead of using the light placeholder sounds.
## Desktop builds always read them from the game folder.
var web_disc_sounds := false
## Swing skill level for the people playing, 0 (easiest) to 3: how hard the
## Links 2003 swing punishes a missed snap (LinksLaunch.apply_swing).
var skill := 3
## How far the people playing hit each club (PlayerPower.Profile): Links
## 2003's own distances by default, or an amateur's, a scratch golfer's or a
## tour pro's.
var power_profile: int = PlayerPower.Profile.CLASSIC
## The game's green options (LinksGround.set_greens): firmness 0 soft, 1
## medium, 2 firm; speed 0 slow, 1 normal, 2 fast.
var green_firmness := 1
var green_speed := 1
## How the people playing swing: 0 the three-click meter, 1 Links 2003's
## PowerStroke mouse swing (MouseSwingControl). Space always uses the meter.
var swing_method := 1
## The pace of play. Quick (the default): the three-click chip and putt
## meters start on the snap line and move briskly
## (LinksPowerStroke.QUICK_CLIMB), the Broadcast and Tour putting meter is
## one of three fixed meters in feet (PuttMeterScale), and a putt that stays out is followed by a short
## pause. Classic: Links 2003's own meter timing and one putting meter.
## The ball's physics and the snap's difficulty are the same either way.
var quick_pace := true
## Settings > Units: false yards and feet with mph (Links 2003), true metres
## with km/h. Copied into Units.metric, which every distance shown reads.
var metric_units := false
## Settings > Play-time count: the anonymous 15-minute count (PlayCount).
## Copied into PlayCount.enabled.
var play_count := true
## Links 2003's swing help for the mouse swing: once most of a player's
## strokes have had no sideways movement at all, strokes are nudged a few
## degrees off line (LinksMouse.Help).
var swing_help := false
## Green reading (GreenRead): the putting grid, 0 off, 1 Links 2003's yellow
## grid, 2 its grid coloured by height, 3 the TV grid coloured by slope
## (GreenGrid.Style + 1). As in the game, the grid isn't there at Elite
## skill, except as the Broadcast presentation's TV graphic.
var putting_grid := 3
## Links 2003's Breakline Indicator at the foot of the aiming marker.
var breakline := false
## Links 2003's Putting Assistant: the line and power at Amateur skill, a
## band round the line at Professional, nothing harder.
var putting_assistant := false
## A caddie at the players' shots with a read scaled to the swing skill
## (Caddie, CaddieAdvice). Off by default, as in Links 2003.
var caddie := false
## Draw the ball at its true size (42.67 mm), only kept from shrinking
## below a few pixels far away (GolfRound.ball_radius). On by default; off
## draws it bigger with distance, as Links 2003 does.
var true_size_ball := true
## The golfer drawn from photographs: a real person filmed swinging, frame by
## frame (PhotoGolfer), instead of the 3D golfer. Off by default; the 3D
## golfer still plays the shots and views the film doesn't cover.
var photo_golfer := false
## Drive a golf buggy to the ball between shots (GolfBuggy). Off by default.
var buggy := false
## Gimmes: a putt left this close is conceded for one stroke (an index into
## GIMME_FEET; 0 is off, as in Links 2003). Never in a friend's round.
var gimme := 0
## Mulligans: take a shot again, as if it never happened. 0 off (as in
## Links 2003), 1 one per player per nine holes, 2 one per player per hole.
## Never in a friend's round or the team modes.
var mulligans := 0
const MULLIGAN_NAMES := ["Off", "One per nine holes", "One per hole"]
## Pick up: end a hole at this score instead of the usual limit
## (GolfRound.MAX_STROKES). 0 off, 1 at double par, 2 at triple bogey.
## Never in a friend's round.
var pickup := 0
var computer_play: int = ComputerPlay.REALISTIC
const PICKUP_NAMES := ["Off (at 10)", "At double par", "At triple bogey"]
## Take real swings from a launch monitor app over OpenConnect (desktop).
var launch_monitor := false
## Captions for the golfer's voice and the crowd (SoundCaptions). Off by default.
var captions := false
const GIMME_FEET := [0.0, 2.0, 3.0, 4.0]
const GIMME_NAMES := ["Off", "Inside 2 ft", "Inside 3 ft", "Inside the leather (4 ft)"]
const GIMME_NAMES_METRIC := ["Off", "Inside 60 cm", "Inside 90 cm", "Inside the leather (1.2 m)"]

var look: int = Look.CLASSIC
## The look was picked by the game for this device (detect_look()), not by
## the player, so FrameWatch may step it down when frames are slow.
var auto_look := true
## Performance's lean form, for the slowest machines (software rendering,
## or FrameWatch's last step): no 3D grass, the course's own trees, a lower
## 3D resolution and no moving cloud shade or swaying leaves.
var lean := false
var lighting: int = Lighting.CLASSIC
var upscaler: int = Upscaler.OFF
var dynamic_res := 0  ## index into DYNAMIC_FPS
## Post effects, as levels 0 (off) to 3 (high).
var sharpen := 0
var bloom := 0
var vignette := 0
var grain := 0
var grade: int = Grade.NEUTRAL
var ssao := false
var dof := false
## 3D grass in the rough, 0 (off) to 3 (dense and far).
var grass := 0
var foliage_wind := false
## Shadows of passing clouds drifting over the course with the wind.
var cloud_shadows := false
var terrain_occlusion := true  ## the ground hides far trees and objects behind hills (TerrainOcclusion)
## 0 classic trees, 1 to 3 photo-textured 3D trees (see TREE_NAMES).
var trees := 0
## Photoreal lighting only, and not part of the looks.
var time_of_day: int = TimeOfDay.AFTERNOON
var weather: int = WeatherMode.FINE


func _init() -> void:
	# The browser build runs on everything from phones to desktops, on the
	# simpler renderer, so it starts a notch lower, but with 2x MSAA:
	# without it trees, flags and the golfer look jagged and low-res.
	if OS.has_feature("web"):
		quality = Quality.MEDIUM
		msaa = 2


## The Gimmes choices in the player's units.
static func gimme_names() -> Array:
	return GIMME_NAMES_METRIC if Units.metric else GIMME_NAMES


## The look to start with on this device: Photoreal on a dedicated graphics
## card, Natural on built-in graphics, browsers and capable phones and
## tablets, Performance on other phones and software renderers, and in a
## browser on old or small graphics chips (WebDevice.Tier.LEAN).
static func detect_look() -> int:
	if OS.has_feature("web"):
		return Look.PERFORMANCE if web_tier() == WebDevice.Tier.LEAN else Look.NATURAL
	if OS.has_feature("mobile"):
		return Look.PERFORMANCE
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return Look.PHOTOREAL
		RenderingDevice.DEVICE_TYPE_CPU:
			return Look.PERFORMANCE
	return Look.NATURAL


## Whether to start on Performance's lean form: software rendering, or a
## browser that says WebGL is slow on this machine.
static func detect_lean() -> bool:
	if OS.has_feature("web"):
		return WebDevice.is_software() or bool(WebDevice.info().get("caveat", false))
	return RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_CPU


## Whether this browser's device gets the web build's higher tier: High
## quality, denser grass and 3D trees further out (WebDevice.tier()).
static func web_capable() -> bool:
	return OS.has_feature("web") and web_tier() == WebDevice.Tier.HIGH


## The browser build's tier for this device (WebDevice.Tier).
static func web_tier() -> int:
	return WebDevice.tier(OS.has_feature("web_android") or OS.has_feature("web_ios"), OS.has_feature("web_ios"))


## An iPad (or another big-screened Apple device) in the browser: Apple's
## tablet chips take the densest grass too.
static func web_tablet() -> bool:
	if not OS.has_feature("web_ios") or not web_capable():
		return false
	# In CSS pixels: phones are under about 450 wide, iPads 744 and up.
	var size := Vector2(DisplayServer.screen_get_size()) / maxf(DisplayServer.screen_get_scale(), 1.0)
	return minf(size.x, size.y) >= 700.0


## Sets every option to the preset `which` (a Look). Options the renderer
## can't do (SSAO, depth of field and FSR in the browser) are still stored
## and simply skipped when applied. The browser build keeps quality and grass
## a notch lower, as it shares one thread with the game.
func apply_look(which: int) -> void:
	look = which
	match which:
		Look.PHOTOREAL:
			_set_look(Quality.ULTRA, Lighting.PHOTOREAL, Upscaler.FSR2, 0, 1.0, [1, 2, 1, 1], Grade.NEUTRAL, true, true, 3)
		Look.NATURAL:
			_set_look(Quality.HIGH, Lighting.PHOTOREAL, Upscaler.OFF, 2, 1.0, [1, 1, 1, 0], Grade.NEUTRAL, true, false, 2)
		Look.CINEMATIC:
			_set_look(Quality.ULTRA, Lighting.PHOTOREAL, Upscaler.FSR2, 0, 1.0, [1, 3, 2, 2], Grade.FILM, true, true, 3)
		Look.CLASSIC:
			_set_look(Quality.HIGH, Lighting.CLASSIC, Upscaler.OFF, 2, 1.0, [0, 0, 0, 0], Grade.NEUTRAL, false, false, 0)
			foliage_wind = false
			cloud_shadows = false
			dynamic_res = 0
			trees = 0
			return
		Look.PERFORMANCE:
			# A lower 3D resolution, upscaled with FSR 1 where it's
			# available and sharpened, costs far less than it shows.
			_set_look(Quality.LOW, Lighting.PHOTOREAL, Upscaler.FSR1, 0, 0.75, [2, 0, 0, 0], Grade.NEUTRAL, false, false, 1)
		_:
			return
	foliage_wind = true
	cloud_shadows = which != Look.PERFORMANCE
	dynamic_res = 2
	trees = 1 if which == Look.PERFORMANCE else (3 if quality >= Quality.ULTRA else 2)
	if which == Look.PERFORMANCE and lean:
		grass = 0
		trees = 0
		render_scale = 0.6
		sharpen = 1
		foliage_wind = false
		cloud_shadows = false
	if OS.has_feature("web"):
		# One thread for game and renderer: a notch lower, and two notches
		# on devices outside web_capable().
		var top := web_capable()
		quality = mini(quality, Quality.HIGH if top else Quality.MEDIUM)
		grass = mini(grass, (3 if web_tablet() else 2) if top else 1)
		trees = mini(trees, 2 if top else 1)
		msaa = maxi(msaa, 2) if which != Look.PERFORMANCE else 0


## `post` is [sharpen, bloom, vignette, grain] levels.
func _set_look(q: int, light: int, up: int, samples: int, scale: float, post: Array, g: int, ao: bool, blur: bool, grass_level: int) -> void:
	quality = q
	lighting = light
	upscaler = up
	msaa = samples
	render_scale = scale
	sharpen = post[0]
	bloom = post[1]
	vignette = post[2]
	grain = post[3]
	grade = g
	ssao = ao
	dof = blur
	grass = grass_level


static func load_saved(path := PATH) -> GraphicsSettings:
	var s := _load_saved(path)
	if force_look < 0:
		s.apply_launcher_requests(path)
	return s


## The desktop launcher (launcher/) can't run this class, so it leaves its
## picks under [launcher] in the settings file: "look" (a Look preset to
## apply) and "quality" (a Quality to use, after the look). They're applied
## once, saved like any change, and the section is removed.
func apply_launcher_requests(path := PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not cfg.has_section(LAUNCHER_SECTION):
		return
	var which := int(cfg.get_value(LAUNCHER_SECTION, "look", -1))
	if which >= Look.PHOTOREAL and which < Look.CUSTOM:
		auto_look = false
		lean = false
		apply_look(which)
	var q := int(cfg.get_value(LAUNCHER_SECTION, "quality", -1))
	if q >= Quality.LOW and q <= Quality.ULTRA and q != quality:
		quality = q
		look = Look.CUSTOM
	save(path)
	cfg.load(path)
	cfg.erase_section(LAUNCHER_SECTION)
	cfg.save(path)


static func _load_saved(path: String) -> GraphicsSettings:
	var s := GraphicsSettings.new()
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file (first run) leaves it empty
	s.quality = clampi(int(cfg.get_value(SECTION, "quality", s.quality)), Quality.LOW, Quality.ULTRA)
	s.fullscreen = bool(cfg.get_value(SECTION, "fullscreen", s.fullscreen))
	s.display_mode = clampi(int(cfg.get_value(SECTION, "display_mode", s.display_mode)), DisplayMode.BORDERLESS, DisplayMode.EXCLUSIVE)
	var w := int(cfg.get_value(SECTION, "window_width", 0))
	var h := int(cfg.get_value(SECTION, "window_height", 0))
	s.window_size = Vector2i(w, h) if w >= 640 and h >= 360 else Vector2i.ZERO
	s.colour_safe = bool(cfg.get_value(SECTION, "colour_safe", s.colour_safe))
	s.ui_scale = clampi(int(cfg.get_value(SECTION, "ui_scale", s.ui_scale)), 0, UI_SCALES.size() - 1)
	s.vsync = bool(cfg.get_value(SECTION, "vsync", s.vsync))
	var samples := int(cfg.get_value(SECTION, "msaa", s.msaa))
	s.msaa = samples if MSAA_CHOICES.has(samples) else s.msaa
	s.render_scale = clampf(float(cfg.get_value(SECTION, "render_scale", s.render_scale)), 0.25, 2.0)
	s.fov = clampf(float(cfg.get_value(SECTION, "fov", s.fov)), 35.0, 90.0)
	s.wind = clampi(int(cfg.get_value(GAME_SECTION, "wind", s.wind)), Wind.Level.OFF, Wind.Level.STRONG)
	s.presentation = clampi(int(cfg.get_value(GAME_SECTION, "presentation", s.presentation)), Presentation.CLASSIC, Presentation.TOUR)
	s.follow_ball = bool(cfg.get_value(GAME_SECTION, "follow_ball", s.follow_ball))
	s.web_disc_sounds = bool(cfg.get_value(GAME_SECTION, "web_disc_sounds", s.web_disc_sounds))
	s.skill = clampi(int(cfg.get_value(GAME_SECTION, "skill", s.skill)), 0, LinksLaunch.SKILL_COUNT - 1)
	s.power_profile = PlayerPower.clamp_profile(int(cfg.get_value(GAME_SECTION, "power_profile", s.power_profile)))
	s.green_firmness = clampi(int(cfg.get_value(GAME_SECTION, "green_firmness", s.green_firmness)), 0, 2)
	s.green_speed = clampi(int(cfg.get_value(GAME_SECTION, "green_speed", s.green_speed)), 0, 2)
	s.swing_method = clampi(int(cfg.get_value(GAME_SECTION, "swing_method", s.swing_method)), 0, 1)
	s.quick_pace = bool(cfg.get_value(GAME_SECTION, "quick_pace", s.quick_pace))
	s.metric_units = bool(cfg.get_value(GAME_SECTION, "metric_units", s.metric_units))
	Units.metric = s.metric_units
	s.play_count = bool(cfg.get_value(GAME_SECTION, "play_count", s.play_count))
	PlayCount.enabled = s.play_count
	s.swing_help = bool(cfg.get_value(GAME_SECTION, "swing_help", s.swing_help))
	s.putting_grid = clampi(int(cfg.get_value(GAME_SECTION, "putting_grid", s.putting_grid)), 0, PUTTING_GRID_NAMES.size() - 1)
	s.breakline = bool(cfg.get_value(GAME_SECTION, "breakline", s.breakline))
	s.putting_assistant = bool(cfg.get_value(GAME_SECTION, "putting_assistant", s.putting_assistant))
	s.caddie = bool(cfg.get_value(GAME_SECTION, "caddie", s.caddie))
	s.time_of_day = clampi(int(cfg.get_value(SECTION, "time_of_day", s.time_of_day)), TimeOfDay.AFTERNOON, TimeOfDay.OVERCAST)
	s.weather = clampi(int(cfg.get_value(GAME_SECTION, "weather", s.weather)), WeatherMode.FINE, WeatherMode.LIVE)
	s.true_size_ball = bool(cfg.get_value(GAME_SECTION, "ball_true_size", s.true_size_ball))
	s.photo_golfer = cfg.get_value(GAME_SECTION, "photo_golfer", s.photo_golfer) == true
	s.buggy = bool(cfg.get_value(GAME_SECTION, "buggy", s.buggy))
	s.launch_monitor = bool(cfg.get_value(GAME_SECTION, "launch_monitor", s.launch_monitor))
	s.captions = cfg.get_value(GAME_SECTION, "captions", s.captions) == true
	s.pickup = clampi(int(cfg.get_value(GAME_SECTION, "pickup", s.pickup)), 0, PICKUP_NAMES.size() - 1)
	s.mulligans = clampi(int(cfg.get_value(GAME_SECTION, "mulligans", s.mulligans)), 0, MULLIGAN_NAMES.size() - 1)
	s.gimme = clampi(int(cfg.get_value(GAME_SECTION, "gimme", s.gimme)), 0, GIMME_FEET.size() - 1)
	s.computer_play = clampi(int(cfg.get_value(GAME_SECTION, "computer_play", s.computer_play)), 0, COMPUTER_PLAY_NAMES.size() - 1)
	if force_look >= 0:
		s.apply_look(force_look)
		return s
	s.auto_look = bool(cfg.get_value(SECTION, "auto_look", s.auto_look))
	s.lean = bool(cfg.get_value(SECTION, "lean", s.lean))
	if not cfg.has_section_key(SECTION, "look"):
		# First run, or settings from before the looks: pick for the device.
		s.auto_look = true
		s.lean = detect_lean()
		s.apply_look(detect_look())
		return s
	s.look = clampi(int(cfg.get_value(SECTION, "look", s.look)), Look.PHOTOREAL, Look.CUSTOM)
	if int(cfg.get_value(SECTION, "look_version", 1)) < LOOK_VERSION and s.look != Look.CUSTOM:
		# The presets have changed since these were saved: take the new
		# ones, and a capable phone or tablet the old version put on
		# Performance moves up to its new look.
		var which := s.look
		if is_equal_approx(s.fov, 50.0):
			s.fov = 40.0  # the old default lens moves to the new one
		if which == Look.PERFORMANCE and OS.has_feature("web"):
			which = detect_look()
		s.apply_look(which)
		return s
	s.lighting = clampi(int(cfg.get_value(SECTION, "lighting", s.lighting)), Lighting.CLASSIC, Lighting.PHOTOREAL)
	s.upscaler = clampi(int(cfg.get_value(SECTION, "upscaler", s.upscaler)), Upscaler.OFF, Upscaler.FSR2)
	s.dynamic_res = clampi(int(cfg.get_value(SECTION, "dynamic_res", s.dynamic_res)), 0, DYNAMIC_FPS.size() - 1)
	s.sharpen = clampi(int(cfg.get_value(SECTION, "sharpen", s.sharpen)), 0, 3)
	s.bloom = clampi(int(cfg.get_value(SECTION, "bloom", s.bloom)), 0, 3)
	s.vignette = clampi(int(cfg.get_value(SECTION, "vignette", s.vignette)), 0, 3)
	s.grain = clampi(int(cfg.get_value(SECTION, "grain", s.grain)), 0, 3)
	s.grade = clampi(int(cfg.get_value(SECTION, "grade", s.grade)), Grade.NEUTRAL, Grade.FILM)
	s.ssao = bool(cfg.get_value(SECTION, "ssao", s.ssao))
	s.dof = bool(cfg.get_value(SECTION, "dof", s.dof))
	s.grass = clampi(int(cfg.get_value(SECTION, "grass", s.grass)), 0, 3)
	s.foliage_wind = bool(cfg.get_value(SECTION, "foliage_wind", s.foliage_wind))
	s.cloud_shadows = bool(cfg.get_value(SECTION, "cloud_shadows", s.cloud_shadows))
	s.trees = clampi(int(cfg.get_value(SECTION, "trees", s.trees)), 0, TREE_NAMES.size() - 1)
	s.terrain_occlusion = bool(cfg.get_value(SECTION, "terrain_occlusion", s.terrain_occlusion))
	return s


func save(path := PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep the other sections; a missing file is fine
	cfg.set_value(SECTION, "quality", quality)
	cfg.set_value(SECTION, "fullscreen", fullscreen)
	cfg.set_value(SECTION, "display_mode", display_mode)
	cfg.set_value(SECTION, "window_width", window_size.x)
	cfg.set_value(SECTION, "window_height", window_size.y)
	cfg.set_value(SECTION, "ui_scale", ui_scale)
	cfg.set_value(SECTION, "colour_safe", colour_safe)
	cfg.set_value(SECTION, "vsync", vsync)
	cfg.set_value(SECTION, "msaa", msaa)
	cfg.set_value(SECTION, "render_scale", render_scale)
	cfg.set_value(SECTION, "fov", fov)
	cfg.set_value(GAME_SECTION, "wind", wind)
	cfg.set_value(GAME_SECTION, "presentation", presentation)
	cfg.set_value(GAME_SECTION, "follow_ball", follow_ball)
	cfg.set_value(GAME_SECTION, "web_disc_sounds", web_disc_sounds)
	cfg.set_value(GAME_SECTION, "skill", skill)
	cfg.set_value(GAME_SECTION, "power_profile", power_profile)
	cfg.set_value(GAME_SECTION, "green_firmness", green_firmness)
	cfg.set_value(GAME_SECTION, "green_speed", green_speed)
	cfg.set_value(GAME_SECTION, "swing_method", swing_method)
	cfg.set_value(GAME_SECTION, "quick_pace", quick_pace)
	cfg.set_value(GAME_SECTION, "metric_units", metric_units)
	Units.metric = metric_units
	cfg.set_value(GAME_SECTION, "play_count", play_count)
	PlayCount.set_enabled(play_count)
	cfg.set_value(GAME_SECTION, "swing_help", swing_help)
	cfg.set_value(GAME_SECTION, "putting_grid", putting_grid)
	cfg.set_value(GAME_SECTION, "breakline", breakline)
	cfg.set_value(GAME_SECTION, "putting_assistant", putting_assistant)
	cfg.set_value(GAME_SECTION, "caddie", caddie)
	cfg.set_value(SECTION, "time_of_day", time_of_day)
	cfg.set_value(GAME_SECTION, "weather", weather)
	cfg.set_value(GAME_SECTION, "ball_true_size", true_size_ball)
	cfg.set_value(GAME_SECTION, "photo_golfer", photo_golfer)
	cfg.set_value(GAME_SECTION, "buggy", buggy)
	cfg.set_value(GAME_SECTION, "gimme", gimme)
	cfg.set_value(GAME_SECTION, "mulligans", mulligans)
	cfg.set_value(GAME_SECTION, "pickup", pickup)
	cfg.set_value(GAME_SECTION, "computer_play", computer_play)
	cfg.set_value(GAME_SECTION, "captions", captions)
	cfg.set_value(GAME_SECTION, "launch_monitor", launch_monitor)
	cfg.set_value(SECTION, "look_version", LOOK_VERSION)
	for key in ["look", "auto_look", "lean", "lighting", "upscaler", "dynamic_res", "sharpen", "bloom", "vignette", "grain", "grade", "ssao", "dof", "grass", "foliage_wind", "cloud_shadows", "terrain_occlusion", "trees"]:
		cfg.set_value(SECTION, key, get(key))
	var err := cfg.save(path)
	if err != OK:
		push_warning("Could not save graphics settings to %s (error %d)" % [path, err])


## True on the Forward+ renderer (desktop), which supports SSAO and the other
## screen-space effects. The web build uses Compatibility.
func broadcast() -> bool:
	return presentation != Presentation.CLASSIC


## The tour graphics package on top of the Broadcast presentation.
func tour() -> bool:
	return presentation == Presentation.TOUR


## Whether the disc's crowd, menu and voice sounds are used: always on the
## desktop, and on the web when the player has turned "Disc sounds" on.
static func disc_sounds() -> bool:
	return not OS.has_feature("web") or load_saved().web_disc_sounds


static func is_forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## How far the sun's shadows reach. The browser keeps them nearer, so its
## one shadow map is spent where the player looks (sharper shadows); the
## baked ground shade carries the far trees' shadows.
func shadow_distance() -> float:
	var d: float = [150.0, 250.0, 400.0, 600.0][quality]
	# Built-in graphics, like the browser, keep the sun's shadow map to the
	# near course (the baked ground shade carries the far trees' shadows):
	# sun shadows were a fifth of an M4's frame, and the four splits then
	# cover less ground each, so near shadows get sharper, not worse.
	if OS.has_feature("web"):
		return minf(d, 200.0)
	return minf(d, 250.0) if integrated_gpu() else d


## Built-in graphics: Apple's M chips, Intel and AMD laptop graphics. They
## share memory bandwidth with the CPU, so pixels are what they run out of
## first: a Mac on a Retina or 4K screen asks for four times the pixels of
## the same window on a 1080p screen.
static func integrated_gpu() -> bool:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return false
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return false
	return RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU \
		or RenderingServer.get_video_adapter_name().to_lower().contains("apple")


## Most 3D pixels a frame draws on built-in graphics, per quality (Low to
## Ultra): High is 1080p's worth. A bigger window (a Retina or 4K screen)
## renders at this many pixels and is upscaled with FSR, which on a
## high-density screen looks the same and costs a half to a quarter.
const IGPU_PIXEL_BUDGET := [1.0e6, 1.5e6, 2.1e6, 3.7e6]


## The share of `pixels` (the window's size in pixels) that fits in
## `budget` pixels, as a 3D scale: 1.0 when it all fits.
static func budget_scale(pixels: float, budget: float) -> float:
	if pixels <= 0.0 or pixels <= budget:
		return 1.0
	return sqrt(budget / pixels)


## The browser's 3D pixel budget per quality (Low to Ultra): WebGL shares
## its one thread with the game, and a Retina or 4K screen asks for four
## times the pixels of a 1080p one (the page draws at the device's pixel
## ratio). High keeps a 1080p window whole.
const WEB_PIXEL_BUDGET := [0.8e6, 1.2e6, 2.1e6, 2.1e6]
## The lowest the browser's pixel budget takes the 3D resolution: its plain
## stretch shows stair steps below about 0.7 on a 1x screen, while on a 2x
## screen half is still a pixel per CSS pixel.
const WEB_BUDGET_FLOOR := 0.7
const WEB_BUDGET_FLOOR_HIDPI := 0.5


## The 3D resolution to draw `viewport` at: the chosen render scale, kept
## inside the built-in graphics' (or the browser's) pixel budget. A scale
## above 1 (chosen supersampling) is taken as asked.
func effective_render_scale(viewport: Viewport) -> float:
	if render_scale > 1.0 or ignore_pixel_budget or not viewport is Window:
		return render_scale
	var size := Vector2((viewport as Window).size)
	if OS.has_feature("web"):
		return web_render_scale(render_scale, size.x * size.y, quality, WebDevice.pixel_ratio())
	if not integrated_gpu():
		return render_scale
	return minf(render_scale, budget_scale(size.x * size.y, IGPU_PIXEL_BUDGET[quality]))


## The browser's 3D scale for a chosen `scale`, a window of `pixels` device
## pixels, `q` quality and a device pixel ratio `dpr`.
static func web_render_scale(scale: float, pixels: float, q: int, dpr: float) -> float:
	var lowest := WEB_BUDGET_FLOOR_HIDPI if dpr >= 1.4 else WEB_BUDGET_FLOOR
	var s := minf(scale, budget_scale(pixels, WEB_PIXEL_BUDGET[q]))
	return maxf(s, minf(scale, lowest))


## The sun's shadow atlas, per quality (Low to Ultra): four splits at Ultra
## on Forward+ take 8192 squared (256 MB of video memory); Compatibility
## caps at 4096, and Medium takes 2048 — the baked ground shade carries
## the far trees' shadows, so the atlas is spent near the player, where
## the shadows are sharpest.
func shadow_atlas_size() -> int:
	return shadow_atlas_size_for(quality, is_forward_plus())


static func shadow_atlas_size_for(q: int, forward_plus: bool) -> int:
	var size: int = [2048, 2048, 4096, 8192][clampi(q, 0, 3)]
	return mini(size, 8192 if forward_plus else 4096)


## How many directional-light shadow splits the sun draws: four at High
## and Ultra (as before), two at Low and Medium. Each split re-draws every
## caster, so two splits roughly halves the shadow pass's draw calls on
## the lower tiers; the first split still covers the golfer and the tee at
## full detail (Scenery.first_split), and the baked ground shade carries
## the far trees' shadows.
func shadow_splits() -> int:
	return shadow_splits_for(quality, is_forward_plus())


static func shadow_splits_for(q: int, _forward_plus: bool) -> int:
	return 4 if q >= Quality.HIGH else 2


func soft_shadow_quality() -> RenderingServer.ShadowQuality:
	# Built-in graphics take a notch softer filter: the sun's soft edge
	# stays, with fewer taps per pixel.
	var q := quality - (1 if integrated_gpu() and quality > Quality.MEDIUM else 0)
	match q:
		Quality.LOW:
			return RenderingServer.SHADOW_QUALITY_HARD
		Quality.MEDIUM:
			return RenderingServer.SHADOW_QUALITY_SOFT_LOW
		Quality.HIGH:
			return RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	return RenderingServer.SHADOW_QUALITY_SOFT_ULTRA


## Applies the settings that belong to the window and the renderer.
func apply_display(viewport: Viewport) -> void:
	if viewport is Window:
		(viewport as Window).content_scale_factor = UI_SCALES[ui_scale]
	SwingMeter.colour_safe = colour_safe
	Glass.allow_blur = quality != Quality.LOW
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		var mode := DisplayServer.WINDOW_MODE_WINDOWED
		if fullscreen:
			mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if display_mode == DisplayMode.EXCLUSIVE else DisplayServer.WINDOW_MODE_FULLSCREEN
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		if mode == DisplayServer.WINDOW_MODE_WINDOWED and window_size != Vector2i.ZERO and not _sized:
			# Once per run, so dragging the window bigger sticks.
			_sized = true
			var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			var size := Vector2i(mini(window_size.x, screen.size.x), mini(window_size.y, screen.size.y))
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
	elif DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	match msaa:
		2:
			viewport.msaa_3d = Viewport.MSAA_2X
		4:
			viewport.msaa_3d = Viewport.MSAA_4X
		8:
			viewport.msaa_3d = Viewport.MSAA_8X
		_:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
	var fsr2 := is_forward_plus() and upscaler == Upscaler.FSR2
	# FXAA is cheap and softens the edges MSAA would otherwise catch; on
	# Forward+ at High and up, SMAA (Godot 4.5+) catches them as well
	# without blurring the turf and leaf texture. FSR 2 does its own
	# (temporal) anti-aliasing, even at full resolution.
	var ssaa := Viewport.SCREEN_SPACE_AA_SMAA if is_forward_plus() and quality >= Quality.HIGH else Viewport.SCREEN_SPACE_AA_FXAA
	viewport.screen_space_aa = ssaa if msaa == 0 and not fsr2 and quality >= Quality.MEDIUM else Viewport.SCREEN_SPACE_AA_DISABLED
	if fsr2:
		viewport.msaa_3d = Viewport.MSAA_DISABLED
	# The FSR upscalers need Forward+; the browser's renderer stretches.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var scale := effective_render_scale(viewport)
	if is_forward_plus():
		match upscaler:
			Upscaler.OFF, Upscaler.FSR1:
				# FSR 1 only runs below full size (the pixel budget or
				# dynamic resolution) and keeps the edges crisp there,
				# where a plain stretch would blur them.
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			Upscaler.FSR2:
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		# Godot's FSR sharpness runs from 0 (sharpest) to 2. FSR 2 at full
		# size is a temporal anti-aliaser whose own sharpen, at 0.3 and
		# with ours on top, gave people, leaves and turf a crunchy,
		# over-processed edge; 2K25 and TV pictures are soft-edged.
		viewport.fsr_sharpness = FSR2_SHARPNESS if upscaler == Upscaler.FSR2 else 0.3
	viewport.scaling_3d_scale = scale
	viewport.mesh_lod_threshold = MESH_LOD_PIXELS[quality]
	RenderingServer.directional_shadow_atlas_set_size(shadow_atlas_size(), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(soft_shadow_quality())


## Per quality: how many pixels a mesh's shape may be off on screen before
## the renderer draws a coarser level of it (the ground's far levels,
## DesignedTerrain.refine_lods, and imported models' own). Low and Medium
## accept a little more, as their screens are small and detail is cut
## anyway; High and Ultra keep Godot's one pixel.
const MESH_LOD_PIXELS := [3.0, 2.0, 1.0, 1.0]


## The frame rate dynamic resolution keeps to, or 0 for off.
func target_fps() -> int:
	return DYNAMIC_FPS[dynamic_res]
