# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the overlay materializes with the keyhole: it shows for one cluster as well as many, a drag on it pans the camera and never grabs a window, its sheets fly on a left click, and a hold in the open overworld brings it back with the pointer staying in the canvas"
pt_state() { nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # (a) One cluster: the map is the plane's legend, not a prize for
    # having scattered windows - it materializes with the keyhole too.
    arrange >/dev/null
    open_1to1
    c commit
    sleep 0.3; c state
    assert_eq "the desk starts as one cluster" "$(sget clusters)" 1
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 8000\nup back\n' | input &
    sleep 1.2
    c "zoom 0.6 960 540"
    sleep 1.0; c state
    assert_eq "one cluster still brings the map" "$(sget map)" overlay
    sleep 6.5
    c cancel
    arrange >/dev/null
    # (b) Two clusters and a drag on the map: the overlay steps in, the drag
    # pans the camera, and the window under the sheet is not grabbed.
    open_1to1
    c "placeby Gwenview 4000 300 460 420"
    c commit
    sleep 0.3
    printf 'move 1592 531\nsleep 60\ndown back\nsleep 3000\nmove 1592 531\nsleep 100\ndrag 1592 531 1392 431\nsleep 2500\nup back\n' | input &
    sleep 1.2
    c "zoom 0.6 960 540"
    sleep 1.0; c state
    assert_eq "two clusters bring the overlay" "$(sget map)" overlay
    local vx vy; vx=$(sget viewx); vy=$(sget viewy)
    sleep 1.6; c state
    assert_near "the map drag pans the camera x" "$(sget viewx)" "$(awk -v v="$vx" 'BEGIN{print v + 200 / 0.6}')" 2
    assert_near "the map drag pans the camera y" "$(sget viewy)" "$(awk -v v="$vy" 'BEGIN{print v + 100 / 0.6}')" 2
    assert_eq "the drag never grabbed the window" "$(eget Gwenview x)" 4000
    sleep 2.3
    c cancel
    arrange >/dev/null
    # (c) A left click on a sheet flies the location there and the release
    # commits it.
    open_1to1
    c "placeby Gwenview 4000 300 460 420"
    c commit
    sleep 0.3
    printf 'move 1590 530\nsleep 60\ndown back\nsleep 4000\nmove 1590 530\nsleep 100\nclick\nsleep 1500\nup back\n' | input &
    sleep 1.2
    c "zoom 0.6 960 540"
    sleep 1.3; c state
    assert_eq "the overlay is up for the click" "$(sget map)" overlay
    local i
    for i in $(seq 1 80); do c state; [ "$(sget visible)" = false ] && break; sleep 0.15; done
    sleep 0.3; c state
    assert_eq "the sheet click commits the location" "$(sget visible)" false
    assert_near "the fly lands centred on the window" "$(sget viewx)" 2564.0 2
    assert_true "the location brings the clicked window wholly on screen" \
        "$(awk -v x="$(eget Gwenview fx)" 'BEGIN{print (x >= 0 && x + 460 <= 1920)}')" = 1
    arrange >/dev/null
    # (d) A hold in the open overworld brings the map back, and the pointer
    # over a real window stays in the canvas instead of handing to it.
    open_1to1
    c "placeby Konsole 900 350 620 420"
    c "placeby Gwenview 4000 300 460 420"
    sleep 0.3
    c "zoom 0.4 960 540"
    sleep 0.6; c state
    assert_eq "the overworld is open" "$(sget visible)" true
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 7000\nup back\n' | input &
    sleep 1.0; c state
    assert_eq "the overworld hold brings the map back" "$(sget map)" overlay
    if nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        input move 250 90
        sleep 0.8
        assert_eq "the overlay keeps the hover out of the real window" \
            "$(pt_state | grep -c 'hover=-')" 1
        input click
        sleep 0.4
        assert_eq "the overlay keeps the press out of the real window" \
            "$(pt_state | grep -c 'grab=-')" 1
    else
        skip "pass-through plugin not answering (85-passthrough)"
    fi
    sleep 5.2; c state
    assert_eq "the release returns to the overworld" "$(sget visible)" true
    assert_eq "the overworld is not quiet" "$(grep -c ' quiet' <<<"$LAST_STATE")" 0
    c cancel
    arrange >/dev/null
    # (e) A sheet click during the overworld hold flies, and the release
    # keeps the overworld open at the flown location.
    open_1to1
    c "placeby Konsole 900 350 620 420"
    c "placeby Gwenview 4000 300 460 420"
    sleep 0.3
    c "zoom 0.4 960 540"
    sleep 0.6
    printf 'move 1590 530\nsleep 60\ndown back\nsleep 4000\nmove 1590 530\nsleep 150\nclick\nsleep 500\nup back\n' | input &
    sleep 1.0; c state
    assert_eq "the overworld hold shows the map again" "$(sget map)" overlay
    local i
    for i in $(seq 1 60); do c state; [ "$(sget zoom)" = "1.0000" ] && break; sleep 0.15; done
    sleep 0.5; c state
    assert_eq "the overworld stays open after the sheet fly" "$(sget visible)" true
    assert_near "the fly lands centred on the window" "$(sget viewx)" 2564.0 2
    assert_near "and vertically" "$(sget viewy)" -336.0 2
    c cancel
    arrange >/dev/null
}
