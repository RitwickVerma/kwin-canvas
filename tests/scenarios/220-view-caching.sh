# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="view caching: with the plugin the scene is kept between openings, so an overview after the first resumes a built scene and reaches its first frame sooner; the kept scene holds no window offscreen while closed and is let go when the GPU's memory runs short; the reused scene still takes the keyboard, shows its toolbar, searches, slides and leaves no window moved; ViewCaching off builds per open again"

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
    # The kept scene keeps no window busy: KWin copies a thumbnail's window on every frame it
    # changes, and keeps a hidden one drawing. The pictures hold their windows while open only.
    # (Measured against the count before the first open: a notification or a task tooltip
    # holds its own.)
    c state; local base; base=$(sget offscreen)
    open_1to1; sleep 0.6; shot "$OUT/vc-first.png" >/dev/null
    c state
    assert_true "an open canvas holds its windows' pictures (offscreen=$(sget offscreen), before ${base})" "$(sget offscreen)" -gt "${base:-0}"
    c cancel >/dev/null; sleep 0.8
    assert_eq "view caching is on with the plugin" "$(cached)" 1
    c state
    assert_eq "a closed canvas holds no window offscreen" "$(sget offscreen)" "$base"
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

    # A full card lets the kept scene go: with VramReduced at 0 any reading of the GPU's memory
    # (the host's real card) is past it, and within a few seconds the closed canvas drops its
    # views. The next open builds the scene afresh. (No NVML on the host: nothing to read.)
    c state
    assert_eq "a closed canvas keeps its scene" "$(sget kept)" 1
    local kpid rss0 rss1 kept=1
    kpid=$(pgrep -f -- "--socket wayland-$NEST_NAME" | while read -r p; do [ "$(cat /proc/"$p"/comm 2>/dev/null)" = kwin_wayland ] && echo "$p"; done | head -1)
    rss0=$(awk '/VmRSS/{print $2}' "/proc/${kpid:-0}/status" 2>/dev/null)
    setcfg VramReduced 0
    for _ in $(seq 1 12); do sleep 1; c state; kept=$(sget kept); [ "$kept" = 0 ] && break; done
    if nvidia-smi -L >/dev/null 2>&1; then
        assert_eq "a full GPU memory lets the kept scene go" "$kept" 0
        sleep 1
        rss1=$(awk '/VmRSS/{print $2}' "/proc/${kpid:-0}/status" 2>/dev/null)
        echo "# kwin's resident memory with the kept scene ${rss0:-?} kB, after letting it go ${rss1:-?} kB (software rendering: the scene's buffers are in it)"
    else
        skip "no NVIDIA GPU on the host: the GPU's memory cannot be read"
    fi
    setcfg VramReduced 100
    open_1to1; sleep 0.6; shot "$OUT/vc-rebuilt.png" >/dev/null
    magick "$OUT/vc-rebuilt.png" -crop 720x40+600+8 +repage "$OUT/vc-c.png"
    d=$({ magick compare -metric RMSE "$OUT/vc-a.png" "$OUT/vc-c.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p')
    assert_true "the scene built afresh shows its toolbar as the first did (rmse $d)" "$(awk -v d="${d:-1}" 'BEGIN{print (d < 0.02)}')" -eq 1
    c cancel >/dev/null; sleep 0.8
    c state
    assert_eq "and closed again, the new scene is kept" "$(sget kept)" 1

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
