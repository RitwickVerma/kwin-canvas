# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a pointer resting on a floated window's picture never flies the camera: the hover reads the picture the eye sees, not the window's coordinates far away, and wants no fetch of a window that already rides on screen"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    source tests/lib.sh
    arrange >/dev/null
    setcfg HoverDelay 400
    open_1to1
    c state >/dev/null
    local k; k=$(eget KCalc index)
    c "pin $k"
    sleep 0.3
    # Pan the world far enough that KCalc's coordinates are well off screen:
    # its picture rides the left edge.
    c "panpx -900 0" >/dev/null
    sleep 1
    c state >/dev/null
    local fx; fx=$(grep -a "KCalc canvas=" <<<"$LAST_STATE" | grep -oE 'float=\([+-]?[0-9]+,[+-]?[0-9]+\)')
    assert_true "the picture floats at the edge" "$(grep -c 'float=' <<<"$fx")" -ge 1
    local vx0 vy0; vx0=$(sget viewx); vy0=$(sget viewy)
    # Rest on the picture (the left edge band), long enough for a fetch.
    input move 250 250
    sleep 0.3
    input move 255 255
    sleep 2.5
    c state >/dev/null
    assert_eq "resting on a floated picture leaves the camera, x" "$(sget viewx)" "$vx0"
    assert_eq "and y" "$(sget viewy)" "$vy0"
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key HoverDelay --delete >/dev/null
    c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
