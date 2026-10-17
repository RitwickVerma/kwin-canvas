# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="reaching for a dock or panel does not pan the canvas: a pointer on its way to the panel pauses over windows, and none of those pauses, nor the arrival, moves the camera"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    local i got=0 seeded=0 c
    for i in $(seq 1 40); do
        c=$(nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "print('PANELCOUNT:' + panels().length)" 2>/dev/null || true)
        case "$c" in *PANELCOUNT:[1-9]*) got=1; break ;; esac
        if [ "$seeded" = 0 ] && [ "$i" -ge 6 ]; then
            nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.loadLookAndFeelDefaultLayout "org.kde.plasma.desktop" >/dev/null 2>&1
            seeded=1
        fi
        sleep 0.5
    done
    if [ "$got" != 1 ]; then skip "no plasmashell panel (make test-panel)"; return; fi
    source tests/lib.sh
    arrange
    # Windows hanging over the screen's edges, so a rest on any of them has
    # a pan to ask for, on the way down to the panel at the bottom.
    open_1to1
    c "placeby KCalc 1500 700 480 420"
    c "placeby Konsole 100 800 620 420"
    sleep 0.4
    c state
    local vx0 vy0; vx0=$(sget viewx); vy0=$(sget viewy)
    # Down the right side and along the bottom to the panel: swept quickly
    # (a pointer in transit never rests) except within reach of the panel,
    # where it pauses over each window long enough to count as a rest
    # (HoverDelay is 900 ms; the camera's fetch waits half of it).
    for pt in "1700 500" "1700 750" "1700 900"; do
        set -- $pt
        input move "$1" "$2"
        sleep 0.05
    done
    for pt in "1700 1000" "1200 1060" "600 1060" "300 1000"; do
        set -- $pt
        input move "$1" "$2"
        sleep 0.9
    done
    c state
    assert_eq "no pause on the way to the panel panned the camera, x" "$(sget viewx)" "$vx0"
    assert_eq "nor y" "$(sget viewy)" "$vy0"
    c cancel
    # The default layout seeded above swapped the fixture wallpaper for
    # Plasma's own and left its panel: put the nest's shape back (see 117).
    if [ "$seeded" = 1 ]; then shell_shape; sleep 2; fi
    arrange
}
