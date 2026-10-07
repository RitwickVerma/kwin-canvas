# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the tour's smart placement pulls the neighbours in: the focused window stays completely inside while the windows around it come at least partially into view"

run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    open_1to1
    # The far pair sits side by side: the focused window (wallpaper.png, the
    # one the arrange activated after Dolphin) with the neighbour just off
    # its right edge. The old least-pan would stop with the focused window
    # at the screen's edge and the neighbour just outside; the smart pan
    # pulls over to the midpoint that includes it.
    c "placeby wallpaper.png 4000 300 460 420"
    c "placeby Dolphin 4500 300 700 360"
    c commit
    sleep 0.3
    c state
    assert_eq "the far pair makes two clusters" "$(sget clusters)" 2
    open_1to1
    sleep 0.5
    c state
    assert_eq "the canvas is open at the first cluster" "$(sget visible)" true
    { printf 'move 1700 900\nsleep 100\nclick forward\nsleep 700\n'; } | input
    for i in $(seq 1 12); do c state; [ "$(sget viewx)" != "0.0" ] && break; sleep 0.4; done
    c state
    assert_near "the focused window stays completely inside" "$(sget viewx)" 3278 60
    if awk -v x="$(sget viewx)" 'BEGIN{exit !(x + 1920 > 4500)}'; then
        ok "the neighbour is pulled at least partially in"
    else
        fail "the neighbour is pulled at least partially in"
    fi
    c cancel
    arrange >/dev/null
}
