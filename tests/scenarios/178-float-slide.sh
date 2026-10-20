# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a slide or fly leaves a floated window where it is on the screen (it does not ride to an edge and land there), while the windows that are not floated move with the desk"
real() { # CAPTION -> "x y"
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) w = x; }); var g = w.frameGeometry; print(\"FLSL \" + Math.round(g.x) + \" \" + Math.round(g.y));" 0.4
    grep -a "FLSL" "$STATE/kwin.log" | tail -1 | sed 's/.*FLSL //'
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    open_1to1; c state >/dev/null
    local k; k=$(eget KCalc index)
    c "pin $k"; sleep 0.3
    c cancel >/dev/null; sleep 0.8
    local before; before=$(real KCalc)
    local kon; kon=$(real Konsole)
    c "slide 700 300" >/dev/null; sleep 1.8
    assert_eq "a floated window stays where it was on the screen through a slide" "$(real KCalc)" "$before"
    assert_true "a window that is not floated moved with the desk" "$(real Konsole)" != "$kon"
    c "slide -2500 900" >/dev/null; sleep 2.2
    assert_eq "and through a far fly" "$(real KCalc)" "$before"
    c open >/dev/null; c state >/dev/null; c "unpin $(eget KCalc index)" >/dev/null
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
