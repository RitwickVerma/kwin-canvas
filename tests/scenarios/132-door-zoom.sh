# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the wheel is the door: with the canvas closed, a wheel over the bare ground zooms the world out of the location, and zooming back in re-enters it at 1:1"

run_scenario() {
    source tests/lib.sh
    if ! have_input; then
        skip "fakeinput not built (make tools)"
        return
    fi
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "the pass-through plugin is not loaded (make plugin)"
        return
    fi
    arrange >/dev/null

    # The closed location: the wheel out over the bare ground (1700,1000)
    # crosses the seam and keeps zooming into the overworld. The wheel and
    # the move ride the same device, so the pointer is where the wheel is.
    { printf 'move 1700 1000\nsleep 300\nwheel -1\n'; } | input
    sleep 0.8
    c state
    assert_eq "the wheel out opens the canvas" "$(sget visible)" true
    if awk -v z="$(sget zoom)" 'BEGIN { exit !(z + 0 < 1) }'; then
        ok "and zooms out of the location"
    else
        fail "and zooms out of the location"
    fi

    # The zoom back in re-enters the location: the wheel in at 1:1 commits
    # and the canvas closes at the seam.
    { printf 'wheel 1\nsleep 300\nwheel 1\n'; } | input
    sleep 0.8
    c state
    assert_eq "the wheel in re-enters the location" "$(sget visible)" false

    # The door never steals the window's wheel: the pointer over KCalc and
    # the wheel goes to KCalc's own scroll, the canvas stays closed.
    { printf 'move 340 330\nsleep 300\nwheel -1\n'; } | input
    sleep 0.6
    c state
    assert_eq "a window keeps its wheel" "$(sget visible)" false

    # And the knob turns the whole thing off.
    setcfg WheelDoor false
    { printf 'move 1700 1000\nsleep 300\nwheel -1\n'; } | input
    sleep 0.6
    c state
    assert_eq "the knob closes the door" "$(sget visible)" false
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key WheelDoor --delete >/dev/null 2>&1

    arrange >/dev/null
}
