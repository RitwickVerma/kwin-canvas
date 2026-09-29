# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="pinned windows: a pinned window rides the camera and never leaves the screen, and one dragged past an edge bounces back into view"
screen_of() {
    awk -v cx="$1" -v cy="$2" -v vx="$(sget viewx)" -v vy="$(sget viewy)" -v z="$(sget zoom)" \
        'BEGIN{printf "%d %d", (cx-vx)*z, (cy-vy)*z}'
}
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # Pin KCalc: its screen spot is the anchor.
    open_1to1
    local kx; kx=$(eget KCalc index)
    c "pin $kx"
    sleep 0.3; c state
    assert_near "the pin anchors the window where it is" \
        "$(awk -v x="$(eget KCalc x)" -v v="$(sget viewx)" 'BEGIN{print x-v}')" 100 2
    # A pan moves the plane; the pinned window rides the camera and stays
    # exactly where it was on screen.
    c "pan -600 0"
    sleep 0.4; c state
    assert_near "the pinned window rides the camera" \
        "$(awk -v x="$(eget KCalc x)" -v v="$(sget viewx)" 'BEGIN{print x-v}')" 100 2
    assert_near "while the plane moved under it" "$(sget viewx)" 600 2
    # Dragging it past the right edge and letting go: it bounces back inside.
    c "snap edges off"; c "snap corners off"; c "snap grid off"
    read -r tx ty <<<"$(screen_of $(( $(eget KCalc x) + 240 )) $(( $(eget KCalc y) + 22 )))"
    printf 'move %d %d\nsleep 60\ndown left\nsleep 60\nglide 2200 %d 20 10\nsleep 60\nup left\n' "$tx" "$ty" "$ty" | input
    sleep 1.6; c state
    assert_true "it bounced back wholly into the screen" \
        "$(awk -v x="$(eget KCalc x)" -v v="$(sget viewx)" 'BEGIN{print ((x-v) >= 0 && (x-v) + 480 <= 1920)}')" = 1
    # Unpin: the window returns to the plane like any other.
    c "unpin $kx"
    c cancel
    arrange >/dev/null
    assert_eq "layout restored" "$(eget KCalc fx)" 100
}
