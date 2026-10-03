# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the world is the map: the hold zooms the world out into the map, a drag on the ground pans it and never grabs a window, a click on a window flies there and the release commits, and a hold in the open overworld keeps the pointer in the canvas"
pt_state() { nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    # (a) One cluster: the world is the map - there is no separate overlay
    # card, the zoomed-out world serves.
    open_1to1
    c commit
    sleep 0.3; c state
    assert_eq "the desk starts as one cluster" "$(sget clusters)" 1
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 8000\nup back\n' | input &
    sleep 1.2
    c "zoom 0.6 960 540"
    sleep 1.0; c state
    assert_eq "no overlay card, ever" "$(sget map)" "-"
    assert_eq "the hold is quiet" "$(grep -c ' quiet' <<<"$LAST_STATE")" 1
    assert_eq "the grasp is on" "$(grep -c ' grasp' <<<"$LAST_STATE")" 1
    sleep 7.0
    c cancel
    arrange >/dev/null
    # (b) Two clusters and a drag on the ground: the drag pans the camera
    # and the window under it is not grabbed.
    open_1to1
    c "placeby Gwenview 4000 300 460 420"
    c commit
    sleep 0.3
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 3000\nmove 1600 800\nsleep 100\ndrag 1600 800 1400 700\nsleep 2500\nup back\n' | input &
    sleep 1.2
    c "zoom 0.6 960 540"
    sleep 1.0; c state
    local vx vy; vx=$(sget viewx); vy=$(sget viewy)
    sleep 1.6; c state
    assert_near "the ground drag pans the camera x" "$(sget viewx)" "$(awk -v v="$vx" 'BEGIN{print v + 200 / 0.6}')" 2
    assert_near "the ground drag pans the camera y" "$(sget viewy)" "$(awk -v v="$vy" 'BEGIN{print v + 100 / 0.6}')" 2
    assert_eq "the drag never grabbed the window" "$(eget Gwenview x)" 4000
    sleep 2.3
    c cancel
    arrange >/dev/null
    # (c) A click on a window during the hold flies the location there and
    # the release commits it.
    open_1to1
    c "placeby Gwenview 4000 300 460 420"
    c commit
    sleep 0.3
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 4000\nmove 978 444\nsleep 100\nclick\nsleep 1500\nup back\n' | input &
    sleep 1.2
    c "zoom 0.6 960 540"
    local i
    for i in $(seq 1 80); do c state; [ "$(sget visible)" = false ] && break; sleep 0.15; done
    sleep 0.3; c state
    assert_eq "the window click commits the location" "$(sget visible)" false
    assert_near "the fly lands with the window on screen" "$(sget viewx)" -556.0 2
    # No vertical pan: KWrite's 520 px already fit vertically at this view
    # (its bottom, canvas 640, sits above viewY+1080-24 = 696).
    assert_near "and vertically" "$(sget viewy)" -360.0 2
    assert_true "the location brings the clicked window wholly on screen" \
        "$(awk -v x="$(eget KWrite fx)" 'BEGIN{print (x >= 0 && x + 700 <= 1920)}')" = 1
    arrange >/dev/null
    # (d) A hold in the open overworld stays in the canvas: the pointer over
    # a real window never hands to it.
    open_1to1
    c "placeby Konsole 900 350 620 420"
    c "placeby Gwenview 4000 300 460 420"
    sleep 0.3
    c "zoom 0.4 960 540"
    sleep 0.6; c state
    assert_eq "the overworld is open" "$(sget visible)" true
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 7000\nup back\n' | input &
    sleep 1.0; c state
    assert_eq "the overworld hold has no map card" "$(sget map)" "-"
    if nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        input move 250 90
        sleep 0.8
        assert_eq "the hold keeps the hover out of the real window" \
            "$(pt_state | grep -c 'hover=-')" 1
        input click
        sleep 0.4
        assert_eq "the hold keeps the press out of the real window" \
            "$(pt_state | grep -c 'grab=-')" 1
    else
        skip "pass-through plugin not answering (85-passthrough)"
    fi
    sleep 5.2; c state
    assert_eq "the release returns to the overworld" "$(sget visible)" true
    assert_eq "the overworld is not quiet" "$(grep -c ' quiet' <<<"$LAST_STATE")" 0
    c cancel
    arrange >/dev/null
    # (e) A window click during the overworld hold flies, and the release
    # keeps the overworld open at the flown location.
    open_1to1
    c "placeby Konsole 900 350 620 420"
    c "placeby Gwenview 4000 300 460 420"
    sleep 0.3
    c "zoom 0.4 960 540"
    sleep 0.6
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 4000\nmove 900 420\nsleep 150\nclick\nsleep 500\nup back\n' | input &
    local i
    for i in $(seq 1 60); do c state; [ "$(sget zoom)" = "1.0000" ] && break; sleep 0.15; done
    sleep 0.5; c state
    assert_eq "the overworld stays open after the window fly" "$(sget visible)" true
    assert_near "the fly lands with the window on screen" "$(sget viewx)" -556.0 2
    assert_near "and vertically" "$(sget viewy)" -416.0 2
    c cancel
    arrange >/dev/null
}
