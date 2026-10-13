# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a click's pending pan dies with the canvas: a commit inside the double-click wait leaves the camera where the commit put it"
run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    setcfg Passthrough false
    open_1to1
    # KCalc hangs over the right edge, so a click owes it a pan into view.
    c "place 2 1700 300"
    c state
    input move 1800 400
    sleep 0.3
    { printf 'click\nsleep 20\n'; } | input
    cmd commit >/dev/null 2>&1
    sleep 0.8
    c state
    assert_eq "the canvas closed" "$(sget visible)" false
    assert_near "the commit's camera stands, x (a stale pan would move it)" "$(sget viewx)" 0 0.5
    assert_near "and y" "$(sget viewy)" 0 0.5
    setcfg Passthrough true
    arrange >/dev/null
}
