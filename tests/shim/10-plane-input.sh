# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="plane input: with the canvas open at zoom < 1, clicks and keys reach the windows where the canvas draws them; title bars, frames and the toolbar stay the canvas's; the chord and the hot corner exit; closing clears the transform"
# Two probe windows log what reaches them: Alpha inside the output, Bravo at
# plane (2400,1400), outside it.
PLOG=$STATE/probe.log
lastp() { grep -a "PROBE .* $1" "$PLOG" | tail -1 | sed 's/.*PROBE //'; }
presses() { grep -ac "PROBE .* press" "$PLOG"; }
shimlog() { grep -a "kwin-canvas-preload: transform" "$LOG" | tail -1 | sed 's/.*kwin-canvas-preload: //'; }
cursor() { js 'out(Math.round(workspace.cursorPos.x) + " " + Math.round(workspace.cursorPos.y))'; }
active() { sed -n 's/.* active="\(.*\)"$/\1/p' <<<"$(head -1 <<<"$LAST_STATE")"; }
chord() { printf 'key leftctrl down\nkey leftalt down\nkey space\nkey leftalt up\nkey leftctrl up\n' | input; sleep 0.6; }
# client CAPTION -> "X Y" of the window's client area on the plane (its real geometry)
client() { js 'for (const w of workspace.windowList()) if (w.caption == "'"$1"'") out(Math.round(w.clientGeometry.x) + " " + Math.round(w.clientGeometry.y))'; }
frame()  { js 'for (const w of workspace.windowList()) if (w.caption == "'"$1"'") out(Math.round(w.frameGeometry.x) + " " + Math.round(w.frameGeometry.y))'; }
# scr PX PY -> the screen point that shows plane point (PX, PY) at the camera
# in the last state: screen = plane * zoom + (target(current) - view) * zoom.
scr() {
    awk -v px="$1" -v py="$2" -v z="$(sget zoom)" -v vx="$(sget viewx)" -v vy="$(sget viewy)" -v tx="$(tget 0 x)" -v ty="$(tget 0 y)" \
        'BEGIN{printf "%d %d", px * z + (tx - vx) * z + 0.5, py * z + (ty - vy) * z + 0.5}'
}
# click_plane PX PY [then...]: click at the screen point showing that plane point
click_plane() {
    local x y; read -r x y <<<"$(scr "$1" "$2")"; shift 2
    { printf 'move %s %s\nsleep 50\nclick\n' "$x" "$y"; for k in "$@"; do printf 'sleep 50\nkey %s\n' "$k"; done; } | input
    sleep 0.5; c state
}
# drawn_at X Y -> rmse of a 32x32 crop at screen (X, Y) between screenshots
# with and without the pointer, taken while fake input holds the pointer
# there (KWin hides the cursor once the fake pointer device is gone).
drawn_at() {
    (printf 'move %s %s\nsleep 3000\n' "$1" "$2" | input) &
    local pid=$!
    sleep 1
    local b; b=$(nestbus) || return 1
    local e=(env -u DISPLAY DBUS_SESSION_BUS_ADDRESS="$b" WAYLAND_DISPLAY="$SOCKET" QT_QPA_PLATFORM=wayland $(nest_env client))
    "${e[@]}" spectacle -b -n -f -p -o "$OUT/pointer-with.png" >/dev/null 2>&1
    "${e[@]}" spectacle -b -n -f -o "$OUT/pointer-without.png" >/dev/null 2>&1
    wait "$pid"
    magick "$OUT/pointer-with.png" -crop "32x32+$1+$2" +repage "$OUT/pointer-a.png"
    magick "$OUT/pointer-without.png" -crop "32x32+$1+$2" +repage "$OUT/pointer-b.png"
    { magick compare -metric RMSE "$OUT/pointer-a.png" "$OUT/pointer-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}
# The camera every check below starts from: s = 0.5, o = (480, 270).
zoomed() { c home; c "zoom 0.5 960 540"; }

run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    assert_eq "shim attached to the effect" "$(grep -ac 'kwin-canvas-preload: attached to the kwin-canvas effect' "$LOG")" 1
    : > "$PLOG"
    probe Alpha; probe Bravo; sleep 3
    open_1to1
    c "placeby Alpha 200 300"; c "placeby Bravo 2400 1400"
    c "snap edges off"; c "snap corners off"; c "snap grid off"
    sleep 0.6; c commit
    local kcalc; kcalc=$(eget KCalc fx)

    echo "   open at zoom 0.5"
    open_1to1; c "snap edges off"; c "snap corners off"; zoomed
    assert_eq "state says plane" "$(head -1 <<<"$LAST_STATE" | grep -c ' plane ')" 1
    assert_eq "shim reads the effect's transform" "$(shimlog)" "transform s=0.5 o=(480,270)"
    local ax ay bx by
    read -r ax ay <<<"$(client "Probe Alpha")"
    read -r bx by <<<"$(client "Probe Bravo")"
    click_plane $((ax + 200)) $((ay + 122)) a
    assert_eq "click at Alpha's drawn position reaches it" "$(lastp press)" "Probe Alpha press 200.0 122.0"
    assert_eq "focus follows" "$(active)" "Probe Alpha"
    assert_eq "keys reach it" "$(lastp key)" "Probe Alpha key a 65"
    assert_eq "cursor is the plane point" "$(cursor)" "$((ax + 200)) $((ay + 122))"
    # Over the ground at screen (300, 900), plane (-360, 1260).
    assert_eq "the cursor is drawn at the screen point" "$(awk -v m="$(drawn_at 300 900)" 'BEGIN{print (m > 0.02)}')" 1
    click_plane $((bx + 150)) $((by + 100)) b
    assert_eq "click at Bravo, outside the output, reaches it" "$(lastp press)" "Probe Bravo press 150.0 100.0"
    assert_eq "focus follows to Bravo" "$(active)" "Probe Bravo"
    assert_eq "keys reach Bravo" "$(lastp key)" "Probe Bravo key b 66"
    assert_eq "activating Bravo panned nothing" "$(eget KCalc fx)" "$kcalc"
    assert_eq "still open" "$(sget visible)" true

    echo "   the canvas's own surfaces"
    # Alpha's title bar, 14 plane px above its client area: a drag of
    # (100, 50) screen px is (200, 100) on the plane, and the window is
    # written there at once.
    local n; n=$(presses)
    local fx fy; read -r fx fy <<<"$(frame "Probe Alpha")"
    local x y; read -r x y <<<"$(scr $((ax + 200)) $((ay - 14)))"
    printf 'drag %s %s %s %s 20 10\n' "$x" "$y" $((x + 100)) $((y + 50)) | input
    sleep 0.8; c state
    assert_eq "title-bar drag reached no window" "$(presses)" "$n"
    assert_near "title-bar drag moves Alpha on the canvas x" "$(eget "Probe Alpha" x)" $((fx + 200)) 1
    assert_near "title-bar drag moves Alpha on the canvas y" "$(eget "Probe Alpha" y)" $((fy + 100)) 1
    assert_eq "Alpha written where the canvas draws it" "$(frame "Probe Alpha")" "$((fx + 200)) $((fy + 100))"
    read -r ax ay <<<"$(client "Probe Alpha")"
    # Clear of the resize grips, which are the canvas's and 6 screen px wide.
    click_plane $((ax + 40)) $((ay + 20))
    assert_eq "click reaches Alpha where it was dragged" "$(lastp press)" "Probe Alpha press 40.0 20.0"
    # The current activity's tag sits just above its frame's top-left corner,
    # plane (0, 0) with the target at the origin.
    n=$(presses)
    read -r x y <<<"$(scr 0 0)"; x=$((x + 12)); y=$((y - 8))
    printf 'drag %s %s %s %s 20 10\n' "$x" "$y" $((x + 50)) $((y + 25)) | input
    sleep 0.8; c state
    assert_near "tag drag moves the frames x" "$(tget 0 x)" 100 1
    assert_near "tag drag moves the frames y" "$(tget 0 y)" 50 1
    assert_eq "tag drag reached no window" "$(presses)" "$n"
    assert_eq "the transform follows the target" "$(shimlog)" "transform s=0.5 o=(530,295)"
    click_plane $((ax + 30)) $((ay + 20))
    assert_eq "click reaches Alpha after the frames moved" "$(lastp press)" "Probe Alpha press 30.0 20.0"
    n=$(presses)
    c "locate In"
    read -r x y <<<"$(grep -a "kwin-canvas locate In = " "$LOG" | tail -1 | sed 's/.*= //')"
    printf 'move %s %s\nsleep 50\nclick\n' "$x" "$y" | input
    sleep 0.5; c state
    assert_near "toolbar zoom-in works" "$(sget zoom)" 0.575 0.001
    assert_eq "toolbar click reached no window" "$(presses)" "$n"

    echo "   leaving"
    chord; c state
    assert_eq "the chord exits" "$(sget visible)" false
    assert_eq "closing clears the transform" "$(shimlog)" "transform cleared"
    input move 700 400; sleep 0.2
    assert_eq "cursor is the screen point" "$(cursor)" "700 400"
    read -r ax ay <<<"$(client "Probe Alpha")"
    if [ "$ax" -ge 0 ] && [ "$ay" -ge 0 ] && [ "$ax" -lt 1900 ] && [ "$ay" -lt 1060 ]; then
        printf 'move %s %s\nsleep 50\nclick\n' $((ax + 5)) $((ay + 5)) | input; sleep 0.4
        assert_eq "click at 1:1 reaches Alpha stock" "$(lastp press)" "Probe Alpha press 5.0 5.0"
    else
        fail "Alpha off screen after the chord at client ($ax, $ay)"
    fi

    # The hot corner (top-left in the nest) fires at the screen corner, where
    # the plane point is (-960, -540).
    open_1to1; zoomed
    input move 0 0
    for _ in 1 2 3 4 5 6; do input rel -20 -20; sleep 0.08; done
    sleep 0.5; c state
    assert_eq "hot corner exits under the transform" "$(sget visible)" false
    assert_eq "and clears it" "$(shimlog)" "transform cleared"

    echo "   twenty open/close cycles"
    kcalc=$(eget KCalc fx)
    local i set; set=$(grep -ac 'kwin-canvas-preload: transform s=0.5 o=(480,270)' "$LOG")
    for i in $(seq 1 20); do
        chord; zoomed; c home; chord
    done
    c state
    assert_eq "closed after the cycles" "$(sget visible)" false
    assert_eq "transform cleared after the cycles" "$(shimlog)" "transform cleared"
    assert_eq "every cycle set it" "$(grep -ac 'kwin-canvas-preload: transform s=0.5 o=(480,270)' "$LOG")" $((set + 20))
    assert_eq "nothing moved" "$(eget KCalc fx)" "$kcalc"
    input move 640 360; sleep 0.2
    assert_eq "cursor stock" "$(cursor)" "640 360"
    read -r ax ay <<<"$(client "Probe Alpha")"
    printf 'move %s %s\nsleep 50\nclick\nsleep 50\nkey c\n' $((ax + 7)) $((ay + 7)) | input; sleep 0.4
    assert_eq "clicks stock" "$(lastp press)" "Probe Alpha press 7.0 7.0"
    assert_eq "keys stock" "$(lastp key)" "Probe Alpha key c 67"
    assert_eq "no script errors" "$(grep -ac 'main.qml.*Error' "$LOG")" 0

    echo "   dead man"
    # Unloading the effect while its transform is live leaves KWin stock
    # within the shim's one-second poll, with no input to trigger it.
    open_1to1; zoomed
    nq org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect kwin-canvas >/dev/null
    sleep 1.5
    assert_eq "unloading the open effect clears the transform" "$(shimlog)" "transform cleared"
    input move 640 360; sleep 0.2
    assert_eq "cursor stock without the effect" "$(cursor)" "640 360"
    nq org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect kwin-canvas >/dev/null
    sleep 1.5
    assert_eq "the shim attaches to the reloaded effect" "$(grep -ac 'kwin-canvas-preload: attached to the kwin-canvas effect' "$LOG")" 2
}
