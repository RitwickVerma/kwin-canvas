# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="app popups: with the canvas open at zoom < 1, a window's menu and submenu are drawn where KWin has them, above the windows, take clicks, and close as stock; a menu of a window outside the output opens beside it"
# Probe Menu opens its menu (magenta) and submenu (cyan) as xdg_popups on a
# right press; Probe Under sits where the menu opens, so the menu is drawn
# over it.
PLOG=$STATE/probe.log
logged() { grep -ac "PROBE Probe Menu $1" "$PLOG"; }
presses() { grep -ac "PROBE .* press" "$PLOG"; }
chord() { printf 'key leftctrl down\nkey leftalt down\nkey space\nkey leftalt up\nkey leftctrl up\n' | input; sleep 0.6; }
client() { js 'for (const w of workspace.windowList()) if (w.caption == "'"$1"'") out(Math.round(w.clientGeometry.x) + " " + Math.round(w.clientGeometry.y) + " " + Math.round(w.clientGeometry.width) + " " + Math.round(w.clientGeometry.height))'; }
# popup DEPTH -> "X Y W H" of Probe Menu's popup DEPTH levels down (1 the
# menu, 2 the submenu), its real geometry on the plane
popup() {
    js 'for (const w of workspace.stackingOrder) {
            if (!w.popupWindow) continue;
            let d = 0, p = w;
            while (p && p.popupWindow) { p = p.transientFor; ++d; }
            if (p && p.caption == "Probe Menu" && d == '"$1"') out(Math.round(w.frameGeometry.x) + " " + Math.round(w.frameGeometry.y) + " " + Math.round(w.frameGeometry.width) + " " + Math.round(w.frameGeometry.height));
        }'
}
# npopups -> how many popups of Probe Menu are open
npopups() {
    js 'let n = 0;
        for (const w of workspace.stackingOrder) {
            let p = w;
            while (p && p.popupWindow) p = p.transientFor;
            if (w.popupWindow && p && p.caption == "Probe Menu") ++n;
        }
        out(n)'
}
# scr PX PY -> the screen point showing plane point (PX, PY) in the last state
scr() {
    awk -v px="$1" -v py="$2" -v z="$(sget zoom)" -v vx="$(sget viewx)" -v vy="$(sget viewy)" -v tx="$(tget 0 x)" -v ty="$(tget 0 y)" \
        'BEGIN{printf "%d %d", px * z + (tx - vx) * z + 0.5, py * z + (ty - vy) * z + 0.5}'
}
at_plane() { local x y; read -r x y <<<"$(scr "$1" "$2")"; printf 'move %s %s\nsleep 80\nmove %s %s\nsleep 80\n' $((x - 1)) "$y" "$x" "$y" | input; }
click_plane() { local x y; read -r x y <<<"$(scr "$1" "$2")"; printf 'move %s %s\nsleep 80\nmove %s %s\nsleep 80\nclick %s\n' $((x - 1)) "$y" "$x" "$y" "${3:-left}" | input; sleep 0.8; }
# pixel PX PY -> the colour drawn at plane point (PX, PY), as #RRGGBB
pixel() {
    local x y; read -r x y <<<"$(scr "$1" "$2")"
    shot "$OUT/popups.png" >/dev/null
    magick "$OUT/popups.png" -crop "1x1+$x+$y" -depth 8 txt:- | sed -n 's/.*\(#[0-9A-F]\{6\}\).*/\1/p' | head -1
}
# place CAPTION PX PY: put the window's frame at plane (PX, PY)
place() { c "placeby $1 $(($2 + $(tget 0 x))) $(($3 + $(tget 0 y)))"; sleep 0.5; }

