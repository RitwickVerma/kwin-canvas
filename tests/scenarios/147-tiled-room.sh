# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a tiled layout is a room: taking one tiled window by the hand moves every tiled window of its cluster, while a free window moves alone"
tile() { # caption side(Left|Right)
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) w = x; }); workspace.activeWindow = w; workspace.slotWindowQuickTile$2();" 1.3
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    tile KWrite Left
    tile KCalc Right
    open_1to1
    c state
    local kw kc ko; kw=$(eget KWrite index); kc=$(eget KCalc index); ko=$(eget Konsole index)
    local wx wy cx cy ox oy
    wx=$(eget KWrite x); wy=$(eget KWrite y); cx=$(eget KCalc x); cy=$(eget KCalc y); ox=$(eget Konsole x); oy=$(eget Konsole y)
    c "drag $kw 150 90"
    c state
    assert_near "the dragged tile moves, x" "$(eget KWrite x)" "$((wx + 150))" 2
    assert_near "the other tile moves with it, x" "$(eget KCalc x)" "$((cx + 150))" 2
    assert_near "and y" "$(eget KCalc y)" "$((cy + 90))" 2
    # A free window is its own set, even when it sits in the same cluster.
    c cancel
    c state
    open_1to1
    c "drag $ko 60 40"
    c state
    assert_near "a free window moves alone: the tile stays, x" "$(eget KWrite x)" "$wx" 2
    assert_near "and the free one moved" "$(eget Konsole x)" "$((ox + 60))" 2
    c cancel
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (x.tile) x.tile = null; });' 1.2
    arrange >/dev/null
}
