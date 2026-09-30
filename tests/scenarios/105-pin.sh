# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="floating windows: a floated window keeps its coordinates, its picture floats at the screen edge and bounces when the camera pushes it out, the hand can still move the coordinates, and the picture returns the moment the camera does"
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
    # A pan pushes the window's coordinates off the screen: the coordinates
    # do not change, and the picture floats at the edge, inside the screen.
    c "pan -600 0"
    sleep 0.5; c state
    assert_eq "the coordinates never change" "$(eget KCalc x)" 100
    local fx fy
    read -r fx fy <<<"$(grep -oE 'float=\([+-][0-9]+,[+-][0-9]+\)' <<<"$LAST_STATE" | head -1 | grep -oE '[-0-9]+' | paste -sd' ')"
    assert_true "the picture floats at the edge" \
        "$(awk -v x="$(eget KCalc x)" -v v="$(sget viewx)" -v d="$fx" 'BEGIN{print ((x-v+d) >= 0 && (x-v+d) + 480 <= 1920 && d > 100)}')" = 1
    # Move the camera back and the picture is the window again, at the same
    # coordinates.
    c "pan 600 0"
    sleep 0.5; c state
    assert_eq "the picture returns to the coordinates" "$(eget KCalc x)" 100
    assert_eq "with no float left" "$(grep -c 'float=(' <<<"$LAST_STATE")" 0
    # The hand can still move a floated window's coordinates: a drag moves
    # them, and the float follows without fighting the hand.
    c "drag $kx 200 0"
    sleep 0.4; c state
    assert_eq "a drag moves the floated window's coordinates" "$(eget KCalc x)" 300
    c "drag $kx -200 0"
    sleep 0.3
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
