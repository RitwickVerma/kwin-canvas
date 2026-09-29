# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="stepping in and cancel fly: the camera springs to the location at 1:1 and the commit or the restore lands on arrival, and home and the swatches take the same spring"
# The nest runs with SmoothZoom off (dev/nest.sh), so a step in lands at once
# and the other scenarios measure the canvas. This one turns it on, measures
# the flight, and puts it back, as 94-physics does for its springs. A slow
# spring (CamSpring 8) keeps the camera mid-flight when a state read lands - a
# read being a config write, a reconfigure and a log read - and has settled
# within the sleeps.
chord() { printf 'key leftctrl down\nkey leftalt down\nkey space\nkey leftalt up\nkey leftctrl up\n' | input; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    setcfg SmoothZoom true
    setcfg CamSpring 8

    # Stepping in from a zoomed-out view flies: the camera springs to the
    # location's viewport at 1:1 and the commit happens on arrival, where the
    # thumbnails and the real windows agree, so nothing on screen jumps.
    open_1to1
    c "zoom 0.4 960 540"
    chord
    sleep 0.25; c state
    assert_eq "the step in keeps the canvas open while it flies" "$(sget visible)" true
    assert_eq "the camera is springing, not jumping" "$(sget cam)" goal
    sleep 2.0; c state
    assert_eq "and it lands in the location" "$(sget visible)" false
    assert_near "at 1:1" "$(sget zoom)" 1 0.001
    assert_near "on the current activity's target, x" "$(sget viewx)" "$(tget 0 x)" 1
    assert_near "on the current activity's target, y" "$(sget viewy)" "$(tget 0 y)" 1
    assert_eq "and the windows were written where they were" "$(eget KCalc fx)" 100

    # Cancel flies back the same way: the camera returns to the entry view at
    # 1:1 and only then does the restore run, so Esc from far away is a
    # flight, not a teleport.
    open_1to1
    c "zoom 0.4 960 540"
    printf 'key esc\n' | input
    sleep 0.25; c state
    assert_eq "the cancel keeps the canvas open while it flies" "$(sget visible)" true
    assert_eq "on the spring" "$(sget cam)" goal
    sleep 2.0; c state
    assert_eq "and it lands closed" "$(sget visible)" false
    assert_near "back at the entry view, x" "$(sget viewx)" "$(tget 0 x)" 1
    assert_near "back at the entry view, y" "$(sget viewy)" "$(tget 0 y)" 1
    assert_eq "nothing moved" "$(eget KCalc fx)" 100

    # Home and the activity swatches take the spring too: a camera move is a
    # camera move, whatever asks for it.
    open_1to1
    c "zoom 0.5 960 540"
    printf 'key home\n' | input
    sleep 0.25; c state
    assert_eq "home flies" "$(sget cam)" goal
    sleep 2.0; c state
    assert_eq "and lands at 1:1" "$(sget zoom)" 1.0000
    assert_near "on the target" "$(sget viewx)" "$(tget 0 x)" 1
    c "zoom 0.5 960 540"
    c "zoomto 1"
    c state
    assert_eq "the swatch's zoom flies" "$(sget cam)" goal
    sleep 2.0; c state
    assert_near "and fits that activity's frames" "$(sget zoom)" 0.8889 0.01
    c cancel

    # Back to the nest's own knobs.
    setcfg SmoothZoom false
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key CamSpring --delete
    c state
    assert_eq "the nest's knobs are back and nothing is left moving" "$(sget cam)" -
    arrange >/dev/null
}
