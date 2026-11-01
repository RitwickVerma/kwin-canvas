# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="view caching: with the plugin the scene is kept between openings, so an overview after the first resumes a built scene and reaches its first frame sooner; the reused scene still takes the keyboard, shows its toolbar, searches, slides and leaves no window moved; ViewCaching off builds per open again"

cached() { c state >/dev/null; grep -o ' cached=[01]' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2; }
toggle_chord() { nq org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Toggle Canvas" >/dev/null 2>&1; }
# The median first paint of N overview opens through the chord.
first_paints() {
    local i mark out=""
    for i in $(seq "$1"); do
        sleep 0.8; mark=$(wc -l <"$LOG")
        toggle_chord; sleep 1.2; toggle_chord; sleep 1.0
        out="$out $(tail -n +"$((mark + 1))" "$LOG" | grep -a 'perf: first-paint' | head -1 | grep -ao 'ms=[0-9]*' | cut -d= -f2)"
    done
    tr ' ' '\n' <<<"$out" | grep . | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}'
}
reals() {
    kwinjs 'var o = []; ["KCalc","sample.txt","Konsole","Dolphin","Gwenview"].forEach(function (k) { workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(k) >= 0) o.push(k + "=" + Math.round(x.frameGeometry.x) + "," + Math.round(x.frameGeometry.y)); }); }); print("VCREALS " + o.join(" "));' 0.3
    grep -a "VCREALS " "$STATE/kwin.log" | tail -1 | sed 's/.*VCREALS //'
}

run_scenario() {
    source tests/lib.sh
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "the pass-through plugin is not loaded (make plugin)"; return
    fi
    arrange >/dev/null
    setcfg SmoothZoom false
    setcfg Perf true
    open_1to1; sleep 0.6; shot "$OUT/vc-first.png" >/dev/null; c cancel >/dev/null; sleep 0.8
    assert_eq "view caching is on with the plugin" "$(cached)" 1
    local on; on=$(first_paints 5)

    # The reused scene still works: the keys, the toolbar, the search, a slide.
    local before; before=$(reals)
    open_1to1; sleep 0.4
    if have_input; then
        printf 'key slash\nsleep 300\nkey k\nsleep 40\nkey c\nsleep 300\n' | input
        c state
        assert_eq "a reused scene takes the keys: / and typing search" "$(grep -oE ' search=("[^"]*":[0-9]+|-)' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2-)" '"kc":1'
        printf 'key esc\nsleep 200\nkey esc\nsleep 600\n' | input
    fi
    c state
    assert_eq "and the overview closes" "$(sget visible)" false
    c "slide 400 0"; sleep 1.2; c "slide -400 0"; sleep 1.2
    assert_eq "a slide there and back moves no window" "$(reals)" "$before"
    open_1to1; sleep 0.6; shot "$OUT/vc-reused.png" >/dev/null
    # The toolbar's strip at the top centre, the same in the reused scene as in the first.
    magick "$OUT/vc-first.png" -crop 720x40+600+8 +repage "$OUT/vc-a.png"; magick "$OUT/vc-reused.png" -crop 720x40+600+8 +repage "$OUT/vc-b.png"
    local d; d=$({ magick compare -metric RMSE "$OUT/vc-a.png" "$OUT/vc-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p')
    assert_true "the reused scene shows its toolbar as the first did (rmse $d)" "$(awk -v d="${d:-1}" 'BEGIN{print (d < 0.02)}')" -eq 1
    c cancel >/dev/null; sleep 0.8

    # Off: built per open again.
    setcfg ViewCaching false
    open_1to1; c cancel >/dev/null; sleep 0.8
    assert_eq "ViewCaching off is off" "$(cached)" 0
    local off; off=$(first_paints 5)
    echo "# overview first paint, median of 5: cached ${on} ms, built per open ${off} ms"
    assert_true "a resumed scene reaches its first frame sooner (${on} < ${off} ms)" "${on:-999}" -lt "${off:-0}"

    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key ViewCaching --delete
    setcfg Perf false
    arrange >/dev/null
}
