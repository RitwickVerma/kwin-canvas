# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a floated window on the second output stays on it: its picture is held to the output it is on and not to the pointer's, rides that output's edge when the camera is elsewhere, and the real window lands there on exit"
run_scenario() {
    c state
    if [ "$(sget screens)" != 2 ]; then skip "needs two outputs (make test-two-outputs ARGS=166)"; return; fi
    local x1 y1 w1 h1
    read -r x1 y1 w1 h1 <<<"$(screenrect 1)"
    arrange >/dev/null
    # KCalc onto the second output, the pointer left on the first.
    open_1to1
    c "placeby KCalc $((x1 + 180)) 120" >/dev/null
    sleep 0.5
    c commit >/dev/null
    sleep 0.8
    assert_eq "KCalc is on the second output" "$(float_frame)" "$((x1 + 180)) 120 480 420"
    open_1to1
    c state >/dev/null
    local k; k=$(eget KCalc index)
    c "pin $k"
    sleep 0.6
    local px py pw ph
    read -r px py pw ph <<<"$(float_picture)"
    assert_eq "floated there, the picture stays where the window is" "$px" "$((x1 + 180)).0"
    # The camera 3000 px to the left of it, so its coordinates are right of
    # every output: the picture rides the right edge of the second output.
    c "panpx 3000 0" >/dev/null
    sleep 1.3
    read -r px py pw ph <<<"$(float_picture)"
    assert_eq "pushed off the right, it rides the second output's right edge" "$px" "$((x1 + w1 - 480 - 8)).0"
    c enter >/dev/null
    sleep 1.8
    assert_eq "and the real window lands there" "$(float_frame)" "$((x1 + w1 - 480 - 8)) 120 480 420"
    c open >/dev/null; c state >/dev/null; k=$(eget KCalc index); c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
