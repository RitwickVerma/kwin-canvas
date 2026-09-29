#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the motion physics: a wheel zoom springs to its step with the point under the cursor pinned, a flicked pan glides under friction, a paused one does not, and a dragged window trails, leans and settles without moving the entry"
# The nest runs with the motion knobs off (dev/nest.sh), so the other scenarios
# measure the canvas and not the spring. This one turns them on, measures them,
# and puts them back.
#
# The canvas point under a screen point, from the last state. The state prints
# the camera to a tenth of a pixel and the zoom to four decimals, so a pinned
# point reads back within a few tenths.
canvas_x() { awk -v s="$1" -v vx="$(sget viewx)" -v z="$(sget zoom)" 'BEGIN{printf "%.3f", vx + s / z}'; }
canvas_y() { awk -v s="$1" -v vy="$(sget viewy)" -v z="$(sget zoom)" 'BEGIN{printf "%.3f", vy + s / z}'; }
abs() { awk -v v="$1" 'BEGIN{print (v < 0 ? -v : v)}'; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    setcfg SmoothZoom true
    setcfg PanInertia true
    setcfg WindowPhysics true
    # Slow enough that a state read lands mid-flight: a state read is a config
    # write, a reconfigure and a log read, about a third of a second.
    setcfg CamSpring 4

    # A wheel notch springs to its step instead of jumping: mid-flight the
    # camera is between 1 and 1/ZoomStep, the point under the cursor is still
    # under it at every sample - the anchor owns the position and only the
    # scale springs - and it arrives exactly on the step without overshooting,
    # because the spring is critically damped. The pointer is on the ground,
    # where the wheel belongs to the canvas: over a client area it belongs to
    # the window while pass-through is live.
    open_1to1
    input move 1700 900
    sleep 0.3
    printf 'wheel -1\n' | input
    c state
    assert_eq "the camera is springing, not jumping" "$(sget cam)" goal
    assert_true "and is between the two zooms" \
        "$(awk -v z="$(sget zoom)" 'BEGIN{print (z > 0.8696 + 0.001 && z < 0.9999)}')" = 1
    assert_near "the point under the cursor is pinned, x" "$(canvas_x 1700)" 1700 0.3
    assert_near "the point under the cursor is pinned, y" "$(canvas_y 900)" 900 0.3
    local n=0 under=0
    while [ "$n" -lt 5 ]; do
        c state
        assert_near "still pinned while it springs" "$(canvas_x 1700)" 1700 0.3
        # Never past the step: a critically damped spring does not overshoot.
        awk -v z="$(sget zoom)" 'BEGIN{exit !(z >= 0.8696)}' || under=1
        n=$((n + 1))
    done
    assert_eq "no overshoot on the way" "$under" 0
    sleep 2.5; c state
    assert_near "and it arrives on the step" "$(sget zoom)" 0.8696 0.001
    assert_eq "at rest" "$(sget cam)" -

    # A flick: the plane keeps moving the way the hand was moving after it lets
    # go, slowing under PanFriction, and comes to a stop rather than drifting on.
    c cancel; open_1to1
    printf 'move 1700 900\nsleep 60\ndown left\nsleep 60\nglide 1300 740 8 4\nup left\n' | input
    sleep 0.2; c state
    assert_eq "the flick keeps the plane moving" "$(sget cam)" glide
    sleep 2.5; c state
    assert_eq "and it stops" "$(sget cam)" -
    local vx1; vx1=$(sget viewx)
    assert_true "having carried well past the drag's own 400 px" \
        "$(awk -v v="$vx1" 'BEGIN{print (v > 700)}')" = 1
    sleep 0.6; c state
    assert_near "and stays put" "$(sget viewx)" "$vx1" 2

    # A drag the hand pauses before letting go is a placement, not a throw: the
    # pan handler only carries a fling whose last motion is within 120 ms of the
    # release, which is what lets a careful drag land exactly where it was put.
    c cancel; open_1to1
    printf 'move 1700 900\nsleep 60\ndown left\nsleep 60\nglide 1600 900 8 4\nsleep 400\nup left\n' | input
    sleep 0.2; c state
    assert_eq "a paused drag does not glide" "$(sget cam)" -
    assert_near "and the view is where the drag left it" "$(sget viewx)" 100 3

    # A dragged window carries weight. The weight is drawn, not measured: the
    # same drag with the physics off and on leaves the entry - and so the
    # committed geometry - at exactly the same place, so all the physics adds
    # is the picture. KCalc's title bar is the drag target; its client area
    # belongs to the app while pass-through is live.
    setcfg WindowPhysics false
    c cancel; open_1to1
    c "snap edges off"; c "snap corners off"; c "snap grid off"
    # The injector runs in the background - a foreground one holds the shell
    # until its stream ends, so a read after it is a read after the release -
    # and the stream releases the button itself, so the read that follows lands
    # on a canvas with the hand off it.
    local kx=340 ky=142
    local drag="move $kx $ky\nsleep 60\ndown left\nsleep 60\nglide $((kx - 200)) $((ky - 100)) 60 25\nsleep 900\nup left\nsleep 500\n"
    printf "$drag" | input &
    sleep 0.5; c state
    assert_eq "no trail with the physics off" "$(sget draglag)" 0
    assert_eq "and no lean" "$(sget lean)" 0.00
    sleep 2.5; c state
    local ox oy; ox=$(eget KCalc x); oy=$(eget KCalc y)
    assert_eq "the physics-off drag lands where it was put" "$ox,$oy" "-100,20"

    setcfg WindowPhysics true
    c cancel; open_1to1
    printf "$drag" | input &
    sleep 0.5; c state
    assert_true "the window trails the hand" \
        "$(awk -v l="$(sget draglag)" 'BEGIN{print (l > 0)}')" = 1
    assert_true "and leans after it" \
        "$(awk -v l="$(abs "$(sget lean)")" 'BEGIN{print (l > 0.05)}')" = 1
    sleep 2.5; c state
    assert_eq "and settles when the hand lets go" "$(sget draglag)" 0
    assert_eq "and stops leaning" "$(sget lean)" 0.00
    assert_eq "with the entry exactly where the same drag put it" \
        "$(eget KCalc x),$(eget KCalc y)" "$ox,$oy"

    # Back to the nest's own knobs: the motion is off everywhere else.
    c cancel
    setcfg SmoothZoom false
    setcfg PanInertia false
    setcfg WindowPhysics false
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key CamSpring --delete
    c state
    assert_eq "the nest's knobs are back and nothing is left moving" "$(sget cam)" -
    arrange >/dev/null
}
