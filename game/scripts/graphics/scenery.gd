class_name Scenery
extends Node3D
## Sky, sun, fog and post-processing for the course. Quality settings switch
## the expensive parts on and off; the Forward+-only effects (SSAO, SSIL,
## soft sun shadows) are left off on the Compatibility renderer used by the
## web build.
##
## Two lighting styles: Classic keeps Links 2003's flat, true-to-texture
## colours (linear tone map, colour ambient); Photoreal uses a filmic tone
## map, a stronger sun with sky-coloured fill light and, on Forward+,
## volumetric haze and screen-space reflections on the water.

const HORIZON := Color(0.68, 0.77, 0.86)
const AMBIENT := Color(0.66, 0.70, 0.76)
const AMBIENT_ENERGY := 0.5
## With the sun 38 degrees up, flat ground gets 0.85 * sin(38) of it.
const SUN_ENERGY := 0.85
## Photoreal: a strong sun under the AgX curve, which rolls highlights off
## to white without ACES's lime greens and orange skin, against a fill
## light about a fifth as bright, as in real sunshine.
const PHOTO_SUN_ENERGY := 3.0
const PHOTO_AMBIENT_ENERGY := 0.5
const PHOTO_EXPOSURE := 1.0
## Links 2003's afternoon sun height, which Classic lighting keeps.
const CLASSIC_SUN_ELEVATION := 38.0
## Photoreal exposure in Compatibility relative to Forward+ (see _apply_time).
const COMPAT_EXPOSURE_LIFT := 1.3
## Photoreal fill light in Compatibility relative to the time of day's.
const COMPAT_FILL_LIFT := 1.6
## The photographed sky in Photoreal on the Compatibility renderer: its
## brightness, saturation above the horizon band (photo_sky.gdshader
## sky_depth) and how much distance haze lies over it. Fitted so the top of
## the tee view lands near 2K25's and real tee shots' deep blue.
## 2026-11-18 quality pass: the tee view's sky top had sunk to a navy
## (44, 55, 83) on the web and (74, 107, 150) on desktop against 2K25's
## pale (97, 159, 205); a deep, saturated sky behind bright cumulus read
## as a painted backdrop.
const COMPAT_SKY_ENERGY := 1.75
const COMPAT_SKY_DEPTH := 0.8
const COMPAT_SKY_FOG := 0.08
const FORWARD_SKY_ENERGY := 1.0
const FORWARD_SKY_DEPTH := 1.2
## The sun's size for soft shadows (degrees), and its shadow normal bias
## (1.5 lifted the golfer's shadow off his feet).
const SUN_ANGLE := 0.15
const SUN_NORMAL_BIAS := 0.8
## Where the sun's shadow splits end, as shares of the shadow distance
## (Godot's are 0.1, 0.2, 0.5): the first covers the golfer and the tee
## at about four times the detail.
const SUN_SPLITS := Vector3(0.04, 0.12, 0.4)
## Forward+ only: how much brighter the photo sky's clouds are drawn
## (photo_sky.gdshader cloud_lift), so they read white under AgX.
const FORWARD_CLOUD_LIFT := 1.2
const SKY_SHADER := preload("res://shaders/photo_sky.gdshader")
## Photoreal light by time of day (GraphicsSettings.time_of_day): the sun's
## height and bearing (degrees), its colour and strength, the fill light
## (`fill` in Compatibility, before its 1.6 lift; `fill_fwd` in Forward+),
## the photographed sky's tint (overall and at the horizon), the glow round
## a low sun, the haze colour and thickness and an exposure that makes up
## for a low sun. Afternoon sits lower and warmer than Classic's sun
## (CLASSIC_SUN_ELEVATION), for long shadows as in TV golf, and warmer: a
## late-afternoon sun as in GSPro's and 2K25's default light, which lays
## long, dappled tree shadows across tees and fairways. `scatter` is the
## haze's glow towards the sun (Environment.fog_sun_scatter). Golden hour
## was fitted to 37 real low-sun golf photos: a near-neutral sky, green
## turf, and only the sunlit patches warm, so its shade needs a strong,
## cool fill (Forward+ shade is darker, hence its own fill). Afternoon's
## sun is only lightly warm, with thin haze: a deep orange sun, thick haze
## and a strong warm grade turned mown fairways and tees olive-yellow and
## washed out (Michael, 2026-11-15).
const TIMES := {
	"morning": {elevation = 17.0, bearing = 100.0, sun = Color(1.0, 0.86, 0.7), energy = 0.85, fill = 0.95, fill_fwd = 0.95,
		ambient = Color(0.62, 0.69, 0.8), sky = Color(0.92, 0.96, 1.04), horizon = Color(1.05, 1.0, 0.95), glow = 0.25,
		haze = Color(0.76, 0.8, 0.86), fog = 2.2, exposure = 1.15, scatter = 0.3, warm = Color(1.03, 1.0, 0.94), cool = Color(0.95, 0.99, 1.06), pop = 1.05},
	"midday": {elevation = 62.0, bearing = 160.0, sun = Color(1.0, 0.97, 0.93), energy = 1.0, fill = 1.0, fill_fwd = 1.0,
		ambient = Color(0.66, 0.70, 0.76), sky = Color(1.0, 1.0, 1.02), horizon = Color(1.0, 1.0, 1.0), glow = 0.0,
		haze = Color(0.70, 0.78, 0.88), fog = 0.9, exposure = 0.95, scatter = 0.05, warm = Color(1.02, 1.0, 0.96), cool = Color(0.98, 1.0, 1.03), pop = 1.04},
	"afternoon": {elevation = 28.0, bearing = 145.0, sun = Color(1.0, 0.9, 0.76), energy = 1.15, fill = 1.0, fill_fwd = 0.6,
		ambient = Color(0.58, 0.68, 0.82), sky = Color(1.0, 1.0, 1.0), horizon = Color(1.06, 1.0, 0.93), glow = 0.2,
		haze = Color(0.70, 0.77, 0.86), fog = 0.8, exposure = 1.0, scatter = 0.2, warm = Color(1.02, 1.0, 0.97), cool = Color(0.93, 1.0, 1.08), pop = 1.15},
	"golden": {elevation = 9.0, bearing = 205.0, sun = Color(1.0, 0.74, 0.5), energy = 1.3, fill = 0.55, fill_fwd = 4.2,
		ambient = Color(0.68, 0.7, 0.74), sky = Color(1.0, 0.96, 0.92), horizon = Color(1.08, 0.98, 0.88), glow = 0.5,
		haze = Color(0.82, 0.78, 0.72), fog = 1.6, exposure = 1.6, scatter = 0.45, warm = Color(1.08, 0.99, 0.84), cool = Color(0.94, 0.98, 1.08), pop = 1.1},
	# Dawn: the sun just up in the east through a cool morning mist, its
	# light peach on the dew. Sunset: the sun low in the west, orange light
	# raking across the course under a warm sky. Both shown for the look
	# (photos, promo), so pushed a little past the photos.
	"dawn": {elevation = 6.0, bearing = 85.0, sun = Color(1.0, 0.74, 0.52), energy = 1.0, fill = 0.6, fill_fwd = 4.0,
		ambient = Color(0.6, 0.66, 0.8), sky = Color(0.95, 0.95, 1.05), horizon = Color(1.12, 0.96, 0.86), glow = 0.6,
		haze = Color(0.8, 0.8, 0.86), fog = 3.5, exposure = 1.45, scatter = 0.5, warm = Color(1.07, 0.99, 0.88), cool = Color(0.92, 0.97, 1.1), pop = 1.06},
	"sunset": {elevation = 5.0, bearing = 245.0, sun = Color(1.0, 0.6, 0.36), energy = 1.3, fill = 0.5, fill_fwd = 4.2,
		ambient = Color(0.7, 0.66, 0.72), sky = Color(1.02, 0.92, 0.86), horizon = Color(1.18, 0.9, 0.72), glow = 0.9,
		haze = Color(0.88, 0.74, 0.62), fog = 2.0, exposure = 1.75, scatter = 0.6, warm = Color(1.12, 0.96, 0.78), cool = Color(0.92, 0.95, 1.1), pop = 1.12},
	# Soft overcast: a high, thin cloud deck (the look of Toni Macaroni's
	# Godot forest scenes that Michael pointed to, 2026-11-17). The sun is a
	# weak, wide source, so shadows are faint and soft and the fill from the
	# whole sky does most of the lighting: no dark, muddy shade. The air is
	# thick enough to stack the far hills and woods into blue-grey layers
	# (aerial perspective), and the grade stays neutral so the turf keeps a
	# fresh green instead of the sunny times' warm olive. `soft` is the
	# sun's angular size in degrees on Forward+ (contact-hardening shadows),
	# `shadow` scales the baked tree shadows on the ground (ground_sun_shadow),
	# and `sky_photo` swaps in the overcast panorama (FreeAssets.overcast_sky).
	"overcast": {elevation = 48.0, bearing = 150.0, sun = Color(0.97, 0.98, 1.0), energy = 0.32, fill = 1.55, fill_fwd = 2.8,
		ambient = Color(0.70, 0.75, 0.80), sky = Color(1.0, 1.0, 1.0), horizon = Color(1.0, 1.0, 1.0), glow = 0.0,
		haze = Color(0.66, 0.74, 0.84), fog = 2.2, exposure = 1.2, scatter = 0.0, warm = Color(1.0, 1.0, 0.99), cool = Color(0.98, 1.0, 1.03), pop = 1.12,
		soft = 9.0, shadow = 0.25, sky_photo = 1.0},
}
## "Through the round": the light at these points of the round, blended.
const ROUND_TIMES := [[0.0, "morning"], [0.35, "midday"], [0.7, "afternoon"], [1.0, "golden"]]

