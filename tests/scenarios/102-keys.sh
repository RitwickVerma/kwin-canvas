# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="keyboard navigation in the open canvas: the arrow keys pan the camera one step, Tab steps the selection through the windows with the camera following, Shift+Tab steps back, and Enter with a window selected steps into it"
selected() { grep -c "^  \[[0-9]*\] \*" <<<"$LAST_STATE"; }
selcap() { grep -a "^  \[[0-9]*\] \*" <<<"$LAST_STATE" | head -1; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    open_1to1
    c "zoom 0.5 960 540"
    # The arrow keys pan the camera one step each, left first.
    local vx; vx=$(sget viewx)
    printf 'key left\n' | input
    sleep 0.4; c state
    assert_near "left arrow pans one step" "$(sget viewx)" "$(awk -v x="$vx" 'BEGIN{print x-1920}')" 2
    printf 'key right\n' | input
    sleep 0.4; c state
    assert_near "right arrow pans back" "$(sget viewx)" "$vx" 2

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
    c cancel
    arrange >/dev/null
}
