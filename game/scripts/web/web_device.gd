class_name WebDevice
extends RefCounted
## What the browser build is running on, read once from the page: the real
## graphics chip, whether the browser itself calls WebGL slow on it, the
## processor cores, the memory and the screen. Godot's own adapter name in
## the browser is only "WebKit WebGL" on Chrome and Edge (they hide the chip
## unless asked through WEBGL_debug_renderer_info), so without this every
## desktop browser, software renderers and ten-year-old laptops included,
## started on the browser's higher tier. See docs/graphics.md.

enum Tier { LEAN, STANDARD, HIGH }

const PROBE := """(function () {
	var o = {renderer: '', vendor: '', caveat: false, cores: navigator.hardwareConcurrency || 0,
		memory: navigator.deviceMemory || 0, dpr: window.devicePixelRatio || 1,
		w: screen.width || 0, h: screen.height || 0, max_tex: 0};
	try {
		var c = document.createElement('canvas');
		var gl = c.getContext('webgl2', {failIfMajorPerformanceCaveat: true});
		if (!gl) { o.caveat = true; gl = c.getContext('webgl2'); }
		if (gl) {
			var e = gl.getExtension('WEBGL_debug_renderer_info');
			o.renderer = String(e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER));
			o.vendor = String(e ? gl.getParameter(e.UNMASKED_VENDOR_WEBGL) : gl.getParameter(gl.VENDOR));
			o.max_tex = gl.getParameter(gl.MAX_TEXTURE_SIZE) || 0;
			var l = gl.getExtension('WEBGL_lose_context');
			if (l) l.loseContext();
		}
	} catch (err) {}
	return JSON.stringify(o);
})()"""

## Chips that are software, or so old or so small that the browser's
## higher tier can't hold a frame rate on them (lower case, as the browser
## names them through ANGLE: "ANGLE (Intel, Intel(R) HD Graphics 520 ...)").
const SOFTWARE := ["swiftshader", "llvmpipe", "softpipe", "software", "microsoft basic render"]
const LEAN_GPUS := [
	# Intel before UHD: HD Graphics (to Kaby Lake, and the Celeron and
	# Pentium chips), GMA and the old Iris parts.
	"intel(r) hd graphics", "intel hd graphics", "mesa intel(r) hd", "mesa dri intel(r) hd", "gma",
	"iris(r) graphics 5", "iris(r) pro graphics", "iris(r) graphics 6", "haswell", "ivybridge", "ivy bridge",
	"sandybridge", "baytrail", "bay trail", "cherryview",
	# AMD's small APU graphics and old cards.
	"radeon r2", "radeon r3", "radeon r4", "radeon r5", "radeon r6", "radeon r7", "radeon hd",
	"vega 3 ", "vega 3)", "vega 6 ", "vega 6)", "stoney",
	# Old discrete cards.
	"geforce 6", "geforce 7", "geforce 8", "geforce 9", "geforce gt 2", "geforce gt 3", "geforce gt 4",
	"geforce gt 6", "geforce gt 7", "geforce 3", "geforce 4", "quadro fx", "nvs ",
	# Phone and tablet chips.
	"mali-4", "mali-t", "mali-g5", "mali-g31", "mali-g51", "mali-g52", "adreno (tm) 3", "adreno (tm) 4",
	"adreno (tm) 5", "adreno (tm) 610", "adreno (tm) 612", "adreno (tm) 613", "powervr", "videocore",
]
## Chips that run the browser build's middle tier well but not its top
## one: Intel's UHD Graphics (2017 to 2021 laptops), Iris Plus, AMD's
## Vega 8 and 10 laptop graphics, and the GeForce MX laptop parts.
const STANDARD_GPUS := [
	"uhd graphics", "iris(r) plus", "iris plus", "vega 8", "vega 10", "vega 11", "radeon(tm) vega",
	"geforce mx", "gtx 6", "gtx 7", "gtx 9",
]
## Phone and tablet chips the browser's higher tier is known to run well on.
const GOOD_MOBILE := ["apple", "adreno (tm) 6", "adreno (tm) 7", "adreno (tm) 8", "mali-g7", "mali-g6", "immortalis", "xclipse"]

static var _info: Dictionary = {}
## Tests set this to classify a made-up device.
static var override_info: Dictionary = {}


## The page's answer (see PROBE), read once; empty off the web.
static func info() -> Dictionary:
	if not override_info.is_empty():
		return override_info
	if not _info.is_empty() or not OS.has_feature("web"):
		return _info
	var text: Variant = JavaScriptBridge.eval(PROBE, true)
	var parsed: Variant = JSON.parse_string(str(text)) if text != null else null
	_info = parsed if parsed is Dictionary else {"renderer": ""}
	print("WebDevice: %s" % JSON.stringify(_info))
	return _info


## The graphics chip's name, lower case ("" when the browser won't say).
static func gpu() -> String:
	var i := info()
	var name := str(i.get("renderer", ""))
	if name == "" or name.to_lower().contains("webkit webgl"):
		name = RenderingServer.get_video_adapter_name() if OS.has_feature("web") else ""
	return name.to_lower()


static func is_software() -> bool:
	var g := gpu()
	for s: String in SOFTWARE:
		if g.contains(s):
			return true
	return false


## The tier the browser build starts on: LEAN on software rendering, when
## the browser says WebGL would be slow here, on old or small graphics
## chips (LEAN_GPUS) and on machines with two cores or 2 GB or less;
## STANDARD on the middle chips (STANDARD_GPUS), phones not known to be
## good, 4 GB machines and chips the browser won't name on four cores or
## fewer; HIGH on Apple's chips, good phone chips and other desktop graphics.
static func tier(mobile: bool, ios: bool) -> int:
	var i := info()
	var g := gpu()
	var cores := int(i.get("cores", 0))
	var memory := float(i.get("memory", 0.0))
	if is_software() or bool(i.get("caveat", false)):
		return Tier.LEAN
	if (cores > 0 and cores <= 2) or (memory > 0.0 and memory <= 2.0):
		return Tier.LEAN
	for slow: String in LEAN_GPUS:
		if g.contains(slow):
			return Tier.LEAN
	var top := Tier.HIGH
	for mid: String in STANDARD_GPUS:
		if g.contains(mid):
			top = Tier.STANDARD
	if memory > 0.0 and memory <= 4.0:
		top = mini(top, Tier.STANDARD)
	if g.contains("apple"):
		return top  # iPhones, iPads and Macs: Safari names only "Apple GPU"
	if ios:
		return top
	if mobile:
		for good: String in GOOD_MOBILE:
			if g.contains(good):
				return top
		return Tier.STANDARD
	if g == "" or g.contains("webkit") or g.contains("mozilla"):
		# The browser hides the chip (Firefox resisting fingerprinting):
		# the cores are the only hint left.
		return mini(top, Tier.HIGH if cores >= 8 else Tier.STANDARD)
	return top


## The device pixel ratio the page draws at (2 on a Retina screen).
static func pixel_ratio() -> float:
	return maxf(1.0, float(info().get("dpr", 1.0)))
