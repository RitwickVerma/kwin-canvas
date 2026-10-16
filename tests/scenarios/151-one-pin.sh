# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="float is on-all-desktops, one flag in both directions: the canvas pin sets it, a script or a window rule setting it floats the window on the canvas, clearing it unfloats; keep above is separate and is never touched"
flags() { # CAPTION -> "allDesktops aboveBelow" as KWin has them, via the nest log
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) w = x; }); print(\"PINFLAGS \" + w.onAllDesktops + \" \" + w.keepAbove + \" \" + w.keepBelow);" 0.6
    grep -a "PINFLAGS" "$STATE/kwin.log" | tail -1 | sed 's/.*PINFLAGS //'
}
setflag() { kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"KCalc\") >= 0) { x.$1 = $2; } });" 0.8; }
floats() { # how many windows the canvas floats (the state's floats= count)
    c state >/dev/null
    sed -n '1s/.* floats=\([0-9]*\).*/\1/p' <<<"$LAST_STATE"
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    open_1to1
    c state
    local k; k=$(eget KCalc index)
    assert_eq "starts unpinned" "$(flags KCalc)" "false false false"
    c "pin $k"
    assert_eq "the canvas pin sets on-all-desktops only" "$(flags KCalc)" "true false false"
    # A flag set from outside - a rule, the title bar's menu - floats it.
    c "unpin $k"
    assert_eq "unpinning clears it" "$(flags KCalc)" "false false false"
    setflag onAllDesktops true
    assert_eq "a script's on-all-desktops floats the window on the canvas" "$(floats)" 1
    setflag onAllDesktops false
    assert_eq "clearing it from outside unfloats" "$(floats)" 0
    # Keep above is its own flag: it neither floats nor follows.
    setflag keepAbove true
    assert_eq "keep-above alone is not a float" "$(flags KCalc)" "false true false"
    assert_eq "and the canvas holds no float for it" "$(floats)" 0
    c state; k=$(eget KCalc index)
    c "pin $k"
    assert_eq "pinning leaves keep-above as it was" "$(flags KCalc)" "true true false"
    c unpinall
    assert_eq "unpinning clears only the float" "$(flags KCalc)" "false true false"
    setflag keepAbove false
    c cancel
    arrange >/dev/null
}
