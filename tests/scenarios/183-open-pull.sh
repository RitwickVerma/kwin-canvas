# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="opening the canvas shows the windows of the other activities in its scene, and KWin then pulls the ones that are partly or wholly off the screen to its edge (4000 became 1820, a plane coordinate gone); the canvas puts them back, so an open, a close and a slide leave a parked window of another activity where it was, and a plain hold with no drag moves no window at all"
# gwframe: Gwenview's real frame, "x,y", straight from KWin.
gwframe() {
    kwinjs 'var o = ""; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Gwenview") >= 0) o = Math.round(x.frameGeometry.x) + "," + Math.round(x.frameGeometry.y); }); print("GWFRAME " + o);' 0.4
    grep -a "GWFRAME " "$STATE/kwin.log" | tail -1 | sed 's/.*GWFRAME //'
}
# allframes: every fixture window's real frame, in a fixed order.
allframes() {
    kwinjs 'var o = []; ["KCalc","sample.txt","Konsole","Dolphin","Gwenview"].forEach(function (k) { workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(k) >= 0) { var g = x.frameGeometry; o.push(k + "=" + Math.round(g.x) + "," + Math.round(g.y) + "," + Math.round(g.width) + "x" + Math.round(g.height)); } }); }); print("ALLFRAMES " + o.join(" "));' 0.4
    grep -a "ALLFRAMES " "$STATE/kwin.log" | tail -1 | sed 's/.*ALLFRAMES //'
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    c state >/dev/null
    assert_eq "the second activity's frame sits at 2160" "$(tget 1 x)" 2160
    # Gwenview is given the second activity and, a moment later (the activity change's own check
    # has run by then), written at x=4000: wholly off the 1920 px screen, in an activity that is
    # not the current one, where only the canvas's scene will show it.
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"Gwenview\") >= 0) w = x; }); w.activities = [\"$ACT2\"];" 0.8
    kwinjs 'var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Gwenview") >= 0) w = x; }); w.frameGeometry = {x: 4000, y: 300, width: 460, height: 420};' 0.8
    assert_eq "Gwenview is parked at 4000 in the second activity" "$(gwframe)" "4000,300"
    c open
    sleep 1.2
    c state
    assert_eq "opening the canvas leaves it at 4000" "$(gwframe)" "4000,300"
    assert_eq "and its plane x is that plus the second activity's frame, 6160" "$(eget Gwenview x)" 6160
    c cancel
    sleep 0.8
    assert_eq "closing leaves it" "$(gwframe)" "4000,300"
    # A quiet slide opens the canvas the same way and writes every window at its end.
    c "slide 300 0" >/dev/null
    sleep 2.0
    assert_eq "a slide leaves it" "$(gwframe)" "4000,300"
    c state
    # Put Gwenview back where arrange keeps it.
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"Gwenview\") >= 0) w = x; }); w.activities = [\"$ACT1\"]; w.frameGeometry = {x: 1400, y: 120, width: 460, height: 420};" 0.8
    arrange >/dev/null
    # A plain hold, no drag, no zoom: the grasp opens the canvas quietly at 1:1 and the release
    # commits the location. No window may move by any amount.
    local before after
    before=$(allframes)
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 1500\nup back\n' | input &
    sleep 0.8
    c state
    assert_eq "the hold is quiet and grasped" "$(grep -c ' quiet grasp' <<<"$LAST_STATE")" 1
    sleep 1.6
    c state
    after=$(allframes)
    assert_eq "the hold is over" "$(sget visible)" false
    assert_eq "a plain hold moves no window" "$after" "$before"
    arrange >/dev/null
}
