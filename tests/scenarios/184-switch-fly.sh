# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="switching to an activity whose window is parked off the screen makes KWin show the window and pull it to the screen's edge, and the canvas's focus fly (a quiet slide to the window) had already measured its destination from the parked spot: the entry followed the pull, the fly landed the window at x=-744, wholly off the screen; the canvas puts the pull back, so the fly brings the window wholly into view and its plane coordinate never changes"
gwframe() {
    kwinjs 'var o = ""; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Gwenview") >= 0) o = Math.round(x.frameGeometry.x) + "," + Math.round(x.frameGeometry.y); }); print("GWFRAME " + o);' 0.4
    grep -a "GWFRAME " "$STATE/kwin.log" | tail -1 | sed 's/.*GWFRAME //'
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    c state >/dev/null
    assert_eq "the second activity's frame sits at 2160" "$(tget 1 x)" 2160
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"Gwenview\") >= 0) w = x; }); w.activities = [\"$ACT2\"];" 0.8
    kwinjs 'var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Gwenview") >= 0) w = x; }); w.frameGeometry = {x: 4000, y: 300, width: 460, height: 420};' 0.8
    assert_eq "Gwenview is parked at 4000 in the second activity" "$(gwframe)" "4000,300"
    # The switch, as the activity switcher does it; the one window of that activity is activated and
    # the canvas flies to it.
    c "activity 1"
    sleep 2.5
    c state
    assert_eq "the second activity is current" "$(sget activity)" "Activity 2"
    assert_eq "the canvas is closed again" "$(sget visible)" false
    local x y; IFS=, read -r x y <<<"$(gwframe)"
    assert_true "the fly brought Gwenview wholly onto the screen (x=$x)" "$(awk -v x="$x" 'BEGIN{print (x >= 0 && x + 460 <= 1920)}')" = 1
    c open
    sleep 0.5
    assert_eq "its plane x never changed" "$(eget Gwenview x)" 6160
    c cancel
    # Back to the first activity, the second one's frame where it was, Gwenview where arrange keeps it.
    local tx; tx=$(tget 1 x)
    c "shift $((tx - 2160)) 0"
    sleep 0.3
    c "activity 0"
    sleep 1.5
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"Gwenview\") >= 0) w = x; }); w.activities = [\"$ACT1\"]; w.frameGeometry = {x: 1400, y: 120, width: 460, height: 420};" 0.8
    arrange >/dev/null
    c state >/dev/null
    assert_eq "the second activity's frame is back at 2160" "$(tget 1 x)" 2160
}
