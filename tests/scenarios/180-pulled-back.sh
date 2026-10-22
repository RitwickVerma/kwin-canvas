# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="KWin pulls a window that sits wholly outside every monitor back inside when the work area changes (a scale change here, a panel resize or a monitor waking on a desktop); the canvas puts such a window back where it was, and leaves a move between two places on the screen alone"
pos3() {
    kwinjs 'var o = []; workspace.stackingOrder.forEach(function (x) { var n = String(x.caption); ["KCalc","Konsole","sample.txt"].forEach(function (k) { if (n.indexOf(k) >= 0) o.push(k + "=" + Math.round(x.frameGeometry.x) + "," + Math.round(x.frameGeometry.y)); }); }); print("PULLPOS " + o.join(" "));' 0.4
    grep -a "PULLPOS " "$STATE/kwin.log" | tail -1 | sed 's/.*PULLPOS //'
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    kwinjs 'workspace.stackingOrder.forEach(function (x) { var n = String(x.caption); if (n.indexOf("KCalc") >= 0) x.frameGeometry = {x: 4000, y: 100, width: 480, height: 420}; if (n.indexOf("Konsole") >= 0) x.frameGeometry = {x: 100, y: 1500, width: 620, height: 420}; if (n.indexOf("sample.txt") >= 0) x.frameGeometry = {x: -900, y: 100, width: 700, height: 520}; });' 0.6
    sleep 1
    local parked; parked=$(pos3)
    assert_eq "three windows parked far outside the monitor" "$parked" "sample.txt=-900,100 Konsole=100,1500 KCalc=4000,100"
    run kscreen-doctor output.Virtual-0.scale.1.25 >/dev/null 2>&1; sleep 3.5
    assert_eq "a scale change leaves the parked windows where they were" "$(pos3)" "$parked"
    run kscreen-doctor output.Virtual-0.scale.1 >/dev/null 2>&1; sleep 3.5
    assert_eq "and changing it back does too" "$(pos3)" "$parked"
    # The contract is the plane's: a window that something other than the hand or the canvas moves from
    # out of reach to in reach is put back, whoever it was. To bring a window here, fly or drag.
    sleep 1
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) x.frameGeometry = {x: 500, y: 250, width: 480, height: 420}; });' 1.2
    assert_eq "a parked window moved onto the screen by a script is put back" "$(pos3 | sed 's/.*KCalc=//')" "4000,100"
    # A window that is already on the screen moved to another place on it is the maintainer's to move
    # (Gwenview stays where arrange put it; the three above are the parked ones).
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Gwenview") >= 0) x.frameGeometry = {x: 300, y: 200, width: 460, height: 420}; });' 0.8
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Gwenview") >= 0) x.frameGeometry = {x: 500, y: 250, width: 460, height: 420}; });' 0.8
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Gwenview") >= 0) print("PULLGW " + x.frameGeometry.x + "," + x.frameGeometry.y); });' 0.4
    assert_eq "a window moved from one place on the screen to another is not put back" "$(grep -a 'PULLGW ' "$STATE/kwin.log" | tail -1 | sed 's/.*PULLGW //')" "500,250"
    arrange >/dev/null
}
