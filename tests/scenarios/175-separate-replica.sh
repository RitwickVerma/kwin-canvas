# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="separate cameras: with the overview open on one monitor, the other monitor shows its desk as it really is (same picture as before), and a quiet slide on one monitor leaves the other monitor's windows exactly where they were"
real() { # CAPTION -> "x y w h"
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) w = x; }); var g = w.frameGeometry; print(\"REPREAL \" + Math.round(g.x) + \" \" + Math.round(g.y) + \" \" + Math.round(g.width) + \" \" + Math.round(g.height));" 0.5
    grep -a "REPREAL" "$STATE/kwin.log" | tail -1 | sed 's/.*REPREAL //'
}
run_scenario() {
    source tests/lib.sh
    c state >/dev/null
    if [ "$(sget screens)" != 2 ]; then skip "needs two outputs (NEST_OUTPUTS=2)"; return; fi
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    setcfg SmoothZoom false
    run kscreen-doctor output.Virtual-0.position.0,0 output.Virtual-1.position.1920,0 output.Virtual-0.scale.1 output.Virtual-1.scale.1 >/dev/null 2>&1
    sleep 2.5
    setcfg Cameras separate
    arrange >/dev/null
    c state >/dev/null
    local r0x r0y r0w r0h r1x r1y r1w r1h
    read -r r0x r0y r0w r0h <<<"$(screenrect 0)"
    read -r r1x r1y r1w r1h <<<"$(screenrect 1)"
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"Dolphin\") >= 0) w = x; }); w.frameGeometry = {x: $((r1x + 380)), y: 300, width: 700, height: 360};" 0.6
    input move $((r1x + r1w - 5)) $((r1y + r1h - 5)); sleep 0.5
    shot "$OUT/rep-before.png" >/dev/null
    input move $((r0x + r0w / 2)) $((r0y + r0h / 2)); sleep 0.3
    c open >/dev/null; sleep 1.2
    c "zoom 0.4 $((r0x + r0w / 2)) $((r0y + r0h / 2))" >/dev/null; sleep 1.2
    shot "$OUT/rep-during.png" >/dev/null
    # The second monitor's half of both shots: the same picture, but for the window's drop
    # shadow, which the replica's thumbnails do not draw.
    magick "$OUT/rep-before.png" -crop "${r1w}x${r1h}+${r1x}+${r1y}" +repage "$OUT/rep-b.png"
    magick "$OUT/rep-during.png" -crop "${r1w}x${r1h}+${r1x}+${r1y}" +repage "$OUT/rep-d.png"
    local rm
    rm=$({ magick compare -metric RMSE "$OUT/rep-b.png" "$OUT/rep-d.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p')
    assert_true "monitor 1 looks the same with the overview open on monitor 0 (rmse $rm)" "$(awk -v m="${rm:-1}" 'BEGIN{print (m < 0.03)}')" = 1
    c cancel >/dev/null 2>&1; sleep 0.8
    # A quiet slide on monitor 0 leaves monitor 1's window where it was.
    input move $((r0x + r0w / 2)) $((r0y + r0h / 2)); sleep 0.3
    c "slide 500 0" >/dev/null; sleep 1.6
    assert_eq "a slide on monitor 0 left Dolphin on monitor 1 where it was" "$(real Dolphin)" "$((r1x + 380)) 300 700 360"
    assert_true "and it moved monitor 0's windows" "$(real KCalc | cut -d' ' -f1)" -ne 100
    setcfg Cameras merged
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
