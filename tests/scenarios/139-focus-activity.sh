# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="focusing a window in another activity's frame commits at that activity's viewport, not the one it left"
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    open_1to1
    c addactivity
    sleep 1.2
    c state
    local tx ty k; tx=$(tget 2 x); ty=$(tget 2 y); k=$(eget KCalc index)
    c "placeby KCalc $((tx + 200)) $((ty + 200))"
    c "focus $k"
    local i
    for i in $(seq 1 10); do c state; [ "$(sget visible)" = false ] && break; sleep 0.3; done
    assert_eq "the canvas closed on Activity 3" "$(sget activity)" "Activity 3"
    sleep 0.8
    c state
    # The smart mode shifts the viewport to keep the neighbours in sight, so
    # the view is near the activity's frame (tx), never at the old one (0).
    assert_true "the view is at the new activity's viewport, not the old one" "$(sget viewx | cut -d. -f1)" -gt $((tx - 1000))
    # Leave the nest as it was.
    c "activity 0"
    sleep 0.8
    open_1to1
    c "placeby KCalc 100 120"
    c commit
    c "rmactivity 2"
    sleep 1.2
    arrange >/dev/null
}
