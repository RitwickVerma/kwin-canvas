# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a panel applet's dropdown opens and never flies the desktop"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # The script's print() output comes back through the nq reply; the poll
    # reads it. If the nest has no panel yet, seed Plasma's default layout
    # (which carries one) and keep polling.
    local i got=0 seeded=0
    for i in $(seq 1 40); do
        local c
        c=$(nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "print('PANELCOUNT:' + panels().length)" 2>/dev/null || true)
        case "$c" in
            *PANELCOUNT:[1-9]*) got=1; break ;;
        esac
        if [ "$seeded" = 0 ] && [ "$i" -ge 6 ]; then
            nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.loadLookAndFeelDefaultLayout "org.kde.plasma.desktop" >/dev/null 2>&1
            seeded=1
        fi
        sleep 0.5
    done
    if [ "$got" != 1 ]; then
        skip "no plasmashell panel (make test-panel)"; return
    fi
    c state
    local vx0 vy0 vis0
    vx0=$(sget viewx); vy0=$(sget viewy); vis0=$(sget visible)
    shot "$OUT/panel.png" >/dev/null
    local bx
    bx=$(clock_box "$OUT/panel.png")
    if [ -z "$bx" ] || [ "$bx" = "0x0+0+0" ]; then skip "no panel clock (make test-panel)"; return; fi
    local cw ch cx cy px py strip bbox
    strip=$(cut -d' ' -f1 <<<"$bx"); bbox=$(cut -d' ' -f2- <<<"$bx")
    cw=$(cut -dx -f1 <<<"$bbox"); ch=$(cut -dx -f2 <<<"$bbox" | cut -d+ -f1)
    cx=$(cut -d+ -f2 <<<"$bbox"); cy=$(cut -d+ -f3 <<<"$bbox")
    px=$((cx + cw / 2))
    if [ "$strip" = top ]; then py=$((cy + ch / 2)); else py=$((1048 + cy + ch / 2)); fi
    echo "# the clock ($strip panel) at $px,$py"
    # The panel's dropdown: a right-click opens the context menu - a plasma
    # popup, the same class an applet's dropdown is.
    magick "$OUT/panel.png" -crop 1920x960+0+60 +repage "$OUT/pop-before.png" 2>/dev/null
    input move "$px" "$py"
    sleep 0.5
    printf 'click right\n' | input
    sleep 1.0
    shot "$OUT/panel2.png" >/dev/null
    magick "$OUT/panel2.png" -crop 1920x960+0+60 +repage "$OUT/pop-after.png" 2>/dev/null
    local pop
    pop=$( { magick compare -metric RMSE "$OUT/pop-before.png" "$OUT/pop-after.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p' )
    if awk -v m="${pop:-0}" 'BEGIN{exit !(m > 0.01)}'; then
        ok "the dropdown opened over the desk (rmse $pop)"
    else
        # plasmashell's popups do not always render in the virtual nest; the
        # guard below is the regression either way.
        skip "the panel's popup did not show in the nest (rmse $pop)"
    fi
    # The camera did not move, and the canvas did not open.
    c state
    assert_eq "the dropdown left the camera's x alone" "$(sget viewx)" "$vx0"
    assert_eq "and its y" "$(sget viewy)" "$vy0"
    assert_eq "and the canvas stayed closed" "$(sget visible)" "$vis0"
    # Close the popup by clicking the desk, and leave the fixtures arranged.
    input move 960 500
    input click
    sleep 0.4
    # The default layout seeded above swapped the fixture wallpaper for
    # Plasma's own and left its panel: put the nest's shape back (see 117).
    if [ "$seeded" = 1 ]; then shell_shape; sleep 2; fi
    arrange >/dev/null
}
