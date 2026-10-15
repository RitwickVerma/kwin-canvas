# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the snap is a magnet: the drag that catches an edge counts one catch and the geometry lands flush, exactly as before; staying on the edge counts no more"
run_scenario() {
    source tests/lib.sh
    setcfg WindowPhysics true
    arrange >/dev/null
    open_1to1
    c "snap grid off"; c "snap edges on"
    c state
    local w s0; w=$(eget sample.txt index); s0=$(sget snaps)
    # KCalc's right edge is at 580: KWrite's left edge 8 px off it, then a
    # nudge that brings it into snap range.
    c "placeby sample.txt 588 130"
    c "drag $w 3 0"
    c state
    assert_eq "the edge snapped flush" "$(eget sample.txt x)" 580
    assert_eq "one catch" "$(sget snaps)" "$((s0 + 1))"
    c "drag $w 1 0"
    c state
    assert_eq "a drag that stays on the edge is no new catch" "$(sget snaps)" "$((s0 + 1))"
    assert_eq "and stays flush" "$(eget sample.txt x)" 580
    c cancel
    arrange >/dev/null
}