var environment: Environment
var sun: DirectionalLight3D
var backdrop: CourseBackdrop
## The hills and woods beyond a course with no horizon panorama, or null.
var far: FarScenery
var _quality := GraphicsSettings.Quality.HIGH
var _free_sky: Material  ## the photographed sky (FreeAssets), or null
var _backdrop_sky: Material  ## the plain sky behind the course's backdrop
var _photo := false
var _gi := false  ## global illumination on (Ultra Photoreal on a real GPU)
## The exposure the time of day sets, before the shade adaptation, and the
## adaptation itself (adapt_to_shade): 1 in the open, more under trees.
var _base_exposure := 1.0
var _adapt := 1.0
var _adapt_target := 1.0
var _adapt_clock := 0.0
## The sun and fill light apply() set, before the weather scales them.
var _sun_energy := SUN_ENERGY
var _sun_color := Color(1.0, 0.95, 0.86)
var _ambient_energy := AMBIENT_ENERGY
var _sun_angle := 0.0
## The time of day's light (TIMES entries blended), and how far through the
## round it is, for "Through the round".
var _time: Dictionary = TIMES["afternoon"]
var _time_setting := 0
var _round_progress := 0.0
## The round's weather (set_weather): how overcast (0 to 1, after
## overcast_of), how misty and how wet.
var _weather_overcast := 0.0
var _weather_fog := 0.0
var _weather_rain := 0.0


