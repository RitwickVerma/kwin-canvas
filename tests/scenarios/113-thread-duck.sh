# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a thread is a line through the stack: it ducks under a window that covers its middle stretch, and stays above the open ground everywhere else"

region_rmse() {   # before after region
    magick "$1" -crop "$3" +repage "$OUT/td-a.png"
    magick "$2" -crop "$3" +repage "$OUT/td-b.png"
    { magick compare -metric RMSE "$OUT/td-a.png" "$OUT/td-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}

changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }

run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    # The pixel probes assume the flat plane's geometry; the 3D tilt is
    # scenario 126's subject, so it is pinned off here.
    setcfg Depth3D false

    # One cluster of three - KCalc, Dolphin (opaque) overlapping KCalc's
    # centre, KWrite past Dolphin - and the rest far away, their own
    # clusters, the switches that light and unlight the web. The thread
    # from KCalc's centre to KWrite's leaves KCalc under Dolphin, crosses
    # the open ground, and reaches KWrite: where Dolphin covers it, it must
    # be hidden; where the ground is, it must show.
    open_1to1
    c "placeby KCalc 900 300 480 420"
    c "placeby Dolphin 950 400 700 360"
    c "placeby sample.txt 1750 300 700 520"
    c "placeby Konsole 3000 900 620 420"
    c "placeby Gwenview 4000 400 460 420"
    c commit
    open_1to1
    c "activate KCalc"; c "activate Dolphin"; c "activate sample.txt"
    c "zoom 0.6 960 540"
    for _ in 1 2 3 4 5 6 7 8 9 10; do c state; [ "$(sget cam)" = "-" ] && break; sleep 0.15; done

    # The stack: the covering window above the lower endpoint, the far
    # endpoint above the cover - the arrangement the fix was made for.
    assert_eq "the cover sits above the lower endpoint" \
        "$(awk -v a="$(eget Dolphin z)" -v b="$(eget KCalc z)" 'BEGIN{print (a>b)?1:0}')" 1
    assert_eq "and the far endpoint above the cover" \
        "$(awk -v a="$(eget sample.txt z)" -v b="$(eget Dolphin z)" 'BEGIN{print (a>b)?1:0}')" 1

    local kx ky kw kh dx dy dw dh
    kx=$(eget KCalc x); ky=$(eget KCalc y); kw=$(eget KCalc w); kh=$(eget KCalc h)
    dx=$(eget sample.txt x); dy=$(eget sample.txt y); dw=$(eget sample.txt w); dh=$(eget sample.txt h)

    # p1: KCalc's centre, under Dolphin. p2: the thread's exposed stretch
    # between Dolphin's edge and KWrite's (t = 0.58 of the centre-to-centre
    # line: past Dolphin's right edge at 1650, short of KWrite's left at
    # 1750).
    local px py qx qy
    read -r px py qx qy <<<"$(awk -v kx="$kx" -v ky="$ky" -v kw="$kw" -v kh="$kh" -v dx="$dx" -v dy="$dy" -v dw="$dw" -v dh="$dh" 'BEGIN{
        cx = kx + kw / 2; cy = ky + kh / 2
        ex = dx + dw / 2; ey = dy + dh / 2
        printf "%d %d %d %d\n", cx, cy, cx + 0.58 * (ex - cx), cy + 0.58 * (ey - cy)
    }')"

    # The cluster is unlit: the active window is Konsole's, far away.
    c "activate Konsole"
    sleep 0.6
    shot "$OUT/td-unlit.png" >/dev/null
    # Lit: KWrite, a member of the cluster, is active.
    c "activate sample.txt"
    sleep 0.6
    shot "$OUT/td-lit.png" >/dev/null

    local vx vy z
    vx=$(sget viewx); vy=$(sget viewy); z=$(sget zoom)
    local b1 b2
    b1=$(awk -v x="$px" -v y="$py" -v vx="$vx" -v vy="$vy" -v z="$z" 'BEGIN{
        sx = (x - vx) * z; sy = (y - vy) * z
        printf "%dx%d+%d+%d\n", 10, 10, sx - 5, sy - 5
    }')
    b2=$(awk -v x="$qx" -v y="$qy" -v vx="$vx" -v vy="$vy" -v z="$z" 'BEGIN{
        sx = (x - vx) * z; sy = (y - vy) * z
        printf "%dx%d+%d+%d\n", 10, 10, sx - 5, sy - 5
    }')

    assert_eq "the thread ducks under the window covering its attach" \
        "$(changed "$(region_rmse "$OUT/td-unlit.png" "$OUT/td-lit.png" "$b1")")" 0
    assert_eq "and shows over the open ground between the windows" \
        "$(changed "$(region_rmse "$OUT/td-unlit.png" "$OUT/td-lit.png" "$b2")")" 1

    c cancel
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Depth3D --delete
}
