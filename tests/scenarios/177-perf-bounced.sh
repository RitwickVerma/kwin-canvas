# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="with Perf on, a window found away from where a landing wrote it (something pushed it back) is logged as a bounced line with how far it went; a landing nothing disturbs logs none"
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    setcfg Perf true
    c state >/dev/null
    local mark lines
    mark=$(wc -l <"$LOG")
    c "slide 400 0" >/dev/null; sleep 2
    lines=$(tail -n +"$((mark + 1))" "$LOG" | grep -a "perf: bounced" || true)
    assert_eq "an undisturbed landing logs no bounced line" "$(grep -c . <<<"$lines")" 0
    # A script that pushes KCalc back to x=100 whenever its frame changes: what a panel's strip
    # or a tiler does to a window it does not want where the canvas put it.
    # (kwinjs unloads its script when it returns, so it runs in the background for the slide.)
    mark=$(wc -l <"$LOG")
    kwinjs 'var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) w = x; }); w.frameGeometryChanged.connect(function () { var g = w.frameGeometry; if (g.x !== 100) w.frameGeometry = {x: 100, y: g.y, width: g.width, height: g.height}; });' 4 &
    sleep 1.2
    c "slide -300 0" >/dev/null
    sleep 2.5
    wait
    lines=$(tail -n +"$((mark + 1))" "$LOG" | grep -a "perf: bounced" | sed 's/.*perf: //' || true)
    assert_true "a window pushed back is a bounced line naming it" "$(grep -c '^bounced win=KCalc' <<<"$lines")" -ge 1
    assert_true "with how far it went" "$(grep -c ' dx=-\?[1-9][0-9]* ' <<<"$lines")" -ge 1
    assert_true "and whether it overlapped a dock" "$(grep -c ' overlapsDock=[01] ' <<<"$lines")" -ge 1
    setcfg Perf false
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
