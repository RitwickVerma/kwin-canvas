# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the camera's rectangle never leaves the minimap: panned past the world's edge, it hugs the chip's border instead of sliding off it"

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    open_1to1
    c "zoom 0.7 960 540"
    sleep 0.5
    c state
    assert_eq "the overworld is up" "$(sget visible)" true
    assert_eq "at seven tenths" "$(sget zoom)" "0.7000"
    # A pan that walks the camera a little past the world's left edge;
    # the minimap's rectangle must clamp to the chip's border there
    # instead of poking out. The exact pan: the same 400 screen pixels the
    # line always meant, taken with no torch (at 0.7 zoom the plain drag
    # rides the arc and overshoots to the 85-degree pole, which is not the
    # step this check is about).
    c "panpx 400 0"
    sleep 0.5
    c state
    assert_near "the camera left the world" "$(sget viewx)" -982.9 60
    snap minimap-rect
    c cancel
    arrange >/dev/null
}
