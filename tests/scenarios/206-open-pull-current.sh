# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a window of the current activity parked far away that something pulls toward the screen right after the canvas opens (the maintainer's log: 160 such moves within 0.35 s of an open, on one activity) keeps its plane coordinate: in the overview and its cancel, and in a quiet fly"
real() { # CAPTION -> "x y"
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) print(\"OPNPOS \" + x.frameGeometry.x + \" \" + x.frameGeometry.y); });" 0.35
    grep -a "OPNPOS " "$STATE/kwin.log" | tail -1 | sed 's/.*OPNPOS //'
}
pull() { # what KWin's constraint does to a window wholly off the screen: bring it to the edge
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) { var g = x.frameGeometry; x.frameGeometry = {x: $2, y: $3, width: g.width, height: g.height}; } });" 0.35
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom true
    c state >/dev/null
    local sw; read -r _ _ sw _ <<<"$(screenrect 0)"
    kwinjs 'workspace.stackingOrder.forEach(function (x) { var n = String(x.caption);
        if (n.indexOf("Dolphin") >= 0) x.frameGeometry = {x: 9000, y: 300, width: 700, height: 360};
        if (n.indexOf("Gwenview") >= 0) x.frameGeometry = {x: 400, y: 4000, width: 460, height: 420}; });' 0.8
    # The overview: opened, the far window pulled in, cancelled.
    c open >/dev/null
    pull Dolphin $((sw - 100)) 300
    sleep 1.2
    assert_eq "overview: the pulled window is back where it was while the canvas is up" "$(real Dolphin)" "9000 300"
    c cancel >/dev/null; sleep 1.2
    assert_eq "overview: and after the cancel" "$(real Dolphin)" "9000 300"
    # A quiet fly: the window below the screen pulled up at the open.
    c "slide 300 0" >/dev/null
    pull Gwenview 400 1052
    sleep 2
    assert_eq "fly: the far window below the screen keeps its place through a fly that pulled it" "$(real Gwenview)" "100 4000"
    assert_eq "fly: and the other far window did not move with it" "$(real Dolphin)" "8700 300"
    arrange >/dev/null
}
