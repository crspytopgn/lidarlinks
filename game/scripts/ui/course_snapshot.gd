class_name CourseSnapshot
extends SubViewport
## Takes a course's picture for the course pickers (CoursePictures): one
## frame of the round's own 3D world, from a camera high over the tee
## looking down the hole (a broadcast drone shot), with the round's look
## (its PostProcess grade; no depth of field). It renders off screen into its own
## small viewport once, so the player's view and the HUD are untouched, and
## then frees itself. Works on both renderers.

## Rendered at twice the saved size and scaled down, for smooth edges.
const RENDER_SIZE := CoursePictures.SIZE * 2
## The camera: this far down the hole from the tee and above it (so the
## golfers and any gallery on the tee stay out of the frame), looking at a
## point this far down the hole (or the green, if closer), with this
## vertical lens.
const AHEAD_M := 12.0
const UP_M := 36.0
const LOOK_M := 210.0
const LOOK_SHARE := 0.7
const FOV := 46.0
## Frames to let the hole settle (grass, trees, shadows) before the shot.
const SETTLE_FRAMES := 45

signal saved(key: String, ok: bool)

var key := ""
var _camera: Camera3D
var _frames := 0
var _shot := false


## Where the camera stands and what it looks at for `hole`: [eye, target].
static func framing(hole: HoleData) -> Array[Vector3]:
	var tee := hole.tee
	var reach := minf(LOOK_M, maxf(hole.length_m() * LOOK_SHARE, 40.0))
	var target := hole.aim_point(tee, reach) if hole.terrain != null else hole.pin
	var flat := Vector3(target.x - tee.x, 0.0, target.z - tee.z)
	var dir := Vector3(0, 0, 1) if flat.length() < 1.0 else flat.normalized()
	var eye := tee + dir * AHEAD_M + Vector3.UP * UP_M
	if hole.terrain != null:
		# Keep clear of rising ground under the camera.
		eye.y = maxf(eye.y, hole.terrain.height_at(eye.x, eye.z) + UP_M * 0.6)
	return [eye, target]


## Starts a picture of `hole` for course `key`, in `host`'s 3D world, with
## `camera`'s draw distance and `post`'s grade (either may be null).
static func take(host: Node, course_key: String, hole: HoleData, camera: Camera3D, post: PostProcess) -> CourseSnapshot:
	var snap := CourseSnapshot.new()
	snap.key = course_key
	snap.size = RENDER_SIZE
	snap.world_3d = host.get_viewport().world_3d
	# Nothing is drawn until the hole has settled: then one frame.
	snap.render_target_update_mode = SubViewport.UPDATE_DISABLED
	snap.transparent_bg = false
	snap.msaa_3d = Viewport.MSAA_DISABLED
	snap._camera = Camera3D.new()
	snap._camera.fov = FOV
	snap._camera.near = 0.3
	snap._camera.far = camera.far if camera != null else 3000.0
	if camera != null:
		snap._camera.cull_mask = camera.cull_mask
	snap.add_child(snap._camera)
	if post != null and post.visible:
		var layer := CanvasLayer.new()
		var rect := ColorRect.new()
		var mat := post.material().duplicate() as ShaderMaterial
		mat.set_shader_parameter("shimmer", 0.0)
		mat.set_shader_parameter("grain", 0.0)
		rect.material = mat
		rect.size = Vector2(RENDER_SIZE)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(rect)
		snap.add_child(layer)
	var f := framing(hole)
	host.add_child(snap)
	snap._camera.look_at_from_position(f[0], f[1], Vector3.UP)
	snap._camera.current = true
	return snap


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE_FRAMES or _shot:
		return
	_shot = true
	render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_texture().get_image()
	var ok := CoursePictures.save(key, img) == OK
	saved.emit(key, ok)
	queue_free()
