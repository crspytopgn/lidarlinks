class_name ClubDistances
extends RefCounted
## Links 2003's own club distance table, CLUBDIST in the player's
## GRAPHICS.LS (docs/formats/ls-archive.md): for each of its 19 clubs, the
## total distance in feet (carry and roll, flat ground, no wind) of a full
## swing at every second point of power, the first value at 2 points and
## the last at 128. The game reads it to
## turn the distance a player wants from a club into the club's power
## rating, the first step that goes that far. A club's distance is its row
## at its rating (LinksMouse.MAX_POWER): 827 ft for the driver at 112.
## Our port of the game's flight and roll (LinksShotModel) sends every
## club within about 1% of its row.
## Nothing of the table is in the repository; it is read at run time.

const ENTRY := "CLUBDIST"
const HEADER_BYTES := 16
const CLUBS := 19
const STEPS := 64
const POWER_PER_STEP := 2.0
const METRES_PER_FOOT := 0.3048
## The most a row may fall from one step to the next, as a share of its top.
const MAX_DIP := 0.03

var _feet := PackedInt32Array()  ## CLUBS rows of STEPS values


## Null unless `bytes` is the table (a header, then 19 rows of 64
## little-endian 16-bit values, each row rising). The game made the table
## with its own physics, which isn't always rising: the disc's lob wedge row
## dips 3 ft (275 then 272) at 92 points, so a row may fall back by up to
## MAX_DIP of its top value.
static func parse(bytes: PackedByteArray) -> ClubDistances:
	if bytes.size() < HEADER_BYTES + CLUBS * STEPS * 2:
		return null
	var t := ClubDistances.new()
	t._feet.resize(CLUBS * STEPS)
	for i in CLUBS * STEPS:
		t._feet[i] = bytes.decode_u16(HEADER_BYTES + 2 * i)
	for c in CLUBS:
		var top := t._feet[c * STEPS + STEPS - 1]
		if top <= 0:
			return null
		for k in range(1, STEPS):
			if t._feet[c * STEPS + k - 1] - t._feet[c * STEPS + k] > MAX_DIP * top:
				return null
	return t


## From the configured game folder's GRAPHICS.LS, or null.
static func from_game_folder() -> ClubDistances:
	var path := GameFolder.find_file(PackedStringArray(HudArt.ARCHIVE_NAMES))
	if path.is_empty():
		return null
	var archive := LsArchiveFile.open(path)
	if archive == null or not archive.has(ENTRY):
		return null
	return parse(archive.read(ENTRY))


## Total distance in metres of a full swing with the game's club `club`
## (LinksLaunch.CLUB_INDEX) at `power` points, between the table's steps
## in a straight line (and from nothing at 0 points).
func total_m(club: int, power: float) -> float:
	var c := clampi(club, 0, CLUBS - 1)
	var x := clampf(power / POWER_PER_STEP - 1.0, -1.0, STEPS - 1.0)
	if x < 0.0:
		return (x + 1.0) * _feet[c * STEPS] * METRES_PER_FOOT
	var k := mini(int(x), STEPS - 2)
	var a := float(_feet[c * STEPS + k])
	var b := float(_feet[c * STEPS + k + 1])
	return lerpf(a, b, x - k) * METRES_PER_FOOT


## The power rating the game gives club `club` for a wanted total of
## `metres`: the first step that reaches it (the game's own search).
func rating_for(club: int, metres: float) -> int:
	var c := clampi(club, 0, CLUBS - 1)
	var feet := metres / METRES_PER_FOOT
	for k in STEPS:
		if _feet[c * STEPS + k] >= feet:
			return int(POWER_PER_STEP) * (k + 1)
	return int(POWER_PER_STEP) * STEPS
