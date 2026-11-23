class_name Units
## How distances, heights and speeds are shown: Settings > Units.
## Imperial (Links 2003, the default): yards, feet on and round the green,
## heights in feet, wind and ball speed in mph. Metric: metres everywhere
## (a decimal on short putts), wind and ball speed in km/h.
## Only the text changes: the game works in metres inside, and the meters
## keep their physics. GraphicsSettings sets `metric` when it loads or saves.

const YARDS_PER_METRE := 1.0 / 0.9144
const FEET_PER_METRE := 1.0 / 0.3048
const KMH_PER_MPH := 1.609344
const NAMES := ["Yards and feet (mph)", "Metres (km/h)"]

static var metric := false


## A long distance: "142 yd" or "130 m".
static func long(m: float) -> String:
	return "%d %s" % [long_value(m), long_unit()]


## long() in capitals, for the TV graphics: "142 YD" or "130 M".
static func long_caps(m: float) -> String:
	return long(m).to_upper()


## long() spelt out, for hole cards: "445 yards" or "407 metres".
static func long_words(m: float) -> String:
	return "%d %s" % [long_value(m), "metres" if metric else "yards"]


static func long_value(m: float) -> int:
	return roundi(m if metric else m * YARDS_PER_METRE)


static func long_unit() -> String:
	return "m" if metric else "yd"


## A distance stored in yards (career stats, CLUBDIST tables) as text.
static func from_yards(yards: float) -> String:
	return long(yards / YARDS_PER_METRE)


## A short distance, on and round the green: "12 ft", or "3.7 m" (whole
## metres from 10 m). `decimal` gives Imperial a decimal too ("4.5 ft").
static func short(m: float, decimal := false) -> String:
	if metric:
		return ("%.1f m" % m) if absf(m) < 10.0 else ("%d m" % roundi(m))
	var ft := m * FEET_PER_METRE
	return ("%.1f ft" % ft) if decimal else ("%d ft" % roundi(ft))


static func short_caps(m: float) -> String:
	return short(m).to_upper()


## A short distance's number alone, as a float in the shown unit.
static func short_value(m: float) -> float:
	return m if metric else m * FEET_PER_METRE


static func short_unit() -> String:
	return "m" if metric else "ft"


## A distance stored in feet (putting drills, gimme sizes) as text.
static func from_feet(feet: float) -> String:
	return short(feet / FEET_PER_METRE)


## A rise or fall: "+12 ft" / "-3 ft", or "+4 m"; "Level" under a foot.
static func rise(m: float) -> String:
	if absf(m) < 0.3048 * 0.5:
		return "Level"
	return "%+d %s" % [roundi(m if metric else m * FEET_PER_METRE), short_unit()]


## A height (ball apex): "92 ft" or "28 m".
static func height(m: float) -> String:
	return "%d %s" % [roundi(m if metric else m * FEET_PER_METRE), short_unit()]


## A wind or ball speed given in mph: "12 mph" or "19 km/h".
static func speed(mph: float) -> String:
	return "%d %s" % [speed_value(mph), speed_unit()]


static func speed_value(mph: float) -> int:
	return roundi(mph * KMH_PER_MPH if metric else mph)


static func speed_unit() -> String:
	return "km/h" if metric else "mph"
