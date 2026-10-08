# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the decor applet's channel: the plugin's state names the focused window, and its windowAction minimizes, floats and closes it for real"

run_scenario() {
    source tests/lib.sh

    pt_state() { nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state; }
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "the pass-through plugin is not loaded"
        return
    fi

    arrange >/dev/null
    sleep 0.5

    # The arrange's activate chain ends on KCalc, so the plugin's state
    # should name it as the focused window.
    c state
    assert_eq "the state names the focused window" "$(pt_state | grep -c ' win=.*KCalc')" 1
    assert_eq "and the canvas is closed" "$(sget visible)" false

    # Minimize hands the focus to the next window - the minimized one is
    # gone from the active slot - and the plane's next open filters it
    # out of the entries entirely.
    nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.windowAction minimize
    for i in $(seq 1 15); do [ "$(pt_state | grep -c ' win=.*KCalc')" = 0 ] && break; sleep 0.4; done
    assert_eq "minimize hands the focus away" "$(pt_state | grep -c ' win=.*KCalc')" 0
    open_1to1
    sleep 0.6
    c state
    assert_eq "and the minimized window leaves the plane" "$(sget entries)" 4
    c cancel

    # The float toggles the on-all-desktops pin, which the state's win=
    # token reports as its last field.
    nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.windowAction float
    sleep 0.4
    assert_eq "the float lifts the window" "$(pt_state | grep -c ' win=.*|1$')" 1
    nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.windowAction float
    sleep 0.4
    assert_eq "and the same action sets it down" "$(pt_state | grep -c ' win=.*|0$')" 1

    # The close really closes: the process-side call reaches the window.
    nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.windowAction close
    sleep 0.6
    open_1to1
    sleep 0.6
    c state
    assert_eq "the close kills the window for real" "$(sget entries)" 3
    c cancel

    # Leave the fixtures as found: the activation un-minimizes KCalc, and
    # the closed fixture is launched again so the batch's next scenario
    # sees all five.
    c "activate KCalc"
    run gwenview "$FIXTURES/wallpaper.png" >/dev/null
    sleep 2
    arrange >/dev/null
}
