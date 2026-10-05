# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="real pointer and keyboard input through fake-input: wheel, pan, drag, the chord enters"
# Screen position of a canvas point at the current camera, from the last state.
screen_of() {   # screen_of CX CY -> "SX SY"
    awk -v cx="$1" -v cy="$2" -v vx="$(sget viewx)" -v vy="$(sget viewy)" -v z="$(sget zoom)" \
        'BEGIN{printf "%d %d", (cx-vx)*z, (cy-vy)*z}'
}
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    open_1to1
    c home
    c "zoom 0.4 960 540"
    input move 1700 900
    input wheel -1
    sleep 0.3; c state
    assert_near "wheel zooms out one notch" "$(sget zoom)" 0.3478 0.002
    c home
    c "zoom 0.4 960 540"
    printf 'drag 1700 900 1500 800\n' | input
    sleep 0.3; c state
    assert_near "ground drag pans x" "$(sget viewx)" -940 2
    assert_near "ground drag pans y" "$(sget viewy)" -560 2
    # Drag KCalc by its title bar (the client area is the app's when
    # pass-through is live), 100 by 50 screen px: 250 by 125 canvas units
    # at zoom 0.4. Snapping off: this measures the drag, not the snap (98
    # covers snapping).
    c "snap edges off"; c "snap corners off"; c "snap grid off"
    # The canvas pitches into perspective below 1:1, so the title bar the
    # eye sees sits where the flat math projects it: push the flat point
    # through the tilt before pressing it (the effect's own closed form,
    # dz 0).
    proj() {
        awk -v px="$1" -v py="$2" 'BEGIN {
            t = (1 - 0.4) * 0.42; d = 900; cx = 960; cy = 540;
            x0 = px - cx; y0 = py - cy;
            w = d - y0 * sin(t);
            printf "%d %d\n", int(cx + d * x0 / w), int(cy + d * y0 * cos(t) / w);
        }'
    }
    read -r sx sy <<<"$(proj $(screen_of $(( $(eget KCalc x) + 240 )) $(( $(eget KCalc y) + 22 ))))"
    printf "drag $sx $sy $((sx + 100)) $((sy + 50))\n" | input
    sleep 0.3; c state
    # The tilt's affine approximation leaves a small perspective residue on
    # the drag (the window's own scale k is constant, the true gradient is
    # not): the tolerance absorbs the measured <2%.
    assert_near "window drag moves x" "$(eget KCalc x)" 350 8
    assert_near "window drag moves y" "$(eget KCalc y)" 245 8
    snap input-dragged
    # The chord enters the location under the screen centre: canvas
    # (1460, 790) at this camera, so the viewport lands at (500, 250) and
    # KCalc is written relative to it, where the drag left it on the plane.
    printf 'key leftctrl down\nkey leftalt down\nkey space\nkey leftalt up\nkey leftctrl up\n' | input
    sleep 0.6; c state
    assert_eq "the chord enters" "$(sget visible)" false
    assert_near "KCalc written relative to the entered viewport x" "$(eget KCalc fx)" -150 8
    assert_near "KCalc written relative to the entered viewport y" "$(eget KCalc fy)" -5 8
    arrange >/dev/null
}
