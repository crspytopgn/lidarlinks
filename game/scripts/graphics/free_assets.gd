class_name FreeAssets
extends RefCounted
## The free (CC0) textures and sky from Poly Haven and ambientCG that the public build uses
## instead of the original art. tools/fetch_free_assets.py downloads them into
## res://free_assets/; they aren't in the repository, so everything here
## returns null when they haven't been fetched and callers fall back to plain
## shading.

const DIR := "res://free_assets/"
const GROUNDS: Array[String] = ["grass", "rough", "sand"]


## `slot` is "grass", "rough", "sand", "path", "dirt", "cliff" or a
## finish ("finish_beach" and so on, see FINISHES); `map` is "albedo", "normal", "height" or
## "roughness".
static func ground(slot: String, map: String) -> Texture2D:
	return _load("%s_%s.jpg" % [slot, map])


## The ground slot that stands in for a surface: "sand", "rough" (rough,
## deep rough, out of bounds, water banks) or "grass" (the mown surfaces).
static func slot_for(surface: Surface.Type) -> String:
	match surface:
		Surface.Type.SAND:
			return "sand"
		Surface.Type.ROUGH, Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS, Surface.Type.WATER:
			return "rough"
	return "grass"


static func has_grounds() -> bool:
	for slot in GROUNDS:
		if ground(slot, "albedo") == null:
			return false
	return true


## The ground finishes (terrain.gdshader's finish_tex, DesignedTerrain.
## Finish), in layer order: what bare ground is where it isn't turf.
## "rock" is the cliff slot's scan. Each is a CC0 photoscan fetched by
## tools/fetch_free_assets.py as finish_<name>_albedo/normal.jpg.
const FINISHES: Array[String] = ["beach", "pine", "mud", "hardpan", "rock"]
## Metres per tile of each finish's scan (its real size).
const FINISH_METRES: Array[float] = [2.0, 2.0, 2.4, 4.0, 3.0]
static var _finish_array: Texture2DArray
static var _finish_luma := PackedFloat32Array()


## The finishes' albedos then normal maps as one texture array (one
## sampler: Compatibility has few), each layer `size` square, or null when
## any is missing. 1024 on Forward+, 512 in Compatibility (the browser's
## video memory).
static func finish_array() -> Texture2DArray:
	if _finish_array != null:
		return _finish_array
	var size := 1024 if GraphicsSettings.is_forward_plus() else 512
	var albedos: Array[Image] = []
	var normals: Array[Image] = []
	var luma := PackedFloat32Array()
	for name in FINISHES:
		var slot := "cliff" if name == "rock" else "finish_" + name
		var a := ground(slot, "albedo")
		var n := ground(slot, "normal")
		if a == null or n == null:
			return null
		var mean := mean_color(a).srgb_to_linear()
		luma.append(mean.get_luminance())
		var ai := _layer(a, size)
		var ni := _layer(n, size)
		if ai == null or ni == null:
			return null
		albedos.append(ai)
		normals.append(ni)
	var arr := Texture2DArray.new()
	if arr.create_from_images(albedos + normals) != OK:
		return null
	_finish_array = arr
	_finish_luma = luma
	return arr


static func _layer(tex: Texture2D, size: int) -> Image:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != size or img.get_height() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


## Mean luminance (linear) of each finish's photo, after finish_array().
static func finish_luma() -> PackedFloat32Array:
	return _finish_luma


## The normal map of a garment's weave for the realistic golfers:
## `garment` is "shirt", "trousers" or "shoes" (ambientCG scans), or null.
static func fabric_normal(garment: String) -> Texture2D:
	return _load("fabric_%s_normal.jpg" % garment)


## A tree texture: "bark_albedo.jpg", "bark_normal.jpg" (Poly Haven) or
## "leaf_albedo.png", "leaf_opacity.png" (ambientCG), or null.
static func tree_texture(file: String) -> Texture2D:
	return _load(file)


static var _sky: Texture2D
static var _sky_loaded := false
static var _sky_sun := Vector2(-2.0, 0.0)  ## sky_sun() of the sky, once read


## The equirectangular HDR sky panorama, or null. Read once from
## sky_panorama.olsky, which tools/fetch_free_assets.py writes (see
## tools/sky_pack.py): the same RGB9E5 pixels as Godot's import of the .hdr,
## deflated to half the size.
static func sky() -> Texture2D:
	if not _sky_loaded:
		_sky_loaded = true
		_sky = _load_packed_sky(DIR + "sky_panorama.olsky")
	return _sky


