#!/bin/bash
# tools/realcourse_bench/stress.sh slug MODE: e2e_stress.gd on a place e2e.sh saved.
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT=${GODOT:-godot}
slug=$1; mode=$2
cd "$HERE/../.."
port=$((8950 + RANDOM % 40))
python3 -I "$HERE/serve.py" /tmp/rc/${slug}_op.json $port & sp=$!
sleep 1
PLACE=/tmp/rc/$slug.place.json MODE=$mode OVERPASS=http://127.0.0.1:$port timeout 1500 "$GODOT" --headless --path game -s "$HERE/e2e_stress.gd" > /tmp/rc/stress_${slug}_$mode.log 2>&1
kill $sp
grep -E "cancel at|build:|STRESS|SCRIPT ERROR" /tmp/rc/stress_${slug}_$mode.log
