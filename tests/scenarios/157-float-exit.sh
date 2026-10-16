# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a floated window is never left behind: fly the camera far away and leave the canvas, by commit or by a quiet slide, and the window is on screen where its picture was"
onscreen() { # the pinned window's frame, wholly inside the 1920x1080 screen?
    kwinjs 'var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) w = x; }); var g = w.frameGeometry; print("FLOATFRAME " + Math.round(g.x) + " " + Math.round(g.y) + " " + Math.round(g.width) + " " + Math.round(g.height));' 0.6
    grep -a "FLOATFRAME" "$STATE/kwin.log" | tail -1 | sed 's/.*FLOATFRAME //' | awk '{print ($1 >= 0 && $2 >= 0 && $1 + $3 <= 1920 && $2 + $4 <= 1080) ? "yes" : "no " $0}'
}
run_scenario() {
    arrange >/dev/null
    open_1to1
    c state
    local k; k=$(eget KCalc index)
    c "pin $k"
    sleep 0.3
    # Fly far over the open canvas, then step in.
    c "panpx 4000 -2500" >/dev/null
    sleep 0.6
    c enter >/dev/null; sleep 1.5
    assert_eq "after a far fly and stepping in the floated window is on screen" "$(onscreen)" yes
    # The same window, left behind by a quiet slide far away.
    c state >/dev/null
    c "slide 3500 1800" >/dev/null
    sleep 2
    assert_eq "after a far slide the floated window is on screen" "$(onscreen)" yes
    c open >/dev/null; c state; k=$(eget KCalc index); c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
