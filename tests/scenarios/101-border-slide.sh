# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="BorderSlide: an edge push at 1:1 slides the desktop one step toward the push instead of opening the canvas, and in the open canvas it moves the camera one step"
chord() { printf 'key leftctrl down\nkey leftalt down\nkey space\nkey leftalt up\nkey leftctrl up\n' | input; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    setcfg BorderSlide true
    c state
    local vx0 vy0 kx0 ky0
    vx0=$(sget viewx); vy0=$(sget viewy); kx0=$(eget KCalc fx); ky0=$(eget KCalc fy)
    # The top-left corner, without the button held, is a push: one slide step
    # up and left. The windows ride the slide, so the desktop moves as one.
    push_border 7
    sleep 0.5; c state
    assert_eq "a push slid instead of opening the canvas" "$(sget visible)" false
    assert_near "one step left" "$(sget viewx)" "$(awk -v x="$vx0" 'BEGIN{print x-960}')" 1
    assert_near "one step up" "$(sget viewy)" "$(awk -v y="$vy0" 'BEGIN{print y-540}')" 1
    assert_near "the windows rode with it, x" "$(eget KCalc fx)" $((kx0 + 960)) 1
    assert_near "the windows rode with it, y" "$(eget KCalc fy)" $((ky0 + 540)) 1

    # The borders are a route, not a door: the chord still opens the canvas.
    chord
    sleep 0.6; c state
    assert_eq "the chord still opens it" "$(sget visible)" true
    # In the open canvas the same push moves the camera one step instead of
    # entering the location. The left edge has to be reserved for its handler
    # to exist; the nest starts with the top-left corner (7).
    set_borders 6
    local vx; vx=$(sget viewx)
    push_border 6
    sleep 0.5; c state
    assert_eq "still open" "$(sget visible)" true
    assert_near "the camera stepped left" "$(sget viewx)" "$(awk -v x="$vx" 'BEGIN{print x-960}')" 1
    c cancel
    set_borders 7
    setcfg BorderSlide false
    c state
    assert_eq "closed again" "$(sget visible)" false
    arrange >/dev/null
}
