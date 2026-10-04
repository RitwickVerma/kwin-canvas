# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="an island catches drops: dragging a window onto another desktop's island moves it to that desktop for real, the seam keeps its place, and the commit writes the matching frame"

run_scenario() {
    arrange >/dev/null
    open_1to1
    c "newdesktop Two"
    sleep 0.3
    c state
    assert_eq "the plane has two desktops" "$(sget desktops)" 2
    c "zoom 0.5 960 540"
    sleep 0.4
    # KWrite's centre: canvas (990,380) -> screen ((990+960)*0.5, (380+540)*0.5) = (975,460).
    # Dragging it +570 screen pixels down = +1140 canvas -> centre (990,1520),
    # inside desktop 2's island (0..1920, 1320..2400).
    printf 'move 975 460\nsleep 300\ndown left\nsleep 300\nmove 975 461\nsleep 100\nglide 975 1030 30 400\nsleep 300\nup left\n' | input
    sleep 0.5
    c state
    assert_eq "the drop moved it to desktop 2" "$(eget "sample.txt" desktop)" 2
    # The glide's first 14 px are the grip's dead zone, so the drop lands
    # near, not exactly at, the pointer: the window's top edge ends up
    # around canvas y 1230-1260, its centre inside desktop 2's island.
    assert_near "and it kept the drop point on the plane" "$(eget "sample.txt" y)" 1260 40
    c commit
    open_1to1
    sleep 0.4
    c state
    assert_eq "the commit wrote the frame's x" "$(eget "sample.txt" fx)" 640
    # The frame is exact: canvas minus the activity target minus desktop 2's
    # island offset (1320), whatever the drop's final canvas position was.
    assert_near "the commit wrote the frame to match the canvas" "$(awk -v y="$(eget "sample.txt" y)" -v fy="$(eget "sample.txt" fy)" 'BEGIN { d = y - 1320 - fy; if (d < 0) d = -d; print d }')" 0 2
    c "desktop 1"
    sleep 0.4
    open_1to1
    sleep 0.4
    c state
    assert_eq "the other desktop's seam holds just the dropped window" "$(grep -c '^  \[[0-9][0-9]*\] .* desktop=2' <<<"$LAST_STATE")" 1
    assert_eq "and the first desktop keeps the rest" "$(grep -c '^  \[[0-9][0-9]*\] .* desktop=1' <<<"$LAST_STATE")" 4
    c "desktop 0"
    sleep 0.4
    c "movetodesktop 1 0"
    sleep 0.4
    c "rmdesktop 1"
    sleep 0.4
    c state
    assert_eq "the cleanup leaves one desktop" "$(sget desktops)" 1
    arrange >/dev/null
}
