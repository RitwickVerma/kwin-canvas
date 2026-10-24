# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="in the open overview a window no monitor shows gets a chip at the screen's edge on the side it lies, and a click on the chip flies the camera to it; windows on the screen and floated windows get none"

away() { grep -o ' away=[0-9]*' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2; }

run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    setcfg SmoothZoom false
    open_1to1
    c "placeby Gwenview 5000 400 460 420"
    c commit >/dev/null; sleep 1.0
    open_1to1; sleep 0.6; c state
    assert_eq "one window is out of view" "$(away)" 1
    shot "$OUT/away.png" >/dev/null
    # The chip sits at the right edge, level with the window's centre (y 610 on a 1080 screen).
    local cy; cy=$(awk -v y="$(eget Gwenview y)" -v v="$(sget viewy)" 'BEGIN{printf "%d", y + 210 - v}')
    local inset=26
    printf 'move %d %d\nsleep 400\nclick left\nsleep 1500\n' "$((1920 - inset))" "$cy" | input
    c state
    assert_true "a click on the chip flies to the window (view x $(sget viewx))" "$(sget viewx | cut -d. -f1)" -gt 3000
    local sx; sx=$(awk -v x="$(eget Gwenview x)" -v v="$(sget viewx)" 'BEGIN{printf "%d", x - v}')
    assert_true "Gwenview is on the screen now (x $sx)" "$sx" -ge 0
    assert_true "and wholly" "$((sx + 460))" -le 1920
    assert_eq "and the four left behind have their chips" "$(away)" 4
    c cancel >/dev/null; sleep 0.8

    # A floated far window gets no chip.
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Gwenview") >= 0) x.onAllDesktops = true; });' 0.5
    open_1to1; sleep 0.4; c state
    assert_eq "a floated window gets no chip" "$(away)" 0
    c cancel >/dev/null; sleep 0.6
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Gwenview") >= 0) x.onAllDesktops = false; });' 0.5
    arrange >/dev/null
}