run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    probe Menu; probe Under; sleep 3
    open_1to1; c "snap edges off"; c "snap corners off"; c "snap grid off"
    place Menu 300 200
    place Under 250 560
    c home; c "zoom 0.5 960 540"
    local mx my mw mh; read -r mx my mw mh <<<"$(client "Probe Menu")"

    echo "   a menu"
    local n; n=$(logged "menu opened")
    click_plane $((mx + 60)) $((my + 40)) right
    assert_eq "right press opens the menu" "$(logged "menu opened")" $((n + 1))
    c state
    assert_eq "the canvas draws one app popup" "$(sget popups)" 1
    assert_eq "no popup became an entry" "$(sget entries)" "$(js 'let n = 0; for (const w of workspace.stackingOrder) if (w.normalWindow && !w.popupWindow) ++n; out(n)')"
    local px py pw ph; read -r px py pw ph <<<"$(popup 1)"
    if [ -z "$px" ]; then fail "no popup window for Probe Menu"; return; fi
    assert_eq "drawn at its top-left corner" "$(pixel $((px + 4)) $((py + 4)))" "#FF00FF"
    assert_eq "drawn at its bottom-right corner" "$(pixel $((px + pw - 4)) $((py + ph - 4)))" "#FF00FF"
    assert_true "not drawn beyond its corner" "$(pixel $((px + pw + 12)) $((py + ph + 12)))" != "#FF00FF"
    local ux uy uw uh; read -r ux uy uw uh <<<"$(client "Probe Under")"
    if [ $((px + 4)) -ge "$ux" ] && [ $((py + ph - 4)) -lt $((uy + uh)) ] && [ $((py + ph - 4)) -ge "$uy" ]; then
        ok "the menu overlaps Probe Under"
    else
        fail "the menu at ($px,$py ${pw}x$ph) misses Probe Under at ($ux,$uy ${uw}x$uh)"
    fi
    n=$(logged "triggered One")
    click_plane $((px + pw / 2)) $((py + 25))
    assert_eq "a click on an item reaches the app" "$(logged "triggered One")" $((n + 1))
    assert_eq "the menu closes" "$(npopups)" 0
    c state
    assert_eq "and is no longer drawn" "$(sget popups)" 0
    assert_true "nothing drawn where it was" "$(pixel $((px + 4)) $((py + 4)))" != "#FF00FF"

    echo "   a submenu"
    click_plane $((mx + 60)) $((my + 40)) right
    read -r px py pw ph <<<"$(popup 1)"
    n=$(logged "submenu opened")
    at_plane $((px + pw / 2)) $((py + 85)); sleep 1
    assert_eq "hovering More opens the submenu" "$(logged "submenu opened")" $((n + 1))
    local sx sy sw; read -r sx sy sw _ <<<"$(popup 2)"
    if [ -z "$sx" ]; then fail "no submenu window"; return; fi
    c state
    assert_eq "the canvas draws both" "$(sget popups)" 2
    assert_eq "the submenu is drawn" "$(pixel $((sx + 4)) $((sy + 4)))" "#00FFFF"
    assert_eq "the menu is still drawn" "$(pixel $((px + 4)) $((py + 4)))" "#FF00FF"
    n=$(logged "triggered Three")
    click_plane $((sx + sw / 2)) $((sy + 25))
    assert_eq "a click on a submenu item reaches the app" "$(logged "triggered Three")" $((n + 1))
    assert_eq "both close" "$(npopups)" 0

    echo "   dismissal"
    click_plane $((mx + 60)) $((my + 40)) right
    assert_eq "the menu is open" "$(npopups)" 1
    n=$(presses)
    local zoom; zoom=$(sget zoom)
    # The ground, far from every window.
    printf 'move 150 1000\nsleep 80\nclick\n' | input; sleep 0.8; c state
    assert_eq "a click on the ground closes it" "$(npopups)" 0
    assert_eq "the click reached no window" "$(presses)" "$n"
    assert_eq "the canvas stays open" "$(sget visible)" true
    assert_eq "and its camera where it was" "$(sget zoom)" "$zoom"
    click_plane $((mx + 60)) $((my + 40)) right
    assert_eq "the menu opens again" "$(npopups)" 1
    c "locate In"
    local x y; read -r x y <<<"$(grep -a "kwin-canvas locate In = " "$LOG" | tail -1 | sed 's/.*= //')"
    printf 'move %s %s\nsleep 80\nclick\n' "$x" "$y" | input; sleep 0.8; c state
    assert_eq "a click on the toolbar closes it" "$(npopups)" 0
    assert_eq "and does nothing else" "$(sget zoom)" "$zoom"

    echo "   a window outside the output"
    # At zoom 0.3 the output shows plane x from about -2200 to 4200: KWin
    # would keep the menu inside the output's own rectangle, x < 1920.
    place Menu 2400 1000
    c home; c "zoom 0.3 960 540"
    read -r mx my mw _ <<<"$(client "Probe Menu")"
    click_plane $((mx + 60)) $((my + 40)) right
    read -r px py pw ph <<<"$(popup 1)"
    if [ -z "$px" ]; then fail "no popup window for Probe Menu outside the output"; return; fi
    assert_true "the menu opens beside its window" "$px" -ge "$mx"
    assert_true "within its window's width" "$px" -lt $((mx + mw))
    assert_eq "drawn there" "$(pixel $((px + pw / 2)) $((py + 5)))" "#FF00FF"
    n=$(logged "triggered Two")
    click_plane $((px + pw / 2)) $((py + 55))
    assert_eq "its item takes the click" "$(logged "triggered Two")" $((n + 1))
    assert_eq "and it closes" "$(npopups)" 0

    echo "   leaving"
    click_plane $((mx + 60)) $((my + 40)) right
    chord; c state
    assert_eq "the chord exits with a menu open" "$(sget visible)" false
    assert_eq "no app popup drawn while closed" "$(sget popups)" 0
    printf 'key esc\n' | input; sleep 0.5
    assert_eq "no menu left" "$(npopups)" 0
    assert_eq "no script errors" "$(grep -ac 'main.qml.*Error' "$LOG")" 0
}
