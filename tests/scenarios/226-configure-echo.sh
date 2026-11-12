# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a client that commits a focus change's configure only after a fly has landed keeps the place the fly wrote: KWin sends each configure with the window's place at the time and puts the window there when the client commits it, so the canvas moves a window as a move (the plugin's moveWindow, which carries the queued configures along), or, without that move, puts back a window that comes back to a spot its own write left; the window gaining the focus and the one losing it alike, and no window's plane coordinate changes"

# plane(): every window's plane coordinate while the canvas is closed: its real frame plus the camera.
plane() {
    kwinjs 'var o = []; workspace.stackingOrder.forEach(function (x) { var n = String(x.caption); ["KCalc","Konsole","sample.txt","Dolphin","Gwenview"].forEach(function (k) { if (n.indexOf(k) >= 0) o.push(k + "=" + x.frameGeometry.x + "," + x.frameGeometry.y); }); }); print("ECHPOS " + o.join(" "));' 0.45
    c state >/dev/null
    local vx vy; vx=$(sget viewx); vy=$(sget viewy)
    grep -a "ECHPOS " "$STATE/kwin.log" | tail -1 | sed 's/.*ECHPOS //' | tr ' ' '\n' | sort | awk -F'[=,]' -v vx="$vx" -v vy="$vy" '{printf "%s=%.1f,%.1f ", $1, $2 + vx, $3 + vy}'
}
activate() { kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) workspace.activeWindow = x; });" 0.3; }
put() { kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) x.frameGeometry = {x: $2, y: $3, width: x.frameGeometry.width, height: x.frameGeometry.height}; });" 0.5; }
pid_of() {
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) print(\"ECHPID \" + x.pid); });" 0.3
    grep -a "ECHPID " "$STATE/kwin.log" | tail -1 | sed 's/.*ECHPID //'
}
inside() { # is the window wholly on the screen now?
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) { var g = x.frameGeometry; print(\"ECHIN \" + (g.x >= 0 && g.y >= 0 && g.x + g.width <= workspace.virtualScreenSize.width && g.y + g.height <= workspace.virtualScreenSize.height ? \"yes\" : \"no \" + g.x + \",\" + g.y)); } });" 0.4
    grep -a "ECHIN " "$STATE/kwin.log" | tail -1 | sed 's/.*ECHIN //'
}
# hold PID: stop the client, and make sure it runs again even if the scenario stops early.
hold() { kill -STOP "$1"; ( sleep 8; kill -CONT "$1" 2>/dev/null ) & }

run_scenario() {
    source tests/lib.sh
    setcfg Perf true
    arrange >/dev/null
    c state >/dev/null
    local mover; mover=$(sget mover)
    echo "    the canvas moves windows by: $mover"
    local pid before after mark
    pid=$(pid_of KCalc)
    if [ -z "$pid" ] || [ "$pid" -le 1 ]; then
        fail "KCalc's pid not found"
        kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Perf --delete
        c state >/dev/null
        return
    fi
    # The window gaining the focus: KCalc above the screen's top edge. The activation sends KCalc
    # a configure with its place then; the stopped client commits it after the fly has landed.
    put KCalc 300 -60
    # From here on only the canvas moves KCalc (the put above is a script's move, adopted).
    mark=$(wc -l < "$STATE/kwin.log")
    activate Konsole; sleep 1.8
    before=$(plane)
    hold "$pid"
    activate KCalc; sleep 2.4
    kill -CONT "$pid"; sleep 1.5
    after=$(plane)
    assert_eq "the focused window committed its configure after the fly: no plane coordinate changed" "$after" "$before"
    assert_eq "and it stayed where the fly put it, on the screen" "$(inside KCalc)" yes
    # The window losing the focus: KCalc has it and stays on the screen through the fly to
    # Dolphin above the top edge; KCalc's configure (no longer focused) comes after the landing.
    arrange >/dev/null
    put Dolphin 780 -300
    activate KCalc; sleep 1.8
    before=$(plane)
    hold "$pid"
    activate Dolphin; sleep 2.4
    kill -CONT "$pid"; sleep 1.5
    wait
    after=$(plane)
    assert_eq "the window losing the focus committed its configure after the fly: no plane coordinate changed" "$after" "$before"
    # The Perf lines say which way it held: with the plugin's move no echo comes back, without it
    # the echo came back and was put back; KCalc was never adopted as moved either way.
    local log; log=$(tail -n +"$((mark + 1))" "$STATE/kwin.log")
    local echoes; echoes=$(grep -a 'kwin-canvas perf: reverted win=KCalc' <<<"$log" | grep -c 'why=echo')
    if [ "$mover" = plugin ]; then
        assert_eq "with the plugin's move, no echo came back to put back" "$echoes" 0
    else
        assert_eq "without it, both echoes came back and were put back" "$([ "$echoes" -ge 2 ] && echo yes || echo "no ($echoes)")" yes
    fi
    assert_eq "and no move of KCalc was adopted" "$(grep -ac 'kwin-canvas perf: moved win=KCalc' <<<"$log")" 0
    c cancel >/dev/null 2>&1
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Perf --delete
    c state >/dev/null
    arrange >/dev/null
}
