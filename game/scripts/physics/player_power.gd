class_name PlayerPower
extends RefCounted
## How far the people playing hit each club (Settings > Hitting distance).
##
## Links 2003 let a player set how far each club goes: it looked the wanted
## distance up in its club distance table (CLUBDIST, ClubDistances) and made
## the first step that reaches it the club's power rating, which a full
## swing then strikes with (docs/formats/ls-archive.md). A profile here does
## the same with real distances for a kind of golfer, so the launch, flight,
## bounce and roll stay the game's own; only the full swing's power changes.
## Classic keeps the game's default ratings (112 for the driver down to 80
## for the wedges, about 276 yd with the driver).
##
## With the stand-in physics (StandardShotModel) a profile scales the full
## swing's ball speed by STANDARD_SPEED, measured so each club's total on
## flat fairway is the profile's (tests/run_tests.gd checks it).
##
## Only full swings change: chips, putts and launch monitor shots are as
## they were, and computer golfers keep their own calibrated power.

enum Profile { CLASSIC, AMATEUR, SCRATCH, TOUR }

const NAMES := ["Classic Links", "Amateur", "Scratch", "Tour pro"]
## What each profile is (the driver and 7 iron distances are added in the
## player's units by description()).
const DESCRIPTIONS := [
	"The game's own club distances: about %s with the driver in Links 2003's physics.",
	"An average club golfer: about %s with the driver, %s with a 7 iron.",
	"A scratch golfer: about %s with the driver, %s with a 7 iron.",
	"A tour pro: about %s with the driver, %s with a 7 iron.",
]

## The clubs of Club.standard_set, in its order (the putter is never changed).
const CLUBS := ["Dr", "3W", "5W", "3H", "4i", "5i", "6i", "7i", "8i", "9i", "PW", "SW", "LW"]

## Total yards (carry and roll on flat fairway, no wind) of a full swing
## with each club in CLUBS, for each profile past Classic. Ballpark figures
## from published shot-tracking averages: tour pros from tour launch
## monitor data (about 300 yd driving), scratch golfers about 260, and the
## average male club golfer about 225.
const TOTAL_YD := {
	Profile.AMATEUR: [225, 205, 190, 180, 165, 158, 150, 140, 130, 120, 110, 90, 70],
	Profile.SCRATCH: [260, 235, 220, 210, 190, 180, 170, 160, 148, 136, 125, 105, 85],
	Profile.TOUR: [300, 265, 248, 238, 212, 201, 190, 178, 165, 152, 140, 118, 95],
}

## StandardShotModel: the full swing's ball speed, as a share of the club's
## (Club.ball_speed_mps), that sends each club in CLUBS its TOTAL_YD on flat
## fairway with the stand-in physics (whose own clubs are tour launch
## monitor averages, so most clubs slow down). Measured with
## tests/calibrate_player_power.gd.
const STANDARD_SPEED := {
	Profile.AMATEUR: [0.703, 0.678, 0.664, 0.659, 0.658, 0.672, 0.709, 0.751, 0.774, 0.793, 0.827, 0.862, 0.861],
	Profile.SCRATCH: [0.851, 0.798, 0.787, 0.783, 0.761, 0.768, 0.808, 0.859, 0.875, 0.887, 0.918, 0.967, 0.988],
	Profile.TOUR: [1.062, 0.944, 0.922, 0.918, 0.866, 0.870, 0.910, 0.960, 0.976, 0.985, 1.014, 1.071, 1.081],
}

const METRES_PER_YARD := 0.9144


## DESCRIPTIONS[profile] with its distances in Units.
static func description(profile: int) -> String:
	if profile == 0:
		return DESCRIPTIONS[0] % Units.from_yards(276)
	var yd: Array = TOTAL_YD[profile]
	return DESCRIPTIONS[profile] % [Units.from_yards(yd[0]), Units.long_value(float(yd[7]) * METRES_PER_YARD)]


## Every profile and what it means, for the setting's tooltip.
static func tooltip() -> String:
	var lines := PackedStringArray(["How far your full swings go (chips, putts and computer golfers stay the same)."])
	for i in NAMES.size():
		lines.append("%s: %s" % [NAMES[i], description(i)])
	return "\n".join(lines)


static func clamp_profile(p: int) -> int:
	return clampi(p, Profile.CLASSIC, Profile.TOUR)


## The profile's full-swing total for `club` in metres, or a negative number
## when the profile leaves the club alone (Classic, the putter, a club not
## in CLUBS).
static func total_m(profile: int, club: Club) -> float:
	if profile == Profile.CLASSIC or club == null or club.is_putter or not TOTAL_YD.has(profile):
		return -1.0
	var i := CLUBS.find(club.short_name)
	if i < 0:
		return -1.0
	return float(TOTAL_YD[profile][i]) * METRES_PER_YARD


## LinksShotModel: the club's full-swing power rating for the profile, the
## way the game turns a wanted distance into a rating (ClubDistances
## .rating_for). Without the game's table the rating scales with the
## distance, as LinksShotModel.reach_scale does then. `classic` is the
## game's default rating for the club.
static func links_rating(profile: int, club: Club, classic: float, distances: ClubDistances) -> float:
	var want := total_m(profile, club)
	if want <= 0.0 or not LinksLaunch.CLUB_INDEX.has(club.short_name):
		return classic
	if distances != null:
		return float(distances.rating_for(LinksLaunch.CLUB_INDEX[club.short_name], want))
	if club.total_m <= 0.0:
		return classic
	return 100.0 * want / club.total_m


## StandardShotModel: the share of the club's ball speed a full swing
## leaves at (1 for Classic and the putter).
static func standard_speed(profile: int, club: Club) -> float:
	if profile == Profile.CLASSIC or club == null or club.is_putter or not STANDARD_SPEED.has(profile):
		return 1.0
	var i := CLUBS.find(club.short_name)
	return 1.0 if i < 0 else float(STANDARD_SPEED[profile][i])
