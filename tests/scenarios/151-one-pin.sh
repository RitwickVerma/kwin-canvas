# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="one pin, synced: the canvas's pin sets on-all-desktops and keep-above together, either flag set by KWin reads as pinned on the canvas, and unpinning clears both"
flags() { # CAPTION -> "allDesktops aboveBelow" as KWin has them, via the nest log
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) w = x; }); print(\"PINFLAGS \" + w.onAllDesktops + \" \" + w.keepAbove + \" \" + w.keepBelow);" 0.6
    grep -a "PINFLAGS" "$STATE/kwin.log" | tail -1 | sed 's/.*PINFLAGS //'
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    open_1to1
    c state
    local k; k=$(eget KCalc index)
    assert_eq "starts unpinned" "$(flags KCalc)" "false false false"
    c "pin $k"
    assert_eq "the canvas pin sets both flags" "$(flags KCalc)" "true true false"
    c state
    assert_true "and the canvas floats it" "$(grep -c 'KCalc' <<<"$LAST_STATE")" -ge 1
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) { x.onAllDesktops = false; x.keepAbove = false; x.keepBelow = true; } });' 0.8
    assert_eq "KWin cleared both and set keep-below" "$(flags KCalc)" "false false true"
    c state; k=$(eget KCalc index)
    c "pin $k"
    assert_eq "the pin clears keep-below, which would contradict it" "$(flags KCalc)" "true true false"
    # Either flag alone is a pin: the unpin clears both.
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) { x.onAllDesktops = false; } });' 0.8
    assert_eq "keep-above alone is left" "$(flags KCalc)" "false true false"
    c unpinall
    assert_eq "unpinning clears both" "$(flags KCalc)" "false false false"
    c cancel
    arrange >/dev/null
}
