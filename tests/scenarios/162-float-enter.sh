# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="stepping into a floated window (Enter on it, a double-click) enters where the eye is: the camera is not flown to the window's coordinates and the window lands on screen where its picture was, focused"
run_scenario() {
    arrange >/dev/null
    open_1to1
    c state >/dev/null
    local k; k=$(eget KCalc index)
    c "pin $k"
    # Camera pushed 3000 px: the window's coordinates are far off the screen
    # to the right and its picture rides the right edge.
    c "panpx 3000 0" >/dev/null
    sleep 1.2
    assert_eq "the picture rides the right edge" "$(float_picture)" "1432.0 120.0 480.0 420.0"
    # The step into the window itself, as a double-click on its picture or
    # Enter with it selected does.
    c "focus $k" >/dev/null
    sleep 2
    c state >/dev/null
    assert_eq "the canvas is closed" "$(sget visible)" false
    assert_eq "the window landed where its picture was" "$(float_frame)" "1432 120 480 420"
    kwinjs 'var a = workspace.activeWindow; print("FLOATACTIVE " + (a ? a.caption : "none"));' 0.6
    assert_true "and it is the focused window" "$(grep -a FLOATACTIVE "$STATE/kwin.log" | tail -1 | sed 's/.*FLOATACTIVE/FLOATACTIVE/')" = "FLOATACTIVE KCalc"
    c "open" >/dev/null; c state >/dev/null; k=$(eget KCalc index); c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
    # The same step in from the whole-plane view (the switcher's, a zoom-out):
    # the window's picture is at its coordinates there, so it is placed like
    # any window, and it must still land on screen. The step is taken at once
    # with SmoothZoom off, from the zoomed-out camera.
    setcfg SmoothZoom false
    open_1to1
    c state >/dev/null; k=$(eget KCalc index)
    c "pin $k"
    sleep 0.3
    c extents >/dev/null
    sleep 1
    c "pick $k" >/dev/null
    sleep 2
    assert_eq "stepping in from the zoomed-out plane lands the window on screen" "$(float_frame | awk '{print ($1 >= 0 && $2 >= 0 && $1 + $3 <= 1920 && $2 + $4 <= 1080) ? "yes" : "no " $0}')" yes
    c "open" >/dev/null; c state >/dev/null; k=$(eget KCalc index); c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
    # And from a zoomed-out camera that has left the window behind: the
    # picture is displaced, the step is taken at once at zoom 0.5, and the
    # window is landed for the 1:1 view it will be written for, not the
    # zoomed-out one (where its coordinates are still inside the screen).
    open_1to1
    c state >/dev/null; k=$(eget KCalc index)
    c "pin $k"
    c "panpx 3000 0" >/dev/null
    c "zoom 0.5 960 540" >/dev/null
    sleep 1
    c "pick $k" >/dev/null
    sleep 2
    assert_eq "stepping in with the picture displaced at zoom 0.5 lands the window on screen" "$(float_frame | awk '{print ($1 >= 0 && $2 >= 0 && $1 + $3 <= 1920 && $2 + $4 <= 1080) ? "yes" : "no " $0}')" yes
    c "open" >/dev/null; c state >/dev/null; k=$(eget KCalc index); c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
