# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="separate cameras: leaving the canvas from one monitor moves only that monitor's desk. A window on the other monitor stays exactly where it is, and a window left outside every desk is parked beyond all monitors instead of landing on the neighbour; with the cameras merged the same walk moves every window"
real() { # CAPTION -> "x y" of the real window
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) w = x; }); var g = w.frameGeometry; print(\"SEPREAL \" + Math.round(g.x) + \" \" + Math.round(g.y) + \" \" + Math.round(g.width) + \" \" + Math.round(g.height));" 0.5
    grep -a "SEPREAL" "$STATE/kwin.log" | tail -1 | sed 's/.*SEPREAL //'
}
leaks() { # "x y w h" -> yes if the rect overlaps any output
    local x y w h r=no i ox oy ow oh
    read -r x y w h <<<"$1"
    for i in 0 1; do
        read -r ox oy ow oh <<<"$(screenrect $i)"
        [ "$(awk -v x="$x" -v y="$y" -v w="$w" -v h="$h" -v ox="$ox" -v oy="$oy" -v ow="$ow" -v oh="$oh" 'BEGIN{print (x < ox + ow && x + w > ox && y < oy + oh && y + h > oy) ? 1 : 0}')" = 1 ] && r=yes
    done
    echo "$r"
}
walk() { # the same walk in either mode: Dolphin onto monitor 1, open on monitor 0, look left, step in
    arrange >/dev/null
    c state >/dev/null
    local r1x r1y r1w r1h r0x r0y r0w r0h
    read -r r0x r0y r0w r0h <<<"$(screenrect 0)"
    read -r r1x r1y r1w r1h <<<"$(screenrect 1)"
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"Dolphin\") >= 0) w = x; }); w.frameGeometry = {x: $((r1x + 380)), y: 300, width: 700, height: 360};" 0.6
    input move $((r0x + r0w / 2)) $((r0y + r0h / 2)); sleep 0.3
    c open >/dev/null; sleep 1.2; c state >/dev/null
    CAMS=$(sed -n '1s/.* cams=\([^ ]*\).*/\1/p' <<<"$LAST_STATE")
    c "panpx 700 0" >/dev/null; sleep 0.6
    c enter >/dev/null; sleep 1.5
}
run_scenario() {
    source tests/lib.sh
    c state >/dev/null
    if [ "$(sget screens)" != 2 ]; then skip "needs two outputs (NEST_OUTPUTS=2)"; return; fi
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    setcfg SmoothZoom false
    # Side by side at scale 1: the nest's default, set here because another scenario may have
    # left a different layout in this nest.
    run kscreen-doctor output.Virtual-0.position.0,0 output.Virtual-1.position.1920,0 output.Virtual-0.scale.1 output.Virtual-1.scale.1 >/dev/null 2>&1
    sleep 2.5
    c state >/dev/null
    local r1x r1y r1w r1h
    read -r r1x r1y r1w r1h <<<"$(screenrect 1)"
    # Merged: everything shares one desk, so the step-in moves Dolphin on monitor 1 too.
    setcfg Cameras merged
    walk
    assert_eq "merged: the walk ran with merged cameras" "$CAMS" merged
    assert_true "merged: Dolphin on the other monitor moved with the desk" "$(real Dolphin | cut -d' ' -f1)" -ne $((r1x + 380))
    # Separate: only monitor 0's desk moves.
    setcfg Cameras separate
    walk
    assert_eq "separate: the active camera is the pointer's monitor" "$CAMS" "separate:Virtual-0"
    assert_eq "separate: Dolphin on the other monitor did not move" "$(real Dolphin)" "$((r1x + 380)) 300 700 360"
    # Gwenview's plane spot is in neither desk and its real spot would be on monitor 0 or 1; it is
    # parked on the far side of the nearest desk's opposite edge: 300 px beyond the desktop's left edge.
    assert_eq "separate: Gwenview, left outside every desk, is parked beyond the desktop" "$(real Gwenview)" "-760 120 460 420"
    assert_eq "separate: and it shows on no monitor" "$(leaks "$(real Gwenview)")" no
    assert_eq "separate: KCalc, whose spot is in the new desk, is on monitor 0" "$([ "$(real KCalc | cut -d' ' -f1)" -lt "$r1x" ] && echo yes || echo no)" yes
    setcfg Cameras merged
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