static var _overcast_sky: Texture2D
static var _overcast_loaded := false


## The bright overcast panorama for the "Soft overcast" time of day
## (sky_overcast_panorama.olsky), or null when it wasn't fetched.
static func overcast_sky() -> Texture2D:
	if not _overcast_loaded:
		_overcast_loaded = true
		_overcast_sky = _load_packed_sky(DIR + "sky_overcast_panorama.olsky")
	return _overcast_sky


## sky_sun() of the free sky, worked out once.
static func free_sky_sun() -> Vector2:
	if _sky_sun.x < -1.5:
		_sky_sun = sky_sun(sky())
	return _sky_sun


static func _load_packed_sky(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_buffer(8).slice(0, 6).get_string_from_ascii() != "OLSKY1":
		return null
	var width := f.get_32()
	var height := f.get_32()
	var size := f.get_32()
	if size != width * height * 4:
		return null
	var data := f.get_buffer(f.get_length() - f.get_position()).decompress(size, FileAccess.COMPRESSION_DEFLATE)
	if data.size() != size:
		return null
	return ImageTexture.create_from_image(Image.create_from_data(width, height, false, Image.FORMAT_RGBE9995, data))


## Where the sun is in a sky panorama: (across 0 to 1, height in radians),
## from its brightest patch after box-filtering it down (so a cloud edge
## can't win over the sun's disc). (-1, 0) when nothing stands out enough
## to be a sun, as under a grey sky.
static func sky_sun(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2(-1.0, 0.0)
	var img := tex.get_image()
	if img == null or img.is_empty():
		return Vector2(-1.0, 0.0)
	return sun_in_image(img)


static func sun_in_image(source: Image) -> Vector2:
	var img := source.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBF)
	while img.get_width() > 256:
		img.shrink_x2()
	var w := img.get_width()
	var h := img.get_height()
	var best := 0.0
	var at := Vector2i.ZERO
	var sum := 0.0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum += l
			if l > best:
				best = l
				at = Vector2i(x, y)
	if best < 20.0 * sum / float(w * h):
		return Vector2(-1.0, 0.0)
	return Vector2((at.x + 0.5) / w, PI * (0.5 - (at.y + 0.5) / h))


## Average colour of a texture: halved with a box filter down to a few
## pixels (a straight resize to one pixel samples only a handful of them).
static func mean_color(tex: Texture2D) -> Color:
	var img := tex.get_image()
	if img == null or img.is_empty():
		return Color(0.5, 0.5, 0.5)
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGB8)
	while img.get_width() > 8 and img.get_height() > 8:
		img.shrink_x2()
	var sum := Color(0, 0, 0)
	for y in img.get_height():
		for x in img.get_width():
			sum += img.get_pixel(x, y)
	var n := float(img.get_width() * img.get_height())
	return Color(sum.r / n, sum.g / n, sum.b / n)


static var _vram := {}  ## path -> the block-compressed copy (desktop)


## The private Megascans pack (docs/megascans-pack.md): baked plant
## textures named like the free ones (foliage/fescue.png), which replace
## them where present, and in ground/ the blade detail of a photoscanned
## lawn for the mown turf (Materials.terrain). Never in the
## repository or the web build: the scans' licence lets them be used, not
## passed on. OL_MEGASCANS overrides the folder (the pack's root, holding
## foliage/).
const MEGASCANS_DIR := "user://megascans/"
## The free pack (docs/free-pack.md): the same layout baked from CC0 scans
## (Poly Haven, ambientCG) by tools/fetch_free_assets.py, so every desktop
## build has scanned plants, rocks, woodland debris and surfaces. Each
## feature reads the private pack's manifest when it has one and this one
## otherwise. Forward+ only: not in the web export (its download budget)
## nor read in Compatibility (its video memory), and off with
## OL_FREE_PACK=0 (to compare before and after).
const FREE_PACK_DIR := "res://free_assets/pack/"
static var free_pack := OS.get_environment("OL_FREE_PACK") != "0"


static func megascans_dir() -> String:
	if OS.has_feature("web"):
		return ""
	var env := OS.get_environment("OL_MEGASCANS")
	return env.path_join("") if not env.is_empty() else MEGASCANS_DIR


## The packs to read, best first: the private one, then the free one.
static func pack_dirs() -> PackedStringArray:
	var out := PackedStringArray()
	if OS.has_feature("web"):
		return out
	out.append(megascans_dir())
	# Compatibility keeps textures uncompressed, so the free pack would
	# add about 100 MB of video memory there (the low-end tier's budget):
	# it is for Forward+ only, like the web build that leaves it out.
	if free_pack and GraphicsSettings.is_forward_plus():
		out.append(FREE_PACK_DIR)
	return out


