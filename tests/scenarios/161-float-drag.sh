# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a hand on a floated window that rides the screen's edge takes the picture where the eye sees it: the picture follows the hand from its own spot, the camera does not move, and on release it settles inside the screen"
run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # The canvas takes the pointer, not the plugin, so the drag moves the
    # thumbnail (the plugin's own scenario is 85).
    setcfg Passthrough false
    arrange >/dev/null
    open_1to1
    c state >/dev/null
    local k; k=$(eget KCalc index)
    c "pin $k"
    # Push the camera far to the left of the window: its coordinates are now
    # 3000 px right of the screen and its picture rides the right edge.
    c "panpx 3000 0" >/dev/null
    sleep 1.2
    local px py pw ph
    read -r px py pw ph <<<"$(float_picture)"
    assert_eq "pushed out, the picture rides the right edge" "$px" "1432.0"
    # Take the picture 168 px in from its left edge and pull it 150 px left.
    # The window is held by the hand, so it must come with the hand: the
    # hand-to-picture offset stays what it was at the grab.
    { printf 'move 1600 300\nsleep 50\ndown\nsleep 60\n'
      local i; for i in $(seq 1 15); do printf 'rel -10 0\nsleep 25\n'; done
      printf 'sleep 1500\nup\nsleep 200\n'; } > "$OUT/161.in"
    input < "$OUT/161.in" &
    sleep 1.0
    c state >/dev/null
    local vx; vx=$(sget viewx)
    read -r px py pw ph <<<"$(float_picture)"
    assert_eq "the camera did not move under the hand" "$vx" "-3000.0"
    assert_near "the picture follows the hand from where it was grabbed" "$px" 1282 40
    wait
    sleep 1.5
    assert_eq "let go, the picture settles inside the screen" "$(float_inside)" yes
    rm -f "$OUT/161.in"
    c state >/dev/null; k=$(eget KCalc index); c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
    setcfg Passthrough true
}
