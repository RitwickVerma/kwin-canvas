# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="flies back to back: a slide asked for right as the last one lands opens fresh, so each lands exactly and no window is shifted twice"
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg PanDuration 200
    c state
    local x0 v0; x0=$(eget KCalc fx); v0=$(sget viewx)
    # Three slides, each asked for as the previous one lands (200 ms glide,
    # the debug channel takes ~0.3 s a command), then back.
    cmd "slide 300 0" >/dev/null 2>&1
    sleep 0.18
    cmd "slide 300 0" >/dev/null 2>&1
    sleep 0.18
    cmd "slide 300 0" >/dev/null 2>&1
    sleep 1
    c state
    assert_eq "the canvas closed" "$(sget visible)" false
    assert_near "the view moved by the three slides" "$(sget viewx)" "$(awk -v v="$v0" 'BEGIN{print v + 900}')" 1
    assert_near "and KCalc moved with them, once each" "$(eget KCalc fx)" "$((x0 - 900))" 1
    cmd "slide -900 0" >/dev/null 2>&1
    sleep 1
    c state
    assert_near "back again: the view" "$(sget viewx)" "$v0" 1
    assert_near "and KCalc where it began" "$(eget KCalc fx)" "$x0" 1
    arrange >/dev/null
}
