#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# The tutorial: one activity, one desk, driven by real input in a hidden nest
# (a virtual framebuffer, so nothing opens on your desktop), each step held
# long enough to read and captioned with what the hand did. Writes
# build/tutorial/tutorial.gif and tutorial.mp4; `make tutorial` copies the gif
# into docs/images for the README.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export NEST_VIRTUAL=1
# shellcheck source=nest.sh
source "$HERE/dev/nest.sh"
# shellcheck source=../tests/lib.sh
source "$HERE/tests/lib.sh"
OUT=$HERE/build/tutorial
mkdir -p "$OUT"
rm -f "$OUT"/frame-*.png "$OUT"/tutorial.gif "$OUT"/tutorial.mp4
have_input || { echo "fakeinput not built: make tools"; exit 1; }

down >/dev/null 2>&1 || true
up || true
fixtures >/dev/null 2>&1 || true
setcfg Passthrough false
setcfg SmoothZoom true
setcfg WindowPhysics true
setcfg MovesGlide true
# One activity: the second seeded one goes, so the plane has one desk.
c state >/dev/null
[ "$(sget nactivities)" -gt 1 ] && { c "rmactivity 1" >/dev/null; sleep 1.2; }
arrange >/dev/null
c open >/dev/null; c home >/dev/null
# Two windows on the desk, three far off to the right, off-screen: the
# plane's point is that they are there all the same.
c "placeby KCalc 160 180 480 420" >/dev/null
c "placeby Konsole 760 460 620 420" >/dev/null
c "placeby sample.txt 2700 220 700 520" >/dev/null
c "placeby Gwenview 3500 260 460 420" >/dev/null
c "placeby Dolphin 3100 820 700 360" >/dev/null
c commit >/dev/null
sleep 1

FRAME=0
CAPTION=""
STEP=0
# shot N: N frames of the current caption, ~0.35 s apart.
shots() {
    local n=$1 f
    for _ in $(seq 1 "$n"); do
        FRAME=$((FRAME + 1))
        f="$OUT/frame-$(printf '%03d' "$FRAME").png"
        shot "$f" >/dev/null 2>&1
        [ -s "$f" ] || continue
        magick "$f" -gravity south -background '#000000c0' \
            -fill white -font DejaVu-Sans-Bold -pointsize 34 \
            -splice 0x0 \( -size 1920x84 xc:'#0b0d12d8' \) -gravity south -composite \
            -gravity south -annotate +0+24 "$CAPTION" "$f" 2>/dev/null
    done
}
step() { STEP=$((STEP + 1)); CAPTION="$STEP. $1"; }

step "This is your desktop. Windows live on one endless plane."
shots 5
step "Step out: the chord, a screen corner, or the wheel on the wallpaper."
c open >/dev/null
c "zoom 0.45 960 540" >/dev/null
sleep 0.9
shots 6
step "The far windows were here all along, off-screen. Rest on one to light it."
input move 1760 420
sleep 1.2
shots 5
step "Drag the plane to pan. Flick a window and it glides."
{ printf 'move 1100 900\nsleep 60\ndown\nsleep 60\n'; for _ in $(seq 1 12); do printf 'rel -25 0\nsleep 20\n'; done; printf 'up\n'; } | input >/dev/null 2>&1
sleep 0.8
shots 4
step "Double-click a window to fly there and step in."
# The double-click's own path (focusWindow), driven by the debug verb: a
# synthetic double-click lands as two separate clicks often enough to make
# the recording unreliable.
c state >/dev/null
c "focus $(eget sample.txt index)" >/dev/null
sleep 0.5
shots 2
sleep 1.2
shots 5
step "Ctrl+1 keeps this view. Alt+1 flies back to it from anywhere."
c open >/dev/null
c "bookmark set 1" >/dev/null
c home >/dev/null
sleep 1
c "bookmark go 1" >/dev/null
sleep 1.2
shots 5
step "Hold the side button anywhere: the world becomes the map."
c cancel >/dev/null
sleep 0.6
{ printf 'move 1200 600\nsleep 100\ndown back\nsleep 700\nwheel -4\nsleep 1800\nup back\n'; } | input >/dev/null 2>&1 &
sleep 1.6
shots 5
sleep 1.2
step "Let go to land. Everything you moved is real window geometry."
shots 5
c cancel >/dev/null 2>&1

ffmpeg -y -loglevel error -framerate 3 -pattern_type glob -i "$OUT/frame-*.png" \
    -vf "fps=6,scale=960:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=160[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4" \
    "$OUT/tutorial.gif"
ffmpeg -y -loglevel error -framerate 3 -pattern_type glob -i "$OUT/frame-*.png" \
    -vf "fps=30,scale=1280:-1:flags=lanczos" -c:v libx264 -pix_fmt yuv420p "$OUT/tutorial.mp4"
rm -f "$OUT"/frame-*.png
down >/dev/null 2>&1 || true
echo "tutorial: $OUT/tutorial.gif ($(du -h "$OUT/tutorial.gif" | cut -f1)) and tutorial.mp4"
