# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the grasp's map: holding MB4 zooms the world out into the map, a click on a window flies there and the release commits the location, and MB5 held in the overworld tours the clusters"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    # Hold MB4, zoom the world out, click a window on the plane, release:
    # the location opens centred on it. The clicked window must be the
    # current activity's - the quiet grasp shows only its own activity's
    # windows, the world-map's step to a window across activities is the
    # commit's business. Gwenview sits at (1400,120); at zoom 0.3 from the
    # anchor view (-2240,-1260) its body is the screen rect
    # (1092..1230, 414..540) - clear of KWrite (ends x 1074) and of the
    # cluster chip at (942,541).
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 3000\nmove 1161 477\nsleep 100\nclick\nsleep 500\nup back\n' | input &
    sleep 1.2
    c "zoom 0.3 960 540"
    sleep 3.4; c state
    assert_eq "the grasp's map click flies and the release commits" "$(sget visible)" false
    assert_true "the location brings the clicked window wholly on screen" \
        "$(awk -v x="$(eget Gwenview fx)" 'BEGIN{print (x >= 0 && x + 460 <= 1920)}')" = 1
    arrange >/dev/null
    # In the overworld, MB4 held and MB5 tapped tours the clusters.
    open_1to1
    c "placeby KCalc 300 300 480 420"
    c "placeby Konsole 900 350 620 420"
    c "placeby Gwenview 3000 300 460 420"
    c "placeby Dolphin 3600 350 700 360"
    sleep 0.3
    c "zoom 0.4 960 540"
    sleep 0.4; c state
    local vx; vx=$(sget viewx)
    # The pointer is put on bare ground first: arrange parks it at the screen's
    # corner, which a nest with a panel (make test-panel) covers with the dock,
    # and the dock owns the press, so no hold ever started there.
    printf 'move 1700 900\nsleep 60\ndown back\nsleep 400\n' | input &
    sleep 0.5
    printf 'down forward\nsleep 60\nup forward\n' | input
    sleep 0.6; c state
    assert_true "MB5 held in the overworld travels between clusters" \
        "$(awk -v a="$vx" -v b="$(sget viewx)" 'BEGIN{print (b != a)}')" = 1
    printf 'up back\n' | input
    sleep 0.4
    c cancel
    arrange >/dev/null
    # The switcher: the world fitted as a map, the chord's repeat steps the
    # selection, entering lands on the chosen window. The virtual seat of
    # the test nest routes plain keys to the focused fixture window, never
    # to the canvas's scene, so the enter rides the debug channel here -
    # the chord's repeat and the Enter key are the live session's path.
    c "switch"
    sleep 0.5; c state
    assert_eq "the switcher opens the map quietly" "$(sget visible)" true
    c "switch"
    sleep 0.5; c state
    assert_eq "the chord's repeat steps the selection" \
        "$(grep -c '^  \[[0-9][0-9]*\] \*' <<<"$LAST_STATE")" 1
    c "enter"
    sleep 0.8; c state
    assert_eq "entering steps into the chosen window" "$(sget visible)" false
    arrange >/dev/null
}
