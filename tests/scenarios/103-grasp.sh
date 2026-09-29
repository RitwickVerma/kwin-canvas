# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the canvas modifier: holding MB4 on the normal desktop makes the location itself the canvas - pan and move windows as if the overworld were open, release applies the moves and closes - and held in the open overworld it is navigation only"
# Screen position of a canvas point at the current camera, from the last state.
screen_of() {
    awk -v cx="$1" -v cy="$2" -v vx="$(sget viewx)" -v vy="$(sget viewy)" -v z="$(sget zoom)" \
        'BEGIN{printf "%d %d", (cx-vx)*z, (cy-vy)*z}'
}
# A point on a window's title bar, in screen coordinates.
title_of() {
    echo "$(screen_of $(( $(eget "$1" x) + 240 )) $(( $(eget "$1" y) + 22 )))"
}
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "pass-through plugin not loaded (make plugin)"; return
    fi
    c state
    assert_eq "closed to start" "$(sget visible)" false
    # Holding MB4 anywhere on the desktop makes the location itself the
    # canvas: the overworld opens quietly at 1:1, pixel-identical, no chrome.
    # The hold is one injector stream - its exit is itself the release - with
    # the reads timed inside it, so the canvas never closes under the drags.
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 900\nmove 340 142\nsleep 60\ndown left\nsleep 60\nglide 190 82 20 10\nsleep 60\nup left\nsleep 500\nup back\n' | input &
    sleep 0.7; c state
    assert_eq "the hold opens the canvas quietly" "$(head -1 <<<"$LAST_STATE" | grep -c 'visible=true quiet grasp')" 1
    assert_eq "at the location, 1:1" "$(sget zoom)" 1.0000
    # The overworld's gestures work as if it were open: a left drag on a
    # window's title bar moves the window on the plane.
    sleep 0.8; c state
    assert_near "a drag moves the window on the plane, x" "$(eget KCalc x)" -50 2
    assert_near "and y" "$(eget KCalc y)" 60 2
    # Releasing applies the moves and closes: the window is written where the
    # hand put it, the camera returns to the location's viewport.
    sleep 0.9; c state
    assert_eq "the release closed the canvas" "$(sget visible)" false
    assert_near "the moved window was written, x" "$(eget KCalc fx)" -50 2
    assert_near "and y" "$(eget KCalc fy)" 60 2
    assert_near "and the camera is back on the viewport" "$(sget viewx)" "$(tget 0 x)" 1
    wait

    # A middle drag grabs and pans, from anywhere, in the same hold.
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 900\nmove 1700 900\nsleep 60\ndown middle\nsleep 60\nglide 1500 800 20 10\nsleep 60\nup middle\nsleep 900\nup back\n' | input &
    sleep 0.7; c state
    assert_eq "the second hold opens quietly too" "$(head -1 <<<"$LAST_STATE" | grep -c 'visible=true quiet grasp')" 1
    sleep 0.7; c state
    assert_near "a middle drag pans, x" "$(sget viewx)" 200 3
    assert_near "and y" "$(sget viewy)" 100 3
    sleep 0.9; c state
    assert_eq "and the release closes again" "$(sget visible)" false
    wait

    # Held in the open overworld it is navigation only: the hold counts, the
    # release commits nothing and leaves the canvas open.
    open_1to1
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 900\n' | input &
    sleep 0.6; c state
    assert_eq "held in the overworld it navigates" "$(sget nav)" hold
    sleep 0.9; c state
    assert_eq "and the release leaves the canvas open" "$(sget visible)" true
    wait
    c cancel
    arrange >/dev/null
}
