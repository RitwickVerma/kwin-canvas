#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# The cinematic demo: one nested session driven by real input, captured to
# build/demo/demo.gif and demo.mp4. The sequence is the tour: the desktop,
# the step out into the haze, the hover's glow, the double-click's flight,
# the clusters' web, the map's morph, the hold's sheets, and the step back
# in. For the README's hero and the release notes.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$HERE/dev/nest.sh"
source "$HERE/tests/lib.sh"
OUT=$HERE/build/demo
mkdir -p "$OUT"
rm -f "$OUT"/frame-*.png "$OUT"/demo.gif "$OUT"/demo.mp4
have_input || { echo "fakeinput not built: make tools"; exit 1; }

# The show's wallpaper: a deep gradient, darker than the test fixtures'.
WALL="$FIXTURES/wallpaper.png"
cp "$WALL" "$WALL.demo.bak" 2>/dev/null || true
magick -size 1920x1080 gradient:'#151528'-'#0f2038' \
    -fill '#101830' -draw 'circle 1450,240 1450,60' \
    -fill '#141a30' -draw 'circle 350,820 350,680' "$WALL" 2>/dev/null || true

down >/dev/null 2>&1 || true
up || true
fixtures >/dev/null 2>&1 || true
setcfg Passthrough false
arrange >/dev/null
# A wider desk so the map and the clusters have somewhere to be.
c open >/dev/null; c home >/dev/null
c "placeby KCalc 300 300 480 420" >/dev/null
c "placeby Konsole 900 350 620 420" >/dev/null
c "placeby Gwenview 3000 300 460 420" >/dev/null
c "placeby Dolphin 3600 350 700 360" >/dev/null
c commit >/dev/null

# The frame camera: a backgrounded loop that captures while the input runs.
FRAMES=$OUT
shot_frames() {
    for i in $(seq -w 1 90); do
        shot "$FRAMES/frame-$i.png" >/dev/null 2>&1
        sleep 0.11
    done
}

# The sequence, as one continuous scripted session.
run_sequence() {
    # 1. the desktop, then the step out into the haze
    sleep 1.2
    c open >/dev/null
    c "zoom 0.5 960 540" >/dev/null
    sleep 1.4
    # 2. the hover's glow settles on KCalc
    input move 480 510
    sleep 1.2
    # 3. the double-click flies into the location, snappy
    input click
    sleep 0.09
    input click
    sleep 1.0
    # 4. back out; the clusters' web and the floating windows
    c open >/dev/null
    c "zoom 0.35 960 540" >/dev/null
    sleep 1.6
    # 5. the cluster tour
    input key bracketright
    sleep 1.1
    input key bracketright
    sleep 1.1
    input key bracketleft
    sleep 0.8
    # 6. the hold: the map's sheets sharpen in
    input move 1700 900
    sleep 0.3
    input down back
    sleep 1.6
    # 7. the release and the step back in
    input up back
    sleep 0.9
    c enter >/dev/null
    sleep 1.0
}

shot_frames &
SHOT_PID=$!
run_sequence
wait $SHOT_PID

# The GIF and the mp4 from the frames.
ffmpeg -y -loglevel error -framerate 12 -pattern_type glob -i "$OUT/frame-*.png" \
    -vf "fps=12,scale=960:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$OUT/demo.gif"
ffmpeg -y -loglevel error -framerate 30 -pattern_type glob -i "$OUT/frame-*.png" \
    -vf "fps=30,scale=1280:-1:flags=lanczos" -c:v libx264 -pix_fmt yuv420p "$OUT/demo.mp4"

# The wallpaper back for the tests.
[ -f "$WALL.demo.bak" ] && mv "$WALL.demo.bak" "$WALL" 2>/dev/null || true
python3 "$FIXTURES/gen.py" >/dev/null 2>&1 || true
down >/dev/null 2>&1 || true
echo "demo: $OUT/demo.gif and demo.mp4"
