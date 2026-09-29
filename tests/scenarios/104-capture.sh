# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="input capture lifecycle: a lingering hover pans the window into view, a close asked for mid-gesture waits for the buttons to come up, and releasing the modifier before the window does the same"
screen_of() {
    awk -v cx="$1" -v cy="$2" -v vx="$(sget viewx)" -v vy="$(sget viewy)" -v z="$(sget zoom)" \
        'BEGIN{printf "%d %d", (cx-vx)*z, (cy-vy)*z}'
}
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # The hover navigation: KCalc parked with only a sliver on screen, the
    # pointer resting on the sliver for a moment, the camera pans the least
    # that fits the window wholly into view.
    open_1to1
    c "placeby KCalc 1800 120"
    c state
    input move 1900 142
    sleep 0.6; c state
    assert_true "a lingering hover pans the window into view" \
        "$(awk -v x="$(sget viewx)" 'BEGIN{print (x > 300 && x < 500)}')" = 1
    c cancel

    # A close asked for mid-drag waits: the chord while a window drag is in
    # hand parks the commit until the button comes up, so the still-held
    # button never becomes a native drag on whatever is under the pointer.
    open_1to1
    local kx ky
    read -r kx ky <<<"$(screen_of 340 142)"
    printf 'move %d %d\nsleep 60\ndown left\nsleep 60\nglide %d %d 20 10\nsleep 60\nkey leftctrl down\nkey leftalt down\nkey space\nkey leftalt up\nkey leftctrl up\nsleep 300\nglide %d %d 10 10\nsleep 300\nup left\n' \
        "$kx" "$ky" "$((kx + 160))" "$((ky + 140))" "$((kx + 360))" "$ky" | input &
    sleep 0.8; c state
    assert_eq "the chord waits while the drag is in hand" "$(sget visible)" true
    sleep 0.8; c state
    assert_eq "and the release closes it" "$(sget visible)" false
    assert_near "the dragged window was written" "$(eget KCalc fx)" 460 2
    assert_eq "and the window the pointer crossed was not moved natively" "$(eget sample.txt fx)" 640

    # The modifier released before the window: the grasp holds the commit
    # until the drag's button is up too. (The canvas is closed here; held
    # while the overworld is open, the modifier is navigation only. arrange
    # restores the layout the section 2 drag moved.)
    arrange >/dev/null
    c state
    assert_eq "closed for the grasp" "$(sget visible)" false
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 800\nmove 340 142\nsleep 60\ndown left\nsleep 60\nglide 190 82 20 10\nsleep 60\nup back\nsleep 700\nup left\n' | input &
    sleep 0.7; c state
    assert_eq "the grasp is open" "$(head -1 <<<"$LAST_STATE" | grep -c 'visible=true quiet grasp')" 1
    sleep 0.8; c state
    assert_eq "releasing the modifier first keeps the grasp while the window is in hand" \
        "$(head -1 <<<"$LAST_STATE" | grep -c 'visible=true quiet grasp')" 1
    sleep 0.9; c state
    assert_eq "and the window's release commits" "$(sget visible)" false
    assert_near "with the window written where the hand put it" "$(eget KCalc fx)" -50 2
    wait
    arrange >/dev/null
}
