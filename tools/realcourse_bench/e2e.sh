#!/bin/bash
# Builds a real course end to end as the game does, and audits it:
#   tools/realcourse_bench/e2e.sh slug "search words"
# Searches like the game (Nominatim), fetches the OSM data for the box the
# game asks Overpass for from the OSM API and serves it locally (public
# Overpass servers are often busy or blocked), then builds with the real
# tile, lidar, photo and land-cover services and runs e2e_audit.gd. Prints
# the build time, the longest frame gap and each hole's problems, then
# compares the course from above with a satellite picture of the place
# (look_export.gd, look_check.py: missing water, fescue drawn mown, missing
# sand; LOOK=0 skips it). Output in /tmp/rc. Dev tool only; nothing is
# committed.
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT=${GODOT:-godot}
slug=$1; q=$2
mkdir -p /tmp/rc
cd "$HERE/../.."
if [ ! -s /tmp/rc/$slug.place.json ]; then
	SEARCHOUT=/tmp/rc/$slug.place.json timeout 120 "$GODOT" --headless --path game -s "$HERE/e2e_build.gd" -- "$q" > /tmp/rc/$slug.search.log 2>&1
fi
[ -s /tmp/rc/$slug.place.json ] || { echo "$slug: search failed"; grep -E "FAILED|found" /tmp/rc/$slug.search.log; exit 1; }
if [ ! -s /tmp/rc/${slug}_op.json ]; then
	python3 -I "$HERE/osm_for_place.py" /tmp/rc/$slug.place.json /tmp/rc/${slug}_op.json > /tmp/rc/$slug.osm.log 2>&1 || { echo "$slug: OSM fetch failed"; tail -2 /tmp/rc/$slug.osm.log; exit 1; }
fi
port=$((8800 + RANDOM % 150))
python3 -I "$HERE/serve.py" /tmp/rc/${slug}_op.json $port & sp=$!
sleep 1
PLACE=/tmp/rc/$slug.place.json SLUG=$slug OVERPASS=http://127.0.0.1:$port timeout 900 "$GODOT" --headless --path game -s "$HERE/e2e_build.gd" -- "$q" > /tmp/rc/$slug.log 2>&1
kill $sp
grep -E "BUILT|FAILED|AUDIT|MAXGAP|SCRIPT ERROR|  hole" /tmp/rc/$slug.log | cut -c1-300 | sed "s/^/$slug: /"
if [ "${LOOK:-1}" != "0" ] && [ -s /tmp/rc/$slug.olc ]; then
	"$GODOT" --headless --path game -s "$HERE/look_export.gd" -- /tmp/rc/$slug.olc /tmp/rc/look_$slug > /dev/null 2>&1
	python3 -I "$HERE/look_check.py" /tmp/rc/look_$slug | sed "s/^/$slug: /"
fi
