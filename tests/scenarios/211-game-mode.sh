# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="game mode: while a fullscreen window has the focus and the canvas is closed, the canvas stands aside - a corner push does not open it, and the plugin stops taking the canvas's hold buttons - and all of it comes back when the fullscreen window leaves; FullscreenPause off keeps the canvas as it was"

game() { c state >/dev/null; grep -o ' game=[01]' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2; }
pt_hold() { nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state 2>/dev/null | grep -o 'hold=[0-9]*' | cut -d= -f2; }

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    setcfg CanvasHold ForwardButton
    c state >/dev/null; sleep 0.5
    local plugin=0
    nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1 && plugin=1
    assert_eq "no game at first" "$(game)" 0
    [ "$plugin" = 1 ] && assert_true "the plugin takes the hold button" "$(pt_hold)" -ne 0

    c "activate KCalc"; sleep 0.3
    c "fullscreen KCalc on"; sleep 0.8
    assert_eq "a fullscreen window with the focus is game mode" "$(game)" 1
    [ "$plugin" = 1 ] && assert_eq "the plugin lets the hold button through" "$(pt_hold)" 0
    if have_input; then
        push_border 7; sleep 0.8; c state
        assert_eq "a corner push does not open the canvas over the game" "$(sget visible)" false
    fi

    c "fullscreen KCalc off"; sleep 0.8
    assert_eq "the fullscreen window left: game mode ends" "$(game)" 0
    [ "$plugin" = 1 ] && assert_true "the hold button is the canvas's again" "$(pt_hold)" -ne 0
    if have_input; then
        push_border 7; sleep 0.8; c state
        assert_eq "and a corner push opens the canvas again" "$(sget visible)" true
        c cancel >/dev/null; sleep 0.8
    fi

    setcfg FullscreenPause false
    c "fullscreen KCalc on"; sleep 0.8
    assert_eq "FullscreenPause off: no game mode" "$(game)" 0
    c "fullscreen KCalc off"; sleep 0.5
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key FullscreenPause --delete
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key CanvasHold --delete
    c state >/dev/null
    arrange >/dev/null
}
