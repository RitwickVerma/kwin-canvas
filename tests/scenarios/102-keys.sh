# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="keyboard navigation in the open canvas: the arrow keys pan the camera one step, Tab steps the selection through the windows with the camera following, Shift+Tab steps back, and Enter with a window selected steps into it"
selected() { grep -c "^  \[[0-9]*\] \*" <<<"$LAST_STATE"; }
selcap() { grep -a "^  \[[0-9]*\] \*" <<<"$LAST_STATE" | head -1; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # The scenario drives the canvas with its keys; with the pass-through
    # plugin live those go to the focused window, so the plugin stands down
    # for this one (the plugin's own scenario is 85).
    setcfg Passthrough false
    open_1to1
    c "zoom 0.5 960 540"
    # WASD pans the camera one step each, left first.
    local vx; vx=$(sget viewx)
    printf 'key a\n' | input
    sleep 0.4; c state
    assert_near "a pans one step" "$(sget viewx)" "$(awk -v x="$vx" 'BEGIN{print x-1920}')" 2
    printf 'key d\n' | input
    sleep 0.4; c state
    assert_near "d pans back" "$(sget viewx)" "$vx" 2
    local vy; vy=$(sget viewy)
    printf 'key w\n' | input
    sleep 0.4; c state
    assert_near "w pans up one step" "$(sget viewy)" "$(awk -v y="$vy" 'BEGIN{print y-1080}')" 2

    # Tab steps the selection through the entries in stacking order - KWrite
    # first - and Enter with it selected steps into that window, focused.
    printf 'key tab\n' | input
    sleep 0.4; c state
    assert_eq "tab selected the first window" "$(selected)" 1
    assert_eq "which is KWrite" "$(grep -c 'sample.txt' <<<"$(selcap)")" 1
    printf 'key enter\n' | input
    sleep 0.6; c state
    assert_eq "enter with it selected stepped in" "$(sget visible)" false
    assert_eq "focused on it" "$(grep -c 'active="sample.txt' <<<"$LAST_STATE")" 1

    # The camera follows the selection: a window parked far away, Tabbed to,
    # is brought into view. arrange() restores the fixed layout and stack
    # first - the Enter above raised KWrite, which reordered the entries.
    arrange >/dev/null
    open_1to1
    c "placeby Gwenview 8000 0"
    c clearsel
    printf 'key tab\nsleep 80\nkey tab\nsleep 80\nkey tab\nsleep 80\nkey tab\n' | input
    sleep 0.5; c state
    assert_eq "tabbed through to Gwenview" "$(grep -c 'Gwenview' <<<"$(selcap)")" 1
    assert_true "and the camera followed it out there" \
        "$(awk -v x="$(sget viewx)" 'BEGIN{print (x > 6000)}')" = 1
    # Shift+Tab steps the other way, and the camera follows back.
    printf 'key shift down\nkey tab\nkey shift up\n' | input
    sleep 0.5; c state
    assert_eq "shift+tab stepped back to Dolphin" "$(grep -c 'Dolphin' <<<"$(selcap)")" 1
    # A click on a window brings it wholly into view: KCalc parked with only
    # a sliver on screen, clicked on the sliver, is fitted by the camera.
    open_1to1
    c "placeby KCalc 1800 120"
    c state
    printf 'move 1900 142\nclick\n' | input
    sleep 0.4; c state
    assert_true "a click pans the window wholly into view" \
        "$(awk -v x="$(sget viewx)" 'BEGIN{print (x > 300 && x < 500)}')" = 1
    # A click focuses the window: the keyboard follows it. The hover makes a
    # window the canvas's focus too, and Enter applies with it.
    open_1to1
    c "placeby KCalc 100 120"
    c state
    printf 'move 340 142\nclick\n' | input
    sleep 0.6; c state
    assert_eq "a click focuses the window" "$(grep -c 'active="KCalc"' <<<"$LAST_STATE")" 1
    c cancel
    open_1to1
    c "placeby Gwenview 8000 0"
    c state
    printf 'move 340 142\n' | input
    sleep 0.8; c state
    assert_eq "the settled hover is the canvas focus" "$(grep -c 'focus="KCalc"' <<<"$LAST_STATE")" 1
    printf 'key enter\n' | input
    sleep 0.6; c state
    assert_eq "enter applies with the hovered window" "$(sget visible)" false
    assert_eq "and it ends focused" "$(grep -c 'active="KCalc"' <<<"$LAST_STATE")" 1
    # The digits are the plane's desks: Ctrl+1 saves the view, 1 springs back.
    c cancel
    c resetview
    open_1to1
    c "zoom 0.5 960 540"
    sleep 0.5
    c state
    printf 'key leftctrl down\nkey 1\nkey leftctrl up\n' | input
    sleep 0.4; c state
    assert_true "ctrl+1 saved the view" \
        "$(kreadconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Bookmarks | grep -ci 'spot')" -ge 1
    c home
    c "pan 500 0"
    sleep 0.3
    printf 'key 1\n' | input
    sleep 0.4; c state
    assert_near "1 springs back to the saved view" "$(sget viewx)" -960 2
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Bookmarks --delete
    c cancel
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Passthrough --delete
    arrange >/dev/null
}
