# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the map widget: the plugin's Map reads the effect's plane, says changed only once someone reads, and its go and focus slide the desk; the widget on the desktop draws the map and a click on it moves the desk"

run_scenario() {
    source tests/lib.sh

    mq() { nq org.kde.KWin /KWinCanvas/Map org.kde.kwin.canvas.Map."$@"; }
    # pj EXPR: one value out of a map reading on stdin (the plane is the dict p).
    pj() { python3 -I -c 'import json, sys; p = json.loads(sys.stdin.read() or "null"); print(eval(sys.argv[1]))' "$1" 2>/dev/null; }
    kcalc='[w for w in p["windows"] if "KCalc" in w["caption"]][0]'
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "the pass-through plugin is not loaded"
        return
    fi

    arrange >/dev/null
    sleep 0.5

    # Nobody has read the map yet, so it watches nothing: a window's move
    # says nothing on the bus.
    DBUS_SESSION_BUS_ADDRESS=$(nestbus) dbus-monitor "type='signal',interface='org.kde.kwin.canvas.Map'" > "$OUT/map-signals.txt" 2>&1 &
    local mon=$!
    sleep 0.5
    kwinjs "$FIND_KWRITE if (w) { const g = w.frameGeometry; w.frameGeometry = { x: g.x + 40, y: g.y, width: g.width, height: g.height }; }"
    assert_eq "before any read, a move says nothing" "$(grep -c 'member=changed' "$OUT/map-signals.txt")" 0

    # Closed, the map is the desk at rest: the windows where the canvas
    # would put them, the camera on the view.
    c state
    local vx vy
    vx=$(printf '%.0f' "$(sget viewx)")
    vy=$(printf '%.0f' "$(sget viewy)")
    local closed
    closed=$(mq read)
    assert_eq "the map reads closed" "$(pj 'p["open"]' <<<"$closed")" False
    assert_eq "the camera is the view at 1:1" "$(pj 'p["camera"][0]' <<<"$closed")" "[$vx, $vy, $WIDTH, $HEIGHT]"
    assert_eq "one frame is the current activity's" "$(pj 'sum(f[5] for f in p["frames"])' <<<"$closed")" 1
    open_1to1
    c state
    assert_eq "every window the canvas draws is on the map" "$(pj 'len(p["windows"])' <<<"$closed")" "$(sget entries)"
    assert_near "KCalc sits where the canvas puts it (x)" "$(pj "$kcalc[\"x\"]" <<<"$closed")" "$(eget KCalc x)" 1
    assert_near "and (y)" "$(pj "$kcalc[\"y\"]" <<<"$closed")" "$(eget KCalc y)" 1
    assert_eq "open, the map reads the live canvas" "$(pj 'p["open"]' <<<"$(mq read)")" True
    c cancel
    sleep 0.3

    # Read once, the map watches: the next move is a signal.
    kwinjs "$FIND_KWRITE if (w) { const g = w.frameGeometry; w.frameGeometry = { x: g.x - 40, y: g.y, width: g.width, height: g.height }; }"
    assert_true "once read, a move says changed" "$(grep -c 'member=changed' "$OUT/map-signals.txt")" -ge 1
    kill "$mon" 2>/dev/null
    wait "$mon" 2>/dev/null

    # wait_view X Y: the desk has landed with the view at (X, Y).
    wait_view() {
        local i
        for i in $(seq 1 20); do
            c state
            [ "$(sget visible)" = false ] && [ "$(printf '%.0f' "$(sget viewx)")" = "$1" ] && [ "$(printf '%.0f' "$(sget viewy)")" = "$2" ] && return 0
            sleep 0.2
        done
        return 1
    }

    # go: the plane point comes to the screen's centre, the closed desk sliding there.
    mq go $((vx + WIDTH / 2 + 600)) $((vy + HEIGHT / 2)) >/dev/null
    wait_view $((vx + 600)) "$vy"
    assert_eq "go slides the desk to the point" "$(printf '%.0f' "$(sget viewx)")" $((vx + 600))
    assert_eq "and the canvas is closed again" "$(sget visible)" false

    # focus: KCalc is now off the screen's left; a click on its sheet brings it
    # back into view and gives it the focus.
    local id
    id=$(pj "$kcalc[\"id\"]" <<<"$(mq read)")
    mq focus "$id" >/dev/null
    local i plane=""
    for i in $(seq 1 20); do
        sleep 0.2
        plane=$(mq read)
        [ "$(pj "$kcalc[\"active\"]" <<<"$plane")" = 1 ] && [ "$(pj "(lambda w, c: c[0] <= w['x'] and w['x'] + w['w'] <= c[0] + c[2])($kcalc, p['camera'][0])" <<<"$plane")" = True ] && break
    done
    assert_eq "focus gives KCalc the focus" "$(pj "$kcalc[\"active\"]" <<<"$plane")" 1
    assert_eq "and slides it wholly into view" "$(pj "(lambda w, c: c[0] <= w['x'] and w['x'] + w['w'] <= c[0] + c[2])($kcalc, p['camera'][0])" <<<"$plane")" True

    # The widget itself, on the desktop. The desk first goes somewhere empty, so
    # no window covers the widget and anything the map shows is off the screen:
    # a click anywhere on the map then has to move the desk.
    mq go $((vx + 8000 + WIDTH / 2)) $((vy + HEIGHT / 2)) >/dev/null
    wait_view $((vx + 8000)) "$vy"
    assert_eq "the desk is on empty ground" "$(printf '%.0f' "$(sget viewx)")" $((vx + 8000))
    local wx=1180 wy=640 ww=640 wh=300
    shot "$OUT/map-before.png"
    nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "desktops()[0].addWidget('org.kde.kwin.canvas.map', $wx, $wy, $ww, $wh);" >/dev/null
    local drawn=0
    for i in $(seq 1 15); do
        sleep 0.4
        shot "$OUT/map-after.png"
        magick "$OUT/map-before.png" -crop "${ww}x${wh}+${wx}+${wy}" +repage "$OUT/map-a.png"
        magick "$OUT/map-after.png" -crop "${ww}x${wh}+${wx}+${wy}" +repage "$OUT/map-b.png"
        drawn=$({ magick compare -metric RMSE "$OUT/map-a.png" "$OUT/map-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p')
        awk -v m="${drawn:-0}" 'BEGIN{exit !(m > 0.02)}' && break
    done
    assert_true "the widget draws the map (rmse ${drawn:-none})" "$(awk -v m="${drawn:-0}" 'BEGIN{print (m > 0.02)}')" = 1
    # The click goes through the widget's own D-Bus call, the end of the chain
    # the qdbus6 calls above stand in for.
    if have_input; then
        printf 'move %d %d\nsleep 300\nclick\n' $((wx + ww / 2)) $((wy + wh / 2)) | input
        for i in $(seq 1 20); do
            sleep 0.2
            c state
            [ "$(sget visible)" = false ] && [ "$(printf '%.0f' "$(sget viewx)")" != $((vx + 8000)) ] && break
        done
        assert_true "a click on the map moves the desk" "$(printf '%.0f' "$(sget viewx)")" != $((vx + 8000))
    else
        skip "a click on the widget: fakeinput not built (make tools)"
    fi

    # Leave the desk as found: the widget off the desktop, the view home.
    nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        "for (const d of desktops()) for (const w of d.widgets('org.kde.kwin.canvas.map')) w.remove();" >/dev/null
    mq go $((vx + WIDTH / 2)) $((vy + HEIGHT / 2)) >/dev/null
    wait_view "$vx" "$vy"
    rm -f "$OUT"/map-*.png "$OUT/map-signals.txt"
    arrange >/dev/null
}
