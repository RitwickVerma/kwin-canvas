# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a window that leaves maximized or tiled after the view has slid goes back to where the plane had it, not to the screen spot KWin remembered"
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    open_1to1
    c state
    local x0 y0; x0=$(eget KWrite x); y0=$(eget KWrite y)
    c cancel
    sleep 0.4
    # Maximize, slide the view, unmaximize.
    kwinjs "$FIND_KWRITE w.setMaximize(true, true);" 1.2
    cmd "slide 300 200" >/dev/null 2>&1
    sleep 1.8
    kwinjs "$FIND_KWRITE w.setMaximize(false, false);" 1.4
    open_1to1
    c state
    assert_near "unmaximized after a slide: back on its plane spot, x" "$(eget KWrite x)" "$x0" 2
    assert_near "and y" "$(eget KWrite y)" "$y0" 2
    c cancel
    sleep 0.4
    # The same for a KWin tile.
    kwinjs "$FIND_KWRITE workspace.activeWindow = w; workspace.slotWindowQuickTileLeft();" 1.4
    cmd "slide -200 150" >/dev/null 2>&1
    sleep 1.8
    kwinjs "$FIND_KWRITE w.tile = null;" 1.4
    open_1to1
    c state
    assert_near "untiled after a slide: back on its plane spot, x" "$(eget KWrite x)" "$x0" 2
    assert_near "and y" "$(eget KWrite y)" "$y0" 2
    c cancel
    sleep 0.4
    cmd "slide 0 0" >/dev/null 2>&1
    arrange >/dev/null
}