func _init() -> void:
	name = "Scenery"
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.40, 0.74)
	sky_mat.sky_horizon_color = HORIZON
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.16, 0.22, 0.14)
	sky_mat.ground_horizon_color = HORIZON
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# The free photographic sky (FreeAssets), when it has been fetched.
	var panorama := FreeAssets.sky()
	if panorama:
		var pano_mat := ShaderMaterial.new()
		pano_mat.shader = SKY_SHADER
		pano_mat.set_shader_parameter("panorama", panorama)
		# An HDR photo: keep its sun-lit clouds from clipping to white under
		# the linear tone map.
		pano_mat.set_shader_parameter("energy", 0.8)
		sky.sky_material = pano_mat
		_free_sky = pano_mat

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Links 2003 draws its photographic ground textures close to their own
	# colours, with shading from the sun and soft shadows. A linear tone map
	# with the sun and ambient light adding up to about 1 on flat ground keeps
	# them that way; a filmic curve washes the greens out to pale lime.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Distance haze, so far trees and hills fade towards the horizon.
	environment.fog_enabled = true
	environment.fog_light_color = HORIZON
	environment.fog_density = 0.0006
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.3
	environment.glow_intensity = 0.25
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.2
	# Tuned for contact shade: a tighter radius with full fine detail, so
	# grass darkens round the golfer's shoes, the ball, the flagstick and
	# crowd feet, and a little of it reaches the sunlit side (light_affect),
	# where real contact shadows show most.
	# In shade the sky fill is all the light there is, so the occlusion
	# takes all of it: at intensity 1.6 and power 1.6 the trunks and bark in
	# a wood's shade went from about 32/255 to 6, near black (2026-11-19,
	# Michael: "way too dark, not real" under trees at midday). Softer,
	# and the fine detail halved so bark and leaf normals don't crush.
	environment.ssao_radius = 0.9
	environment.ssao_intensity = 1.0
	environment.ssao_detail = 0.5
	environment.ssao_power = 1.15
	environment.ssao_light_affect = 0.2
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	# Afternoon sun from behind and to the right of the golfer, so the view
	# down the hole is lit from the front and slopes cast soft shade.
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = SUN_NORMAL_BIAS
	sun.directional_shadow_blend_splits = true
	# The first split ends close (SUN_SPLITS): the golfer always stands near
	# the camera, and with Godot's 10% of a 400 m shadow distance its texels
	# were 2 cm across, so a leg's or an arm's shadow on the body had a
	# ragged, stepped edge.
	sun.directional_shadow_split_1 = SUN_SPLITS.x
	sun.directional_shadow_split_2 = SUN_SPLITS.y
	sun.directional_shadow_split_3 = SUN_SPLITS.z
	add_child(sun)


func apply(settings: GraphicsSettings) -> void:
	var fwd := GraphicsSettings.is_forward_plus()
	var q := settings.quality
	var photo := settings.lighting == GraphicsSettings.Lighting.PHOTOREAL
	sun.directional_shadow_max_distance = settings.shadow_distance()
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == GraphicsSettings.Quality.LOW else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# Angular size of the sun gives contact-hardening soft shadows (Forward+).
	# Kept small: at 0.6 degrees the soft-shadow filter, over the far
	# splits' big texels, blurred the golfer's and the bag's shadows to a
	# faint smudge, so the golfer looked pasted on the tee (2K25 pass 3).
	sun.light_angular_distance = SUN_ANGLE if fwd and q >= GraphicsSettings.Quality.HIGH else 0.0
	sun.light_energy = PHOTO_SUN_ENERGY if photo else SUN_ENERGY
	sun.light_color = Color(1.0, 0.94, 0.84) if photo else Color(1.0, 0.95, 0.86)
	if photo:
		environment.tonemap_mode = Environment.TONE_MAPPER_AGX
		# Compatibility has no sky fill light, so the same sun reads hotter.
		environment.tonemap_exposure = PHOTO_EXPOSURE if fwd else PHOTO_EXPOSURE * 0.8
		environment.tonemap_white = 6.0
		environment.ambient_light_energy = PHOTO_AMBIENT_ENERGY
		# Fill light from the sky itself (blue from above, green bounce from
		# below) where the renderer supports it.
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if fwd else Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_sky_contribution = 0.6
	else:
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.tonemap_exposure = 1.0
		environment.ambient_light_energy = AMBIENT_ENERGY
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var bloom: float = GraphicsSettings.BLOOM_LEVELS[settings.bloom]
	# Classic keeps its faint glow on the brightest highlights.
	environment.glow_enabled = bloom > 0.0 or (not photo and q >= GraphicsSettings.Quality.HIGH)
	environment.glow_intensity = bloom * 2.0 if bloom > 0.0 else 0.25
	# Glow only off what is really bright (the sun on sand, white
	# clouds): a whole-image bloom lays a milky veil over the course that
	# reads as haze and greys the sky, most of all in Forward+.
	environment.glow_bloom = bloom * 0.15 if not photo else 0.0
	# Photoreal at 1.0 caught sunlit cloth too: a wide yellow halo round
	# the golfer's khaki trousers on the turf behind (2K25 quality pass).
	# Only the sun on sand, white caps and clouds should glow.
	environment.glow_hdr_threshold = 1.8 if photo else 1.2
	environment.ssao_enabled = fwd and settings.ssao
	environment.ssil_enabled = fwd and settings.ssao and q >= GraphicsSettings.Quality.ULTRA
	# Low sun-lit haze that thickens with distance, and light shafts near
	# the camera. Costly, so only at the top quality.
	environment.volumetric_fog_enabled = fwd and photo and q >= GraphicsSettings.Quality.ULTRA
	# A clear day's air: at 0.0012 (about 3 km visibility) the sunlit
	# haze laid a milky veil over everything past the tee.
	environment.volumetric_fog_density = 0.0004
	environment.volumetric_fog_albedo = Color(0.9, 0.93, 1.0)
	environment.volumetric_fog_anisotropy = 0.6
	environment.volumetric_fog_length = 160.0
	environment.volumetric_fog_sky_affect = 0.0
	# Screen-space reflections cost a full-screen ray march for the water
	# alone; built-in graphics keep them for Ultra.
	var ssr_from := GraphicsSettings.Quality.ULTRA if GraphicsSettings.integrated_gpu() else GraphicsSettings.Quality.HIGH
	environment.ssr_enabled = fwd and photo and q >= ssr_from
	# Real-time global illumination at the top end (Ultra, Forward+, a real
	# graphics card): sunlight bouncing off the turf into the shade, green
	# light under the trees and the sky shut out beneath them, as UE5's
	# Lumen does. Software renderers would crawl, so never there.
	_gi = gi_available(settings)
	environment.sdfgi_enabled = _gi
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_cascades = 6
	environment.sdfgi_min_cell_size = 0.4
	environment.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
	environment.sdfgi_bounce_feedback = 0.5
	environment.sdfgi_energy = 1.0
	environment.ssr_max_steps = 48
	environment.fog_aerial_perspective = 0.5 if photo else 0.3
	_photo = photo
	_quality = settings.quality
	if far != null:
		far.apply_quality(_quality)
	_time_setting = settings.time_of_day
	_apply_time()
	_sun_energy = sun.light_energy
	_sun_color = sun.light_color
	_ambient_energy = environment.ambient_light_energy
	_sun_angle = sun.light_angular_distance
	_choose_sky()


