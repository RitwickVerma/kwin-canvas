# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the grasp's map: holding MB4 shows the whole plane translucent, a click on a sheet flies there and the release commits the location, and MB5 held in the overworld tours the clusters"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    # Spread the desk so the map has somewhere to fly.
    open_1to1
    c "placeby Gwenview 4000 300 460 420"
    c commit
    sleep 0.3
    # Hold MB4, click the far window's sheet on the map, release: the
    # location opens centred on it.
    { printf 'move 1700 900\nsleep 60\ndown back\nsleep 1200\n'; \
      printf 'move 1780 520\nsleep 100\nclick\n'; \
      printf 'sleep 500\nup back\n'; } | input
    sleep 1.5; c state
    assert_eq "the grasp's map click flies and the release commits" "$(sget visible)" false
    assert_true "the location is centred on the clicked window" \
        "$(awk -v x="$(sget viewx)" 'BEGIN{print (x > 3000 && x < 3500)}')" = 1
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
    printf 'down back\nsleep 400\n' | input &
    sleep 0.5
    printf 'down forward\nsleep 60\nup forward\n' | input
    sleep 0.6; c state
    assert_true "MB5 held in the overworld travels between clusters" \
        "$(awk -v a="$vx" -v b="$(sget viewx)" 'BEGIN{print (b != a)}')" = 1
    printf 'up back\n' | input
    sleep 0.4
    c cancel
    arrange >/dev/null
}
