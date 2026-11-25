#!/bin/bash
# Films one promo clip from the real game and cuts it into takes:
#   tools/promo/capture.sh NAME [key=value ...]
# runs tools/promo/clips/NAME.gd (see capture.gd) under xvfb with Forward+
# on Mesa's lavapipe, at 1920x1080 and 30 fps, and leaves
# /tmp/promo/out/NAME-N.mp4. SIZE=WxH changes the size, METHOD=gl_compatibility
# the renderer. Dev tool only.
HERE="$(cd "$(dirname "$0")" && pwd)"
GODOT=${GODOT:-godot}
name=$1; shift
size=${SIZE:-1920x1080}
method=${METHOD:-forward_plus}
dir=/tmp/promo/${TAG:-$name}
rm -rf "$dir"; mkdir -p "$dir" /tmp/promo/out
cd "$HERE/../.."
# The project asks for a 1600x900 window; override it for this run.
w=${size%x*}; h=${size#*x}
printf '[display]\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$w" "$h" > game/override.cfg
extra=()
if [ "$method" = forward_plus ]; then
	export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
	extra=(--rendering-driver vulkan)
fi
xvfb-run -a -s "-screen 0 ${size}x24" "$GODOT" --path game --rendering-method "$method" "${extra[@]}" \
	--fixed-fps 30 --disable-vsync --write-movie "$dir/f.png" --resolution "$size" \
	-s "$HERE/capture.gd" -- clip=tools/promo/clips/$name.gd "$@" > "$dir.log" 2>&1
rm -f game/override.cfg
grep -E "PROMO|SCRIPT ERROR|ERROR" "$dir.log" | head -20
python3 "$HERE/cut.py" "$dir" /tmp/promo/out
