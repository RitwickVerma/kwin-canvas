# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a corner push opens the zoom-to-fit view and a second push, with the camera untouched, goes back to where it began; after navigating it enters where you are looking"
settle() { local i; for i in $(seq 1 30); do c state; [ "$(sget cam)" = "-" ] && return; sleep 0.2; done; }
run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    setcfg SmoothZoom true
    setcfg BorderZoom fit
    set_borders 7
    local pan v0
    for pan in "0 0" "700 300" "-500 400"; do
        c cancel; sleep 0.6
        set -- $pan
        if [ "$1$2" != "00" ]; then cmd "slide $1 $2" >/dev/null 2>&1; sleep 1.6; fi
        c state; v0="$(sget viewx),$(sget viewy)"
        push_border 7; sleep 0.8; settle
        assert_eq "the push opened the canvas" "$(sget visible)" true
        assert_true "at the fit view, not 1:1" "$(sget zoom)" != 1.0000
        push_border 7; sleep 1.6; settle
        c state
        assert_eq "the second push closed it" "$(sget visible)" false
        assert_eq "and landed where it began ($pan)" "$(sget viewx),$(sget viewy)" "$v0"
    done
    # Navigated: the exit enters where the camera looks, as before.
    c cancel; sleep 0.6
    push_border 7; sleep 0.8; settle
    c "panpx 400 300"; c state
    push_border 7; sleep 1.6; settle
    c state
    assert_eq "navigated, the second push still closes it" "$(sget visible)" false
    assert_true "and enters where it was looking, not where it began" "$(sget viewx)" != "0.0"
    # SmoothZoom off: the open jumps to the fit view and leaves no camera
    # goal, and the second push must still go back where it began.
    setcfg SmoothZoom false
    c cancel; sleep 0.6
    cmd "slide 700 300" >/dev/null 2>&1; sleep 1.6
    c state; v0="$(sget viewx),$(sget viewy)"
    push_border 7; sleep 0.8
    c state
    assert_eq "without the smooth camera the push opens it too" "$(sget visible)" true
    push_border 7; sleep 1.2
    c state
    assert_eq "and the second push lands where it began" "$(sget viewx),$(sget viewy)" "$v0"
    set_borders 7
    setcfg BorderZoom 0.8
    arrange >/dev/null
}