## Whether `settings` get global illumination on this machine.
static func gi_available(settings: GraphicsSettings) -> bool:
	return GraphicsSettings.is_forward_plus() and settings.lighting == GraphicsSettings.Lighting.PHOTOREAL \
		and settings.quality >= GraphicsSettings.Quality.ULTRA \
		and RenderingServer.get_video_adapter_type() != RenderingDevice.DEVICE_TYPE_CPU


## Shows the course's own horizon (null for none) in front of a cloud sky
## from the player's files (the course's own, `course_sky`, unless the
## player picked one), when the player's files have one; otherwise keeps
## the default sky. Called once per course.
func set_backdrop(horizon: Image, course_sky := 0) -> void:
	if backdrop != null:
		backdrop.queue_free()
		backdrop = null
	var b := CourseBackdrop.create(horizon, course_sky)
	if not b.has_sky and not b.has_horizon:
		b.free()
		return
	backdrop = b
	add_child(b)
	# Above the photo bands the plain sky continues their colours, and the
	# haze fades far ground towards the horizon's own colours.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = b.sky_top.darkened(0.08)
	sky_mat.sky_horizon_color = b.sky_top
	sky_mat.sky_curve = 0.3
	sky_mat.ground_horizon_color = b.ground
	sky_mat.ground_bottom_color = b.ground.darkened(0.3)
	sky_mat.sun_angle_max = 0.0
	sky_mat.sun_curve = 0.0
	_backdrop_sky = sky_mat
	_choose_sky()


## Puts the far hills and woods round `course` when it has no horizon
## panorama of its own (its own panorama already shows the land round it).
func set_far_scenery(course: CourseData) -> void:
	if far != null:
		far.queue_free()
		far = null
	if course == null or course.horizon != null or course.landscape:
		return
	far = FarScenery.create(course)
	if far == null:
		return
	add_child(far)
	far.apply_quality(_quality)
	_choose_sky()


## Photoreal lighting shows the photographed cloud sky with distance haze
## behind the course's horizon instead of the disc's sky, unless the player
## picked a sky; Classic keeps the course's own. The far scenery fades into
## the same haze.
func _choose_sky() -> void:
	_pick_sky()
	if far != null:
		far.set_haze(environment.fog_light_color, environment.fog_density, 1.0 if _photo else 2.2)
	Landscape.set_haze(environment.fog_light_color, environment.fog_density, 1.0 if _photo else 1.6)


