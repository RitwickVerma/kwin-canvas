# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="every commit is a checkpoint: the debug channel's undo steps the layout back to the one before the last commit, windows and real frames alike"

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
    sleep 0.5
    c state
    assert_eq "the undo steps the window back" "$(eget KCalc x)" 100
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
