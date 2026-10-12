# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="navigation while a pan button or the middle button is held: the held button is a portal into the canvas (a drag on the ground pans, a drag on a window moves it, an edge keeps panning with the window in hand), the middle button pans from anywhere, the wheel zooms"
# Screen position of a canvas point at the current camera, from the last state.
screen_of() {   # screen_of CX CY -> "SX SY"
    awk -v cx="$1" -v cy="$2" -v vx="$(sget viewx)" -v vy="$(sget viewy)" -v z="$(sget zoom)" \
        'BEGIN{printf "%d %d", (cx-vx)*z, (cy-vy)*z}'
}
# A point on a window's title bar, in screen coordinates.
title_of() {    # title_of CAPTION -> "SX SY"
    echo "$(screen_of $(( $(eget "$1" x) + 240 )) $(( $(eget "$1" y) + 22 )))"
}
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # The scenario exercises the right-button portal end to end; the default
    # (empty, the middle button always navigates) is what the nest starts
    # with. PanHold is a config key, so pin it for the body of the scenario,
    # and stand the pass-through plugin down: this scenario measures the
    # QML-side portal, and its Esc belongs to the canvas (85 covers the
    # plugin).
    setcfg PanHold RightButton
    setcfg Passthrough false
    c state
    # Hold the right button (PanHold) on the ground and travel 200 by 100 screen
    # pixels left and up: the canvas pans the same 200 by 100, the gesture a
    # middle drag gives. One fakeinput process holds the button across the
    # move, so the drag is a drag.
    open_1to1                     # view (0,0) at 1:1: screen and canvas agree
    printf 'move 1700 900\nsleep 60\ndown right\nsleep 60\nglide 1500 800\nsleep 60\nup right\n' | input
    sleep 0.3; c state
    assert_near "held-button drag pans x" "$(sget viewx)" 200 3
    assert_near "held-button drag pans y" "$(sget viewy)" 100 3

    # The same hold starting on a window takes the window instead: the body
    # grip takes the PanHold buttons too, so a held right button on a window is
    # a portal into the canvas - the window moves on the plane and the camera
    # stays where it was put. With the pass-through plugin or the plane-input
    # shim live the app under it never sees the press at all (planeNavButtons
    # is the mask both hand to the canvas); with neither, as here, the press is
    # the canvas's anyway and the same rule decides what the drag does.
    c cancel; open_1to1
    c "placeby KCalc 100 120"
    local kx ky; read -r kx ky <<<"$(title_of KCalc)"
    printf "move $kx $ky\nsleep 60\ndown right\nsleep 60\nglide %d %d\nsleep 60\nup right\n" \
        "$((kx - 150))" "$((ky - 60))" | input
    sleep 0.3; c state
    assert_near "a held drag on a window moves the window" "$(eget KCalc x)" -50 2
    assert_near "and moves it that way on y too" "$(eget KCalc y)" 60 2
    assert_near "and leaves the camera alone" "$(sget viewx)" 0 2
    assert_eq "and fires no window gesture" "$(sget menus)" 0

    # The client area is the window too: the same drag from inside it moves the
    # window rather than panning. That is the point of the portal - with
    # pass-through live the press would otherwise be the app's.
    c cancel; open_1to1
    c "placeby KCalc 100 120"
    read -r kx ky <<<"$(screen_of $(( $(eget KCalc x) + 240 )) $(( $(eget KCalc y) + 90 )))"
    printf "move $kx $ky\nsleep 60\ndown right\nsleep 60\nglide %d %d\nsleep 60\nup right\n" \
        "$((kx + 120))" "$((ky + 80))" | input
    sleep 0.3; c state
    assert_near "a held drag inside a client area moves the window" "$(eget KCalc x)" 220 2
    assert_near "and moves it that way on y too" "$(eget KCalc y)" 200 2
    assert_near "and leaves the camera alone" "$(sget viewx)" 0 2

    # A pointer parked in the right edge band with the button held pans on its
    # own, revealing what lies beyond the edge - the scroll direction of any
    # map, the desk pulled the other way - and stops the moment the button is
    # let go: no drag, no motion, just the hold. The band is EdgePanMargin
    # wide, so 1918 is inside it; 540 is in no other band.
    c cancel; open_1to1
    printf 'move 1918 540\nsleep 60\ndown right\nsleep 900\n' | input
    c state
    assert_true "the edge pans while the button is held" \
        "$(awk -v v="$(sget viewx)" 'BEGIN{print (v > 100)}')" = 1
    assert_near "and pans that axis only" "$(sget viewy)" 0 2
    printf 'up right\n' | input
    sleep 0.4; c state
    local parked; parked=$(sget viewx)
    sleep 0.7; c state
    assert_near "and stops when the button is let go" "$(sget viewx)" "$parked" 4

    # The wheel zooms at the cursor with the button held, one notch a step: a
    # notch down is a step out, as it is with no button held.
    c cancel; open_1to1
    printf 'move 1700 900\nsleep 60\ndown right\nsleep 60\nwheel -1\nsleep 60\nup right\n' | input
    sleep 0.3; c state
    assert_near "the wheel zooms out while the button is held" "$(sget zoom)" 0.8696 0.002

    # The middle button navigates with nothing configured anywhere: the drag has
    # always taken it, and the hold does too. PanHold is still RightButton here,
    # so what follows is the middle button alone. A drag from a window's title
    # bar pans the canvas, and no window gesture fires: middle-click is bound to
    # nothing.
    c cancel; open_1to1
    read -r kx ky <<<"$(title_of KCalc)"
    printf "move $kx $ky\nsleep 60\ndown middle\nsleep 60\nglide %d %d\nsleep 60\nup middle\n" \
        "$((kx - 140))" "$((ky - 60))" | input
    sleep 0.3; c state
    assert_near "middle drag over a window pans the canvas" "$(sget viewx)" 140 4
    assert_near "and pans that axis too" "$(sget viewy)" 60 4
    assert_eq "and moves no window" "$(eget KCalc x)" 100
    assert_eq "and fires no window gesture" "$(sget menus)" 0

    # Held and parked in the edge band it pans on its own, the same hold any
    # PanHold button gives, and stops the moment it is let go.
    c cancel; open_1to1
    printf 'move 1918 540\nsleep 60\ndown middle\nsleep 900\n' | input
    c state
    assert_true "the edge pans with the middle button held" \
        "$(awk -v v="$(sget viewx)" 'BEGIN{print (v > 100)}')" = 1
    assert_near "and pans that axis only" "$(sget viewy)" 0 2
    printf 'up middle\n' | input
    sleep 0.4; c state
    local mparked; mparked=$(sget viewx)
    sleep 0.7; c state
    assert_near "and stops when the middle button is let go" "$(sget viewx)" "$mparked" 4

    # A navigate button held into the corner is navigation, not a push into the
    # border: the Screen Edges handler must leave the canvas open (scenario 90
    # covers the bare push that toggles it). The hold counts from the press and
    # the drag from the first motion, so either one keeps the corner off.
    c cancel; open_1to1
    printf 'down middle\nmove 0 0\nsleep 120\nrel -20 -20\nsleep 500\n' | input
    c state
    assert_eq "a held middle button keeps the corner from closing the canvas" "$(sget visible)" true
    printf 'up middle\n' | input
    sleep 0.3; c state
    assert_eq "and it is still open once the button is let go" "$(sget visible)" true

    # A window in hand at the screen edge keeps the canvas panning and comes
    # along with it: the camera's own step is added to the window, so its screen
    # position does not change - it stays under the pointer, a drag and drop
    # edge scroll with a desk on the plane - while it travels over the desk, and
    # the pan stops the moment the window is dropped. Snapping is off, so what
    # the window travels is exactly what the camera did.
    c cancel; open_1to1
    c "snap edges off"; c "snap corners off"; c "snap grid off"
    c "placeby KCalc 700 300"
    read -r kx ky <<<"$(title_of KCalc)"
    # Drag the title bar to the right edge and park it there. The injector runs
    # in the background - a foreground one holds the shell until its stream ends
    # - so the reads below land while the button is still down and the pointer
    # is still parked, and everything that happens between them is the edge's
    # doing: no hand motion at all.
    printf "move $kx $ky\nsleep 60\ndown right\nsleep 60\nglide 1918 %d\nsleep 400\nsleep 3000\n" "$ky" | input &
    # The glide is about a second long: read the baseline once the pointer is
    # parked at the edge. A tail of the glide landing after it would read as
    # a window that outran the camera.
    sleep 1.8; c state
    local plane0 vx0 sx0
    plane0=$(eget KCalc x)
    vx0=$(sget viewx)
    sx0=$(awk -v x="$plane0" -v v="$vx0" 'BEGIN{print x - v}')
    sleep 1; c state
    assert_true "the edge pans with a window in hand" \
        "$(awk -v v="$(sget viewx)" 'BEGIN{print (v > 300)}')" = 1
    assert_near "the window travels with the camera's step" \
        "$(awk -v p0="$plane0" -v p="$(eget KCalc x)" 'BEGIN{print p0 - p}')" \
        "$(awk -v v0="$vx0" -v v="$(sget viewx)" 'BEGIN{print v0 - v}')" 4
    assert_near "and so keeps its place under the pointer" \
        "$(awk -v x="$(eget KCalc x)" -v v="$(sget viewx)" 'BEGIN{print x - v}')" "$sx0" 4
    wait
    printf 'up right\n' | input
    sleep 1.3; c state
    local dropped; dropped=$(sget viewx)
    sleep 0.7; c state
    assert_near "and the pan stops when the window is dropped" "$(sget viewx)" "$dropped" 4

    # A right click on a window is still the arrange gesture: the hold pans, a
    # click does not.
    c cancel; open_1to1
    read -r kx ky <<<"$(title_of KCalc)"
    printf "move $kx $ky\nsleep 60\nclick right\nsleep 200\n" | input
    sleep 0.4; c state
    assert_eq "a right click on a window still opens the arrange menu" "$(sget menus)" 1
    printf 'key esc\n' | input
    sleep 0.4; c state
    assert_eq "escape closes it" "$(sget menus)" 0
    assert_eq "and leaves the canvas open" "$(sget visible)" true

    c cancel
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Passthrough --delete
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key PanHold --delete
    arrange >/dev/null
}
