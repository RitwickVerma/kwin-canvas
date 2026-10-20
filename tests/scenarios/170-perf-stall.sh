# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="with Perf on, a physics tick that arrives 60 ms or more late is written as a stall line naming what the canvas was doing and the load readings; steady ticks write none"
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom true
    setcfg Perf true
    c cancel; sleep 0.6
    local mark kpid lines
    c open; sleep 1.2
    c state >/dev/null
    mark=$(wc -l <"$LOG")
    sleep 1.2
    lines=$(tail -n +"$((mark + 1))" "$LOG" | grep -a "kwin-canvas perf: stall" || true)
    assert_eq "a steady open writes no stall line" "$(grep -c . <<<"$lines")" 0
    # Freeze the nest's own compositor for 300 ms: every timer in it is late.
    kpid=$(pgrep -f "kwin_wayland.*--socket $SOCKET" | head -1)
    kill -STOP "$kpid"; sleep 0.3; kill -CONT "$kpid"
    sleep 1
    lines=$(tail -n +"$((mark + 1))" "$LOG" | grep -a "kwin-canvas perf: stall" | sed 's/.*kwin-canvas perf: //' || true)
    assert_true "a 300 ms freeze writes a stall line" "$(grep -c '^stall ms=' <<<"$lines")" -ge 1
    assert_true "its ms is at least 60" "$(sed -n '1s/^stall ms=\([0-9]*\).*/\1/p' <<<"$lines")" -ge 60
    assert_true "it names the camera, the canvas state and the load" "$(grep -c 'cam=.* quiet=[01] entries=[0-9]* ql=[0-9] cpu=[0-9]* gpu=[0-9-]* mem=[0-9]*' <<<"$lines")" -ge 1
    setcfg Perf false
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
