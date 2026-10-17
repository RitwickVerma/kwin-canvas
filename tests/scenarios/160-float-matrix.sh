# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the float across interactions: unpinning while the picture rides the edge leaves the window where the eye saw it, a screen-sized floated window leaves the canvas flush, and the picture stays inside the screen through zoom, pan and a drag"
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    open_1to1
    c state >/dev/null
    local k; k=$(eget KCalc index)
    c "pin $k"
    sleep 0.3
    # Unpin while the picture rides the edge: the window stays where it was seen.
    c "panpx -900 0" >/dev/null
    sleep 1
    assert_eq "pinned and pushed out, the picture rides inside the screen" "$(float_inside)" yes
    c "unpin $k"
    sleep 0.8
    assert_eq "unpinned there, the window is still wholly on screen" "$(float_inside)" yes
    c cancel >/dev/null 2>&1
    arrange >/dev/null
    # The picture stays inside through zoom and pan.
    open_1to1
    c state >/dev/null; k=$(eget KCalc index)
    c "pin $k"
    local z
    for z in 0.8 0.5 0.3; do
        c "zoom $z 960 540" >/dev/null
        c "panpx 700 -400" >/dev/null
        sleep 0.7
        assert_eq "inside at zoom $z after a pan" "$(float_inside)" yes
    done
    c "panpx -5000 3000" >/dev/null
    sleep 0.7
    assert_eq "inside after a far jump" "$(float_inside)" yes
    c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
    # A screen-sized floated window leaves the canvas flush, not 8 px off.
    c "placeby KCalc 0 0 1920 1080" >/dev/null
    sleep 0.6
    open_1to1
    c state >/dev/null; k=$(eget KCalc index)
    c "pin $k"
    c "panpx -400 -300" >/dev/null
    sleep 0.8
    c enter >/dev/null
    sleep 1.5
    assert_eq "a screen-sized floated window lands flush at the origin" "$(float_frame)" "0 0 1920 1080"
    c state >/dev/null; k=$(eget KCalc index); c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
