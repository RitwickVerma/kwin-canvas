# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="with Perf on, a floated window taking its picture's spot is logged as a landed line, and the canvas's own drag is not logged as a moved line (the moved line itself, for a window moved by something else, could not be triggered in the nest)"
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    setcfg Perf true
    open_1to1; c state >/dev/null
    local mark lines k
    mark=$(wc -l <"$LOG")
    c "drag $(eget Gwenview index) 40 30" >/dev/null; sleep 0.5
    lines=$(tail -n +"$((mark + 1))" "$LOG" | grep -a "perf: moved" || true)
    assert_eq "the canvas's own drag is not a moved line" "$(grep -c . <<<"$lines")" 0
    k=$(eget KCalc index); c "pin $k"; c "panpx -900 -300" >/dev/null; sleep 0.6
    mark=$(wc -l <"$LOG")
    c enter >/dev/null; sleep 1.2
    lines=$(tail -n +"$((mark + 1))" "$LOG" | grep -a "perf: landed" | sed 's/.*perf: //' || true)
    assert_true "a floated window taking its picture's spot is a landed line" "$(grep -c '^landed win=KCalc' <<<"$lines")" -ge 1
    c open >/dev/null; c state >/dev/null; c "unpin $(eget KCalc index)" >/dev/null
    setcfg Perf false
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
