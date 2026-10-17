# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a marquee takes a floated window by its picture, where the eye sees it, not by the coordinates it is parked at"
selected() { # CAPTION -> "yes" when the state marks the window selected
    c state >/dev/null
    grep -aq "^  \[[0-9]*\] \*.*$1" <<<"$LAST_STATE" && echo yes || echo no
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    open_1to1
    c state >/dev/null
    local k; k=$(eget KCalc index)
    c "pin $k"
    # The camera is 1500 px to the left of the window: its coordinates are
    # plane x 100..580, which is screen x 1600 and beyond, off the right edge,
    # and its picture rides the edge at screen x 1432, which is plane x -68..412.
    c "panpx 1500 0" >/dev/null
    sleep 1.2
    c "clearsel" >/dev/null
    c "marquee 450 120 110 100" >/dev/null
    assert_eq "a marquee over the coordinates, where nothing is drawn, takes nothing" "$(selected KCalc)" no
    c "clearsel" >/dev/null
    c "marquee -60 120 40 100" >/dev/null
    assert_eq "a marquee over the picture takes the window" "$(selected KCalc)" yes
    c "clearsel" >/dev/null
    c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
