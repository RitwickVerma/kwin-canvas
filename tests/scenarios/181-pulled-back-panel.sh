# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a panel that changes size recalculates KWin's work area and KWin pulls windows parked outside every monitor back in; with a real panel, the canvas puts them back where they were"
pos3() {
    kwinjs 'var o = []; workspace.stackingOrder.forEach(function (x) { var n = String(x.caption); ["KCalc","Konsole","sample.txt"].forEach(function (k) { if (n.indexOf(k) >= 0) o.push(k + "=" + Math.round(x.frameGeometry.x) + "," + Math.round(x.frameGeometry.y)); }); }); print("PANPOS " + o.join(" "));' 0.4
    grep -a "PANPOS " "$STATE/kwin.log" | tail -1 | sed 's/.*PANPOS //'
}
run_scenario() {
    local i got=0 seeded=0 c2
    for i in $(seq 1 40); do
        c2=$(nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "print('PANELCOUNT:' + panels().length)" 2>/dev/null || true)
        case "$c2" in *PANELCOUNT:[1-9]*) got=1; break ;; esac
        if [ "$seeded" = 0 ] && [ "$i" -ge 6 ]; then
            nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.loadLookAndFeelDefaultLayout "org.kde.plasma.desktop" >/dev/null 2>&1
            seeded=1
        fi
        sleep 0.5
    done
    if [ "$got" != 1 ]; then skip "no plasmashell panel (make test-panel)"; return; fi
    source tests/lib.sh
    arrange >/dev/null
    kwinjs 'workspace.stackingOrder.forEach(function (x) { var n = String(x.caption); if (n.indexOf("KCalc") >= 0) x.frameGeometry = {x: 4000, y: 100, width: 480, height: 420}; if (n.indexOf("Konsole") >= 0) x.frameGeometry = {x: 100, y: 1500, width: 620, height: 420}; if (n.indexOf("sample.txt") >= 0) x.frameGeometry = {x: -900, y: 100, width: 700, height: 520}; });' 0.6
    sleep 1
    local parked; parked=$(pos3)
    assert_eq "three windows parked far outside the monitor" "$parked" "sample.txt=-900,100 Konsole=100,1500 KCalc=4000,100"
    nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "panels()[0].height = 90" >/dev/null 2>&1
    sleep 3
    assert_eq "a panel that grew left the parked windows where they were" "$(pos3)" "$parked"
    nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "panels()[0].height = 46" >/dev/null 2>&1
    sleep 3
    assert_eq "and shrinking it again did too" "$(pos3)" "$parked"
    arrange >/dev/null
}