func _pick_sky() -> void:
	var real := _photo and _free_sky != null and not (backdrop != null and backdrop.chosen and backdrop.has_sky)
	_apply_weather()
	if backdrop != null:
		backdrop.set_photo(real, HORIZON)
	if real or _backdrop_sky == null:
		environment.sky.sky_material = _free_sky if _free_sky != null else environment.sky.sky_material
		environment.fog_light_color = _time.haze if real else HORIZON
		environment.fog_density = (0.0006 if not real else 0.00035 * float(_time.fog)) * fog_scale(_weather_fog)
		if real and _weather_overcast > 0.0:
			# Under cloud the haze loses the sun's colour and goes grey.
			environment.fog_light_color = environment.fog_light_color.lerp(deck_color(_weather_rain), _weather_overcast * 0.8)
		environment.volumetric_fog_density = 0.0004 * fog_scale(_weather_fog)
		# The haze lights up warm towards a low sun (light through the air
		# between the tree rows), as on TV and in GSPro, cheap on every
		# renderer.
		# Forward+ fog reads thicker than Compat's, so its glow is kept lower.
		environment.fog_sun_scatter = float(_time.get("scatter", 0.0)) * (0.75 if GraphicsSettings.is_forward_plus() else 1.0) if real else 0.0
		# A little haze over the sky too, so the far land melts into it;
		# less in Forward+, where it turned the whole sky milky (most of all
		# from the flyover's height).
		# Compatibility keeps it as light as Forward+: at 0.25 the web sky
		# measured sRGB (171, 209, 240) at the top of the tee view against
		# 2K25's (97, 159, 205), and the far scenery has its own haze.
		environment.fog_sky_affect = (0.08 if GraphicsSettings.is_forward_plus() else COMPAT_SKY_FOG) if real else 0.0
		if _free_sky is ShaderMaterial:
			var sky_mat := _free_sky as ShaderMaterial
			var grey := FreeAssets.overcast_sky() if _time.has("sky_photo") else null
			sky_mat.set_shader_parameter("panorama", grey if grey != null else FreeAssets.sky())
			# Compatibility has no sky fill light, so its sky is drawn a
			# little brighter than Forward+'s, but no longer pale and milky.
			sky_mat.set_shader_parameter("energy", FORWARD_SKY_ENERGY if GraphicsSettings.is_forward_plus() else COMPAT_SKY_ENERGY)
			sky_mat.set_shader_parameter("sky_depth", FORWARD_SKY_DEPTH if GraphicsSettings.is_forward_plus() else COMPAT_SKY_DEPTH)
			sky_mat.set_shader_parameter("cloud_lift", FORWARD_CLOUD_LIFT if GraphicsSettings.is_forward_plus() else 0.0)
			sky_mat.set_shader_parameter("tint", _time.sky)
			sky_mat.set_shader_parameter("horizon_tint", _time.horizon)
			sky_mat.set_shader_parameter("glow", _time.glow)
			sky_mat.set_shader_parameter("glow_color", _time.sun)
			sky_mat.set_shader_parameter("overcast", _weather_overcast)
			sky_mat.set_shader_parameter("deck", deck_color(_weather_rain))
			_align_sky_sun(sky_mat)
		return
	environment.sky.sky_material = _backdrop_sky
	environment.fog_sun_scatter = 0.0
	environment.fog_sky_affect = 0.0
	environment.fog_light_color = backdrop.sky_haze.lerp(backdrop.ground, 0.35)
	environment.fog_density = 0.00035 * fog_scale(_weather_fog)


## Turns and stretches the photographed sky so the sun in the photo sits
## where the game's sun is (photo_sky.gdshader). Without it the clouds are
## lit from one side and the course's shadows fall from another, the
## commonest giveaway of a pasted-on sky.
func _align_sky_sun(sky_mat: ShaderMaterial) -> void:
	# The overcast photo has no sun to line up.
	var photo_sun := Vector2(-1.0, 0.0) if _time.has("sky_photo") and FreeAssets.overcast_sky() != null else FreeAssets.free_sky_sun()
	sky_mat.set_shader_parameter("align_sun", photo_sun.x >= 0.0)
	if photo_sun.x < 0.0:
		return
	var to_sun := sun.basis.z
	var a := sky_sun_mapping(to_sun, photo_sun.y)
	sky_mat.set_shader_parameter("photo_sun_u", photo_sun.x)
	sky_mat.set_shader_parameter("photo_sun_elevation", photo_sun.y)
	sky_mat.set_shader_parameter("sun_u", a.x)
	sky_mat.set_shader_parameter("sun_elevation", a.y)


## For the direction to the game's sun: its place across the panorama in
## photo_sky.gdshader's mapping, and the height the photo's sun (at
## `photo_elevation` radians) is stretched to: the sun's own height, but
## no more than 40% lower or higher than the photo's, beyond which the
## clouds would visibly squash or smear.
static func sky_sun_mapping(to_sun: Vector3, photo_elevation: float) -> Vector2:
	var u := atan2(to_sun.x, -to_sun.z) / TAU + 0.5
	var e := asin(clampf(to_sun.normalized().y, -1.0, 1.0))
	return Vector2(u, clampf(e, photo_elevation * 0.6, minf(photo_elevation * 1.4, deg_to_rad(80.0))))


## How far through the round the player is (0 the first hole, 1 the last),
## for the "Through the round" time of day. Call before the hole's ground
## shade is baked, as the sun moves.
func set_round_progress(f: float) -> void:
	_round_progress = clampf(f, 0.0, 1.0)
	if _photo and _time_setting == GraphicsSettings.TimeOfDay.ROUND:
		_apply_time()
		_sun_energy = sun.light_energy
		_sun_color = sun.light_color
		_ambient_energy = environment.ambient_light_energy
		_choose_sky()


## The time of day as one of "morning", "midday", "afternoon" or "golden"
## (for the course's sound): the setting's own, or for "Through the round"
## the stretch of ROUND_TIMES the round has reached.
static func time_name(setting: int, progress: float) -> String:
	match setting:
		GraphicsSettings.TimeOfDay.MORNING, GraphicsSettings.TimeOfDay.DAWN:
			return "morning"
		GraphicsSettings.TimeOfDay.SUNSET:
			return "golden"
		GraphicsSettings.TimeOfDay.MIDDAY:
			return "midday"
		GraphicsSettings.TimeOfDay.GOLDEN:
			return "golden"
		GraphicsSettings.TimeOfDay.ROUND:
			var name: String = ROUND_TIMES[0][1]
			for r: Array in ROUND_TIMES:
				if progress + 0.12 >= r[0]:
					name = r[1]
			return name
	return "afternoon"


