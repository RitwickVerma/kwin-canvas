# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="every commit is a checkpoint: the debug channel's undo glides the layout home, windows and real frames alike"

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    # The arrange's own commit seeds the stack with the fixtures' layout.
    open_1to1
    c "placeby KCalc 600 600 480 420"
    c commit
    sleep 0.3
    open_1to1
    sleep 0.5
    c state
    assert_eq "the move took" "$(eget KCalc x)" 600
    c undo
    c state
    assert_eq "the state carries the glide count" "$(head -1 <<<"$LAST_STATE" | grep -c ' moves=')" 1
    # The undo glides the window home (220ms); the reads land after it.
    for _ in $(seq 1 20); do c state; [ "$(eget KCalc x)" = "100" ] && break; sleep 0.2; done
    sleep 0.3
    c state
    assert_eq "the undo glides the window home" "$(eget KCalc x)" 100
    assert_eq "and its y" "$(eget KCalc y)" 120
    assert_eq "and the real frame followed" "$(eget KCalc fx)" 100
    assert_eq "and its y too" "$(eget KCalc fy)" 120
    c undo
    sleep 0.5
    c state
    assert_eq "the first commit has nothing to step back to" "$(eget KCalc x)" 100
    c cancel
    arrange
}