## The pack whose `manifest` (such as "rocks/rocks.json") a feature reads:
## the private pack's when it has one, else the free pack's; "" for none.
static func pack_dir(manifest: String) -> String:
	for dir in pack_dirs():
		if FileAccess.file_exists(dir + manifest):
			return dir
	return ""


## A texture from a pack's `folder` (foliage/ or ground/), or null: the
## private pack's file, else the free pack's. Mipmapped, and
## block-compressed like the free ones on the desktop; halved to 1K in
## Compatibility, which keeps them uncompressed.
static func _load_megascans(file: String, folder := "foliage/", normal := false, max_size := 0) -> Texture2D:
	var path := ""
	for dir in pack_dirs():
		if FileAccess.file_exists(dir + folder + file):
			path = dir + folder + file
			break
	if path.is_empty():
		return null
	if _vram.has(path):
		return _vram[path]
	var img := read_image(path)
	if img == null or img.is_empty():
		return null
	var cap := 1024 if not gpu_compress() else 1 << 30
	if max_size > 0:
		cap = mini(cap, max_size)
	if img.get_width() > cap:
		img.resize(cap, cap * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	# Normal maps stay uncompressed: S3TC blocks show as facets in them.
	if gpu_compress() and not normal:
		img.compress(Image.COMPRESS_S3TC)
	var tex := ImageTexture.create_from_image(img)
	_vram[path] = tex
	return tex


## An image file read as it is: from the user's folder, or from the free
## pack in the game's own files (kept as they are, not imported, so they
## load the same way in an exported game).
static func read_image(path: String) -> Image:
	if not path.begins_with("res://"):
		return Image.load_from_file(path)
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match path.get_extension().to_lower():
		"webp":
			err = img.load_webp_from_buffer(bytes)
		"png":
			err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(bytes)
	return img if err == OK else null


## A texture under the pack's surfaces/ folder (ScannedSurfaces), or null.
static func megascans_surface(file: String, normal := false) -> Texture2D:
	return _load_megascans(file, "surfaces/", normal) if not file.is_empty() else null


## A texture under the pack's foliage/ folder (such as "cards/x.png"), or
## another of its folders (such as "rocks/"), no wider than `max_size` (0
## for as baked), or null without a pack.
static func megascans_texture(file: String, folder := "foliage/", normal := false, max_size := 0) -> Texture2D:
	return _load_megascans(file, folder, normal, max_size) if not file.is_empty() else null


## A texture anywhere in the pack (such as "debris/litter_leaves.png"), or
## null without a pack. Compatibility keeps them to `compat_size`, as it
## stores them uncompressed.
static func megascans_pack_texture(file: String, normal := false, compat_size := 512) -> Texture2D:
	return _load_megascans(file, "", normal, 0 if gpu_compress() else compat_size) if not file.is_empty() else null


static func _load(file: String) -> Texture2D:
	var scan := _load_megascans(file)
	if scan != null:
		return scan
	var path := DIR + file
	if not ResourceLoader.exists(path):
		return null
	if _vram.has(path):
		return _vram[path]
	var tex := load(path) as Texture2D
	if tex != null and gpu_compress():
		tex = compressed(tex)
		_vram[path] = tex
	return tex


## Whether textures are block-compressed for the graphics card as they
## load. They're imported as lossy WebP, small to download but stored
## uncompressed in video memory (a 2K map with mipmaps is 22 MB). On the
## desktop, BC (S3TC) compression packs them 4 to 8 times smaller and is
## sampled faster, with no visible change at game distances. The browser
## keeps the WebP, as phones there can't read S3TC, and so does
## Compatibility, whose video memory budget in CI stands for the browser.
static func gpu_compress() -> bool:
	# Exported games have no BC compressor (it's in the editor build only),
	# so this saves memory only when run from the editor, as CI does.
	return GraphicsSettings.is_forward_plus() and not OS.has_feature("web") \
		and not OS.has_feature("template") and RenderingServer.has_os_feature("s3tc")


## A block-compressed copy of `tex` (BC1, or BC3 with alpha), with mipmaps.
static func compressed(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null or img.is_empty() or img.is_compressed():
		return tex
	if not img.has_mipmaps():
		img.generate_mipmaps()
	if img.compress(Image.COMPRESS_S3TC) != OK:
		return tex
	return ImageTexture.create_from_image(img)