## The light of the time of day: TIMES for one setting, or a blend of
## them through the round.
static func time_light(setting: int, progress: float) -> Dictionary:
	match setting:
		GraphicsSettings.TimeOfDay.MORNING:
			return TIMES["morning"]
		GraphicsSettings.TimeOfDay.MIDDAY:
			return TIMES["midday"]
		GraphicsSettings.TimeOfDay.GOLDEN:
			return TIMES["golden"]
		GraphicsSettings.TimeOfDay.DAWN:
			return TIMES["dawn"]
		GraphicsSettings.TimeOfDay.SUNSET:
			return TIMES["sunset"]
		GraphicsSettings.TimeOfDay.OVERCAST:
			return TIMES["overcast"]
		GraphicsSettings.TimeOfDay.ROUND:
			for i in ROUND_TIMES.size() - 1:
				var a: Array = ROUND_TIMES[i]
				var b: Array = ROUND_TIMES[i + 1]
				if progress <= b[0]:
					return _blend(TIMES[a[1]], TIMES[b[1]], (progress - a[0]) / (b[0] - a[0]))
			return TIMES["golden"]
	return TIMES["afternoon"]


static func _blend(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	var out := {}
	for key: String in a:
		if a[key] is Color:
			out[key] = (a[key] as Color).lerp(b[key], f)
		else:
			out[key] = lerpf(a[key], b[key], f)
	return out


## Sets the sun, fill light and exposure for the time of day. Classic
## lighting keeps Links 2003's afternoon sun.
func _apply_time() -> void:
	_time = time_light(_time_setting, _round_progress) if _photo else TIMES["afternoon"]
	var elevation: float = _time.elevation if _photo else CLASSIC_SUN_ELEVATION
	sun.rotation_degrees = Vector3(-elevation, float(_time.bearing), 0.0)
	# Which way the sunlight travels, for the shadows drawn by shaders
	# (the crowd's, shaders/person_shadow.gdshader).
	RenderingServer.global_shader_parameter_set("sun_travel", -sun.transform.basis.z)
	RenderingServer.global_shader_parameter_set("sky_tint", Vector3(1, 1, 1))
	RenderingServer.global_shader_parameter_set("turf_tone", (1.0 if GraphicsSettings.is_forward_plus() else 1.35) if _photo else 0.0)
	RenderingServer.global_shader_parameter_set("people_light", people_light(_photo, GraphicsSettings.is_forward_plus()))
	RenderingServer.global_shader_parameter_set("people_bounce", people_bounce(_photo, GraphicsSettings.is_forward_plus(), _time))
	_set_grade_look()
	RenderingServer.global_shader_parameter_set("ground_sun_shadow", float(_time.get("shadow", 1.0)) if _photo else 1.0)
	if not _photo:
		environment.ambient_light_color = AMBIENT
		return
	var c: Color = _time.sun
	sun.light_color = c
	sun.light_energy = PHOTO_SUN_ENERGY * float(_time.energy)
	if not GraphicsSettings.is_forward_plus():
		# With the shade fill at COMPAT_SHADE_RATIO the web's sunlit turf
		# came out darker than Forward+'s (the green darker than the
		# fairway); a stronger sun lifts it without filling the shadows.
		sun.light_energy *= COMPAT_SUN_LIFT
	# Compatibility has no sky light, so its flat fill is a little stronger,
	# or shade goes near black.
	# (Measured against real course photos: our shade was far darker than
	# real shade, and the whole frame about a stop under.)
	var fill: float = _time.fill_fwd if GraphicsSettings.is_forward_plus() else _time.fill * COMPAT_FILL_LIFT
	environment.ambient_light_energy = PHOTO_AMBIENT_ENERGY * fill
	if _gi:
		# The bounced light does much of the fill's work.
		environment.ambient_light_energy *= 0.6
	environment.ambient_light_color = _time.ambient
	var fwd := GraphicsSettings.is_forward_plus()
	# Compatibility's turf measured about a stop's third darker than real
	# course photos once its colour matched them (Lab L* 51 against 56).
	_base_exposure = PHOTO_EXPOSURE * float(_time.exposure) * (1.0 if fwd else COMPAT_EXPOSURE_LIFT)
	environment.tonemap_exposure = _base_exposure * _adapt
	var sky: Color = _time.sky
	RenderingServer.global_shader_parameter_set("sky_tint", Vector3(sky.r, sky.g, sky.b))


## How much a camera opens up for a subject in deep tree shade: a TV
## camera or a photographer exposes for the golfer in the trees, so the shade
## reads bright and the sunlit fairway beyond goes pale, not the other way
## round (the eye does the same). About two thirds of a stop with the sun
## and most of the sky shut out.
const SHADE_ADAPT_MAX := 1.65
## The same on Compatibility, whose flat fill and stronger shade fill
## (COMPAT_SHADE_RATIO) already light the shade more: at 1.65 the pale
## bark went near white and a sun fleck on a face blew out.
const SHADE_ADAPT_MAX_COMPAT := 1.3
## How quickly the exposure follows (seconds to get most of the way), as a
## camera's auto-exposure eases rather than jumps.
const SHADE_ADAPT_TIME := 0.9
## How often the cover is measured (seconds).
const SHADE_ADAPT_EVERY := 0.2


## How shut in by tree crowns the point `at` is, from obstacles' CANOPY
## and SOLID shapes: x the share of the sky blocked (rays over the sky,
## each ring weighted by its share of the sky dome, so the open sky and
## sunlit ground all round a lone tree count, as they light a standing
## golfer from the side), y 1 if the sun is blocked, else 0. `sun_from`
## points from the ground to the sun.
static func shade_cover(obstacles: ObstacleField, at: Vector3, sun_from: Vector3) -> Vector2:
	if obstacles == null or obstacles.size() == 0:
		return Vector2.ZERO
	const REACH := 45.0
	var sun_blocked := 0.0 if obstacles.segment_hit(at, at + sun_from.normalized() * REACH).is_empty() else 1.0
	# Straight up and 3 rings of directions.
	var blocked := 0.0
	var total := 0.0
	var dirs := [[90.0, 1]]
	dirs.append([62.0, 4])
	dirs.append([38.0, 6])
	dirs.append([16.0, 8])
	for ring: Array in dirs:
		var el := deg_to_rad(float(ring[0]))
		var n: int = ring[1]
		for i in n:
			var az := TAU * (float(i) + (0.5 if n % 2 == 0 else 0.0)) / float(n)
			var d := Vector3(cos(el) * cos(az), sin(el), cos(el) * sin(az))
			var w := maxf(cos(el), 0.2)
			total += w
			if not obstacles.segment_hit(at, at + d * REACH).is_empty():
				blocked += w
	return Vector2(blocked / maxf(total, 1e-6), sun_blocked)


## The exposure lift for a subject with shade_cover `cover`: none in the
## open or in a lone tree's shadow on open ground, up to SHADE_ADAPT_MAX
## with the sun and most of the sky shut out.
static func shade_adapt_for(cover: Vector2, top := SHADE_ADAPT_MAX) -> float:
	var shut := cover.y * smoothstep(0.15, 0.75, cover.x)
	return lerpf(1.0, top, shut)


## Called every frame with where the camera's subject stands (a point
## about chest high) on the current hole: under trees the exposure opens up
## like a camera's, and closes again out in the open. Photoreal only;
## Classic keeps Links 2003's fixed light.
func adapt_to_shade(obstacles: ObstacleField, at: Vector3, delta: float) -> void:
	if not _photo:
		_adapt_target = 1.0
	else:
		_adapt_clock -= delta
		if _adapt_clock <= 0.0:
			_adapt_clock = SHADE_ADAPT_EVERY
			var top := SHADE_ADAPT_MAX if GraphicsSettings.is_forward_plus() else SHADE_ADAPT_MAX_COMPAT
			_adapt_target = shade_adapt_for(shade_cover(obstacles, at, sun.global_transform.basis.z), top)
	var k := 1.0 - exp(-delta * 3.0 / SHADE_ADAPT_TIME)
	var a := lerpf(_adapt, _adapt_target, clampf(k, 0.0, 1.0))
	if absf(a - _adapt) < 1e-4 and absf(a - _adapt_target) < 1e-4:
		return
	_adapt = a
	if _photo:
		environment.tonemap_exposure = _base_exposure * _adapt


## Jumps straight to the adaptation for `at` (a new hole, a camera cut).
func snap_shade(obstacles: ObstacleField, at: Vector3) -> void:
	_adapt_clock = 0.0
	adapt_to_shade(obstacles, at, 0.0)
	_adapt = _adapt_target
	if _photo:
		environment.tonemap_exposure = _base_exposure * _adapt


## The time of day's split tone and colour lift (post_process.gdshader
## grade_warm, grade_cool), Photoreal only.
func _set_grade_look() -> void:
	var warm := Vector4(1, 1, 1, 1)
	var cool := Vector3(1, 1, 1)
	if _photo and _time.has("warm"):
		var w: Color = _time.warm
		var c: Color = _time.cool
		warm = Vector4(w.r, w.g, w.b, float(_time.pop))
		cool = Vector3(c.r, c.g, c.b)
	RenderingServer.global_shader_parameter_set("grade_warm", warm)
	RenderingServer.global_shader_parameter_set("grade_cool", cool)


## How the golfer shaders light people (shaders/golfer_occlusion.gdshaderinc
## people_light): the lifts above are for the turf, and on a person they
## read as pale, flat skin and light cloth that blooms, so in Compatibility
## at Photoreal people take them back and get their fill light more from
## above than below, as from a sky. Forward+ and Classic leave people be.
## The fill is not cut all the way back: a person's shade side still gets
## the sky and the bounce off sunlit turf, and at 1/COMPAT_FILL_LIFT the
## shaded half of a shirt went near black once the sun got low.
const PEOPLE_COMPAT_FILL := 0.85


static func people_light(photo: bool, forward_plus: bool) -> Vector3:
	if not photo or forward_plus:
		return Vector3(1.0, 1.0, 0.0)
	return Vector3(1.0 / COMPAT_EXPOSURE_LIFT, PEOPLE_COMPAT_FILL, 1.0)


## The sunlit turf's light bounced up onto people's shaded sides
## (golfer_occlusion.gdshaderinc people_ground_bounce): Compatibility at
## Photoreal only, which has no sky light to carry the ground's colour.
## The sun's colour and strength through a grass green's reflectance,
## fitted so shaded khaki keeps its warmth (red to blue about 0.8 of the
## cloth's own, as in photos of golfers' shaded trousers) rather than
## the flat sky fill's cold grey.
const PEOPLE_BOUNCE := Vector3(0.34, 0.32, 0.16)


static func people_bounce(photo: bool, forward_plus: bool, time: Dictionary) -> Vector3:
	if not photo or forward_plus:
		return Vector3.ZERO
	var c: Color = time.get("sun", Color.WHITE)
	var k := float(time.get("energy", 1.0)) * float(time.get("shadow", 1.0))
	return Vector3(c.r * PEOPLE_BOUNCE.x, c.g * PEOPLE_BOUNCE.y, c.b * PEOPLE_BOUNCE.z) * k


## Sets the round's weather (RoundWeather; null for a fine day): cloud dims
## the sun, softens its shadows and greys the sky and haze, mist thickens
## the haze. Photoreal light only, except the mist, which Classic gets too.
func set_weather(w: RoundWeather) -> void:
	_weather_overcast = overcast_of(w.cloud) if w != null else 0.0
	_weather_fog = w.fog if w != null else 0.0
	_weather_rain = w.rain_amount() if w != null else 0.0
	_choose_sky()


## How much a cloud cover (0 to 1) hides the sun on average: scattered
## cloud leaves it out most of the time (the cloud shadows show the rest),
## a full deck hides it.
static func overcast_of(cloud: float) -> float:
	return smoothstep(0.35, 0.95, cloud)


## How much thicker the haze is in mist `fog` (0 to 1): up to about 11x,
## about 700 m visibility.
static func fog_scale(fog: float) -> float:
	return 1.0 + 10.0 * clampf(fog, 0.0, 1.0)


## The grey of a cloud deck, darker under rain.
static func deck_color(rain: float) -> Color:
	return Color(0.74, 0.77, 0.80).lerp(Color(0.55, 0.58, 0.62), clampf(rain, 0.0, 1.0))


## Photoreal light follows a sky the player picked: under cloud the sun
## dims and its shadows soften while the sky's fill light grows; a sunrise
## or sunset sky warms the sun. Classic and the photographed sky keep the
## light apply() set.
func _apply_weather() -> void:
	_apply_weather_light()
	_update_shade_fill()


## How bright shade is against sunlit ground in Photoreal on the
## Compatibility renderer, before the tone curve and grade. In Geograph
## photos of sunny courses, grass in a tree's shade reads about 55% as
## bright as grass in sun (sRGB green), a darker, bluer green. Compatibility
## has no sky light, and its tone curve and grade push the darks down, so
## with only the flat fill its shade came out near black (about 10%); 0.75
## here gives the photos' 55% on screen.
const COMPAT_SHADE_RATIO := 0.5
## How much stronger the sun is drawn in Compatibility (see _apply_time).
const COMPAT_SUN_LIFT := 1.3
## The same for Forward+. Its sky light fills the shade, but under the
## grade and SSAO tree shade still came out near black beside sunlit
## grass; 0.35 brings it to a darker green as in the photos (tuned on
## lavapipe renders of hole 2's tree line).
const FORWARD_SHADE_RATIO := 0.35
## The colour of that fill: skylight, a little bluer than the flat fill.
const SHADE_FILL_COLOR := Color(0.84, 0.92, 0.98)


## Sets the `shade_fill` global the ground, rough and fescue shaders use
## (shaders/ground_shade.gdshaderinc): in Photoreal, an
## even sky-coloured light added to the ground (rgb, as a share of its
## albedo) and how much the sun-and-fill lighting is scaled down to make
## room for it (a), so sunlit turf stays as bright as before and only the
## shade lifts. Off (0, 0, 0, 1) in Classic lighting.
func _update_shade_fill() -> void:
	var fill := Vector4(0.0, 0.0, 0.0, 1.0)
	if _photo:
		var ratio := FORWARD_SHADE_RATIO if GraphicsSettings.is_forward_plus() else COMPAT_SHADE_RATIO
		var amb := environment.ambient_light_energy * environment.ambient_light_color.get_luminance()
		# Flat ground in sun (floored so a low sun doesn't blow it up).
		var lit := amb + sun.light_energy * maxf(sin(deg_to_rad(-sun.rotation_degrees.x)), 0.25)
		var extra := maxf((ratio * lit - amb) / (1.0 - ratio), 0.0)
		var keep := lit / (lit + extra)
		var c := SHADE_FILL_COLOR * (extra * keep / SHADE_FILL_COLOR.get_luminance())
		fill = Vector4(c.r, c.g, c.b, keep)
	RenderingServer.global_shader_parameter_set("shade_fill", fill)


func _apply_weather_light() -> void:
	sun.light_energy = _sun_energy
	sun.light_color = _sun_color
	environment.ambient_light_energy = _ambient_energy
	sun.light_angular_distance = _sun_angle
	if _photo and _sun_angle > 0.0 and _time.has("soft"):
		sun.light_angular_distance = maxf(_sun_angle, float(_time.soft))
	sun.shadow_opacity = 1.0
	var tree_shadow := float(_time.get("shadow", 1.0)) if _photo else 1.0
	RenderingServer.global_shader_parameter_set("ground_sun_shadow", tree_shadow)
	if not _photo:
		return
	var picked := backdrop != null and backdrop.chosen and backdrop.has_sky
	if picked:
		var o := backdrop.overcast
		sun.light_energy = _sun_energy * (1.0 - 0.65 * o)
		environment.ambient_light_energy = _ambient_energy * (1.0 + 0.6 * o)
		if backdrop.warm:
			sun.light_color = Color(1.0, 0.78, 0.55)
		if GraphicsSettings.is_forward_plus():
			sun.light_angular_distance = maxf(_sun_angle, 4.0 * o)
	var w := _weather_overcast
	if w > 0.0:
		# The round's cloud: the sun behind the deck is weak and wide, so
		# shadows fade and soften, and the whole sky's light fills in. Under
		# rain the deck is thicker and the day darker.
		sun.light_energy *= 1.0 - (0.82 + 0.08 * _weather_rain) * w
		sun.light_color = sun.light_color.lerp(Color(0.96, 0.98, 1.0), w)
		environment.ambient_light_energy *= 1.0 + (0.55 - 0.2 * _weather_rain) * w
		if GraphicsSettings.is_forward_plus():
			sun.light_angular_distance = maxf(sun.light_angular_distance, 9.0 * w)
		# Compatibility can't soften shadows, so a weak sun's are faded.
		sun.shadow_opacity = 1.0 - 0.85 * w
		RenderingServer.global_shader_parameter_set("ground_sun_shadow", tree_shadow * (1.0 - 0.85 * w))
