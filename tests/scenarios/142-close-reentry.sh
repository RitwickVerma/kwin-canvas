# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a second commit after the canvas has closed does nothing: no second undo entry for one close"
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    open_1to1
    c "place 2 700 500"
    cmd commit >/dev/null 2>&1
    sleep 0.4
    c state
    local once; once=$(sget undo)
    # The canvas is closed: a second commit is a second ask for a close that
    # has landed. (The stack is capped at 20, so compare with one commit, not
    # with a count from before.)
    cmd commit >/dev/null 2>&1
    sleep 0.4
    c state
    assert_eq "the canvas is closed" "$(sget visible)" false
    assert_eq "a second commit adds no undo entry" "$(sget undo)" "$once"
    arrange >/dev/null
}
