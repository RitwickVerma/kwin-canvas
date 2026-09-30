# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="floating windows: a pinned window keeps its coordinates, floats at the screen edge when the camera would push it off, bounces off the edge when pushed fast, and returns home when the camera comes back"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    # Pin KCalc: the pin itself never moves the window, and KWin's own flag
    # carries the state.
    open_1to1
    local kx; kx=$(eget KCalc index)
    c "pin $kx"
    sleep 0.3; c state
    assert_eq "the pin keeps the window at its coordinates" "$(eget KCalc x)" 100
    js 'var ws = workspace.windowList(); for (var i = 0; i < ws.length; i++) if (ws[i].caption.indexOf("KCalc") >= 0) out("PINFLAG " + ws[i].onAllDesktops);'
    assert_true "and the window is on all desktops" \
        "$(grep -a 'PINFLAG true' "$STATE/kwin.log" | wc -l)" -ge 1
    # A pan pushes the window's home off the screen: the window floats at the
    # edge, its position following the picture, never leaving the screen.
    c "pan -600 0"
    sleep 0.5; c state
    assert_true "the window floats at the screen edge" \
        "$(grep -oE 'float=\([+-][0-9]+,[+-][0-9]+\)' <<<"$LAST_STATE" | head -1 | grep -c '+')" = 1
    assert_true "and stays within the screen" \
        "$(awk -v x="$(eget KCalc x)" -v v="$(sget viewx)" 'BEGIN{print ((x-v) >= 0 && (x-v) + 480 <= 1920)}')" = 1
    # A fast push into the edge bounces: the camera slides hard, and the
    # window settles inside the screen after the slide closes.
    c cancel
    sleep 0.2
    c "slide 800 0"
    sleep 0.6; c state
    assert_true "a fast slide still leaves it on screen" \
        "$(awk -v x="$(eget KCalc fx)" 'BEGIN{print (x >= 0 && x + 480 <= 1920)}')" = 1
    # Bring the camera back to the home and the window is exactly its home
    # again.
    c open
    c home
    sleep 0.3
    c "pan 800 0"
    sleep 0.5; c state
    assert_eq "the window returns to its coordinates" "$(eget KCalc x)" 100
    assert_eq "with no float left" "$(grep -c 'float=(' <<<"$LAST_STATE")" 0
    # Unpin: the flag clears and the window is a plain window again.
    c "unpin $kx"
    sleep 0.3
    js 'var ws = workspace.windowList(); for (var i = 0; i < ws.length; i++) if (ws[i].caption.indexOf("KCalc") >= 0) out("UNPINFLAG " + ws[i].onAllDesktops);'
    assert_true "unpinning clears the flag" \
        "$(grep -a 'UNPINFLAG false' "$STATE/kwin.log" | wc -l)" -ge 1
    c cancel
    arrange >/dev/null
    assert_eq "layout restored" "$(eget KCalc fx)" 100
}
