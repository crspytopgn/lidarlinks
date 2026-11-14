class_name MegascansCards
extends RefCounted
## The plant cards in the private Megascans pack (docs/megascans-pack.md):
## one 2 x 2 card atlas per Megascans 3D plant, in the FescueField layout,
## listed in foliage/cards.json by tools/megascans/build_pack.py. The
## foliage dresser picks from them by kind, golf role or the ground's cover
## (CourseTerrain.cover_at()). Empty without a pack, and always on the web.

const MANIFEST := "foliage/cards.json"
const KINDS := ["grass", "fern", "flower", "rush", "reed", "shrub"]

## What suits each cover (CourseShape.COVERS), best first, as golf roles.
const COVER_ROLES := {
	"heath": ["heath", "scrub", "links_fescue"],
	"scrub": ["scrub", "woodland_edge"],
	"wetland": ["water_edge"],
	"dune": ["dune", "links_fescue"],
	"meadow": ["meadow", "links_fescue"],
}

static var _cards: Array[Dictionary] = []
static var _loaded := false


## Every card: {"uid", "title", "kind", "height_m", "roles", "file"}.
static func cards() -> Array[Dictionary]:
	if not _loaded:
		_loaded = true
		var dir := FreeAssets.megascans_dir()
		if not dir.is_empty() and FileAccess.file_exists(dir + MANIFEST):
			_cards = parse(FileAccess.get_file_as_string(dir + MANIFEST))
	return _cards


## The cards in a cards.json text; bad entries are skipped.
static func parse(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var data: Variant = JSON.parse_string(text)
	var list: Array = data.get("cards", []) if data is Dictionary else []
	for c: Variant in list:
		if not c is Dictionary or str(c.get("file", "")).is_empty() or not KINDS.has(str(c.get("kind", ""))):
			continue
		var roles := PackedStringArray()
		for r: Variant in c.get("roles", []):
			roles.append(str(r))
		out.append({"uid": str(c.get("uid", "")), "title": str(c.get("title", "")), "kind": str(c["kind"]),
			"height_m": clampf(float(c.get("height_m", 0.7)), 0.05, 6.0), "roles": roles, "file": str(c["file"])})
	return out


static func for_kind(kind: String, from: Array[Dictionary] = cards()) -> Array[Dictionary]:
	return from.filter(func(c: Dictionary) -> bool: return c["kind"] == kind)


static func for_role(role: String, from: Array[Dictionary] = cards()) -> Array[Dictionary]:
	return from.filter(func(c: Dictionary) -> bool: return (c["roles"] as PackedStringArray).has(role))


## The cards for a cover, from its best-suited role that has any.
static func for_cover(cover: String, from: Array[Dictionary] = cards()) -> Array[Dictionary]:
	for role: String in COVER_ROLES.get(cover, []):
		var found := for_role(role, from)
		if not found.is_empty():
			return found
	return []


## The card's atlas (the plant stands on the bottom centre of each cell),
## or null when it can't be read.
static func atlas(card: Dictionary) -> Texture2D:
	return FreeAssets.megascans_texture(str(card.get("file", "")))
