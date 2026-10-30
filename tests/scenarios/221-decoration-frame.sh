# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the canvas decoration's frame is the window on the sides and at the bottom, so an effect that shapes the frame (Rounded Corners) shapes what the eye sees; the resize band sits outside the frame and a drag 3 px past the right edge still resizes the window"

# "frame-x frame-y frame-w frame-h client-x client-y client-w client-h" of the window titled $1.
geo() {
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) { var f = x.frameGeometry, c = x.clientGeometry; print(\"DFGEO \" + [f.x, f.y, f.width, f.height, c.x, c.y, c.width, c.height].map(Math.round).join(\" \")); } });" 0.3
    grep -a "DFGEO " "$STATE/kwin.log" | tail -1 | sed 's/.*DFGEO //'
}

run_scenario() {
    source tests/lib.sh
    if [ "${NEST_DECOR:-}" != canvas ]; then
        skip "the canvas decoration is not loaded (make test-decor / NEST_DECOR=canvas)"
        return
    fi
    arrange >/dev/null
    local fx fy fw fh cx cy cw ch
    read -r fx fy fw fh cx cy cw ch <<<"$(geo KCalc)"
    echo "# KCalc frame $fx,$fy ${fw}x$fh client $cx,$cy ${cw}x$ch"
    assert_eq "no border on the left" "$cx" "$fx"
    assert_eq "nor on the right" "$((cx + cw))" "$((fx + fw))"
    assert_eq "nor at the bottom" "$((cy + ch))" "$((fy + fh))"
    assert_eq "the title band is the pill's 32 px" "$((cy - fy))" 32

    if have_input; then
        # The resize band is outside the frame: a drag from 3 px past the right edge widens it.
        local y=$((fy + fh / 2)) x=$((fx + fw + 3))
        printf 'move %d %d\nsleep 150\ndown left\nsleep 100\nmove %d %d\nsleep 60\nmove %d %d\nsleep 150\nup left\nsleep 400\n' \
            "$x" "$y" "$((x + 40))" "$y" "$((x + 80))" "$y" | input
        local fw2; read -r _ _ fw2 _ _ _ _ _ <<<"$(geo KCalc)"
        assert_true "a drag 3 px past the right edge resizes the window (${fw} -> ${fw2})" "$fw2" -ge "$((fw + 60))"
    fi
    arrange >/dev/null
}
