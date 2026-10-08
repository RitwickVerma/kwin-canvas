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
    assert_true "and the window carries the on-all-desktops pin" \
        "$(grep -a 'PINFLAG true' "$STATE/kwin.log" | wc -l)" -ge 1
    # A pan pushes the window's coordinates off the screen: the coordinates
    # do not change, and the picture floats at the edge, inside the screen.
    c "pan -600 0"
    sleep 0.5; c state
    assert_eq "the coordinates never change" "$(eget KCalc x)" 100
    local fx
    read -r fx _ <<<"$(grep -oE 'float=\([+-][0-9]+,[+-][0-9]+\)' <<<"$LAST_STATE" | head -1 | grep -oE '[-0-9]+' | paste -sd' ')"
    assert_true "the picture floats at the edge" \
        "$(awk -v x="$(eget KCalc x)" -v v="$(sget viewx)" -v d="$fx" 'BEGIN{print ((x-v+d) >= 0 && (x-v+d) + 480 <= 1920 && d > 100)}')" = 1
    # Move the camera back and the picture is the window again, at the same
    # coordinates.
    c "pan 600 0"
    sleep 0.5; c state
    assert_eq "the picture returns to the coordinates" "$(eget KCalc x)" 100
    assert_eq "with no float left" "$(grep -c 'float=(' <<<"$LAST_STATE")" 0
    # Entering syncs the window to the picture: a hold that pans the camera
    # off the window and releases commits the clamped spot, so the window
    # never lands off-screen.
    c cancel
    sleep 0.2
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 1200\n' | input &
    sleep 0.6
    c "pan -1200 0"
    sleep 0.4
    printf 'up back\n' | input
    sleep 0.8; c state
    assert_true "the release commits the picture's clamped spot" \
        "$(awk -v x="$(eget KCalc fx)" 'BEGIN{print (x >= 0 && x < 100)}')" = 1
    c cancel
    arrange >/dev/null
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
