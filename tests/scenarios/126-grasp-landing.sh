# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the grasp shows its destination: the window under the pointer wears the landing ring, and the release commits the location"

region_rmse() {
    magick "$1" -crop "$3" +repage "$OUT/ga.png"
    magick "$2" -crop "$3" +repage "$OUT/gb.png"
    { magick compare -metric RMSE "$OUT/ga.png" "$OUT/gb.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}
changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }

run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    # The windows park in one corner cluster, high enough that every
    # window and the pointer's spots stay on screen at the eighth.
    open_1to1
    c "placeby KCalc 200 600 480 420"
    c "placeby sample.txt 700 600 700 520"
    c "placeby Konsole 200 1050 620 420"
    c "placeby Dolphin 850 1100 700 360"
    c "placeby wallpaper.png 1400 600 460 420"
    c commit
    sleep 0.3

    # One device holds for the whole part: the press on open ground, the
    # zoom through the debug channel, and the pointer walked onto KCalc
    # mid-hold. A separate device's fresh first event lands at its default
    # (0,0) - the corner - and the hold's edge pan would ride it away.
    { printf 'move 1700 900\nsleep 60\ndown back\nsleep 4000\nmove 544 756\nsleep 4000\nup back\n'; } | input >/dev/null 2>&1 &
    holdpid=$!
    sleep 1.2
    c "zoom 0.8 960 540"
    sleep 0.8
    c state
    assert_eq "the hold is quiet at the eighth" "$(sget zoom)" "0.8000"
    assert_eq "and the camera is pinned" "$(sget viewx),$(sget viewy)" "-240.0,-135.0"
    assert_eq "the release would land" "$(grep -o 'outcome=[a-z-]*' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2)" "land"
    shot "$OUT/ring-off.png" >/dev/null 2>&1

    # The pointer has walked onto KCalc: the grasp's pick names it, and
    # its bottom edge wears the landing ring.
    sleep 1.6
    c state
    ki=$(eget KCalc index)
    assert_eq "the pointer's window is named as the fly target" "$(grep -o 'graspTarget=[0-9-]*' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2)" "$ki"
    shot "$OUT/ring-on.png" >/dev/null 2>&1
    assert_eq "the window's edge wears the ring" "$(changed "$(region_rmse "$OUT/ring-off.png" "$OUT/ring-on.png" "20x2+500+922")")" 1
    # Past the 0.72 boundary the release widens instead of landing: the
    # strip's last word says so, on the wheel's own motion.
    c "zoom 0.6 960 540"
    sleep 0.8
    c state
    assert_eq "the release would widen" "$(grep -o 'outcome=[a-z-]*' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2)" "world"

    # Back above the boundary, so the release that follows lands.
    c "zoom 0.8 960 540"
    sleep 0.5
    c state
    assert_eq "and back above it, the release would land" "$(grep -o 'outcome=[a-z-]*' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2)" "land"

    # The release at 0.8 commits the location.
    wait "$holdpid" 2>/dev/null || true
    sleep 1.2
    c state
    assert_eq "the release lands the location" "$(sget visible)" false

    c cancel
    arrange
}
