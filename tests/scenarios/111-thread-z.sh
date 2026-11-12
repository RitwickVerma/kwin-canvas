# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the threads respect z: a thread runs over the open ground between the facing sides of a pair, never across either window's body, and the hover lifts its window above the whole web while the raise reorders the entries under it"
region_rmse() {   # before after region
    magick "$1" -crop "$3" +repage "$OUT/tz-a.png"
    magick "$2" -crop "$3" +repage "$OUT/tz-b.png"
    { magick compare -metric RMSE "$OUT/tz-a.png" "$OUT/tz-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}
changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    # One cluster of three in a row - Konsole, KCalc, Dolphin, in that
    # stacking order (Konsole at the bottom, Dolphin on top) - and Gwenview
    # far away, its own cluster, the switch that lights and unlights the web.
    open_1to1
    c "placeby Konsole 100 600 620 420"
    c "placeby KCalc 900 300 480 420"
    c "placeby Dolphin 1540 600 700 360"
    c "placeby Gwenview 4000 400 460 420"
    c "placeby sample.txt 3000 900 640 508"
    c commit
    open_1to1
    c "activate Konsole"; c "activate KCalc"; c "activate Dolphin"
    c "zoom 0.6 960 540"
    for _ in 1 2 3 4 5 6 7 8 9 10; do c state; [ "$(sget cam)" = "-" ] && break; sleep 0.15; done
    # The probe: the middle of the Konsole-KCalc thread. A thread is the walk's step, drawn
    # from where the centre line leaves Konsole to where it enters KCalc, so it lies over the
    # ground between them and must be visible there whenever the web is lit. A point inside
    # either body is never on it.
    local kx ky kw kh vx vy z bx by
    kx=$(eget Konsole x); ky=$(eget Konsole y)
    kw=$(eget Konsole w); kh=$(eget Konsole h)
    read -r bx by <<<"$(thread_mid "$kx" "$ky" "$kw" "$kh" "$(eget KCalc x)" "$(eget KCalc y)" "$(eget KCalc w)" "$(eget KCalc h)")"
    # The cluster is unlit: the active window is Gwenview's, far away.
    c "activate Gwenview"
    sleep 0.6
    shot "$OUT/tz-unlit.png" >/dev/null
    # Lit: Dolphin, a member of the cluster, is active.
    c "activate Dolphin"
    sleep 0.6
    shot "$OUT/tz-lit.png" >/dev/null
    vx=$(sget viewx); vy=$(sget viewy); z=$(sget zoom)
    local box
    box=$(awk -v x="$bx" -v y="$by" -v vx="$vx" -v vy="$vy" -v z="$z" 'BEGIN{
        sx = (x - vx) * z; sy = (y - vy) * z
        printf "%dx%d+%d+%d\n", 10, 10, sx - 5, sy - 5
    }')
    assert_eq "the lit web draws the thread over the ground between the pair" \
        "$(changed "$(region_rmse "$OUT/tz-unlit.png" "$OUT/tz-lit.png" "$box")")" 1
    # The hover lifts Konsole above the whole web: its z jumps to the web's
    # roof, the raise reorders the entries under it, and the threads to it
    # re-midpoint above every other window - the same z rule the pixels
    # above just showed. KWrite, moved far away, keeps the bottom of the
    # stacking.
    assert_eq "before the hover Konsole sits one up from the bottom" "$(eget Konsole z)" 1001
    assert_eq "and KCalc above it" "$(eget KCalc z)" 1002
    read -r sx sy <<<"$(awk -v vx="$vx" -v vy="$vy" -v z="$z" -v kx="$kx" -v ky="$ky" -v kw="$kw" -v kh="$kh" 'BEGIN{
        printf "%d %d\n", (kx + kw / 2 - vx) * z, (ky + kh / 2 - vy) * z
    }')"
    input move "$sx" "$sy"
    # A quiet wait, no debug commands in it, then one read. The rest's focus
    # lands 1.5 to 1.9 s after the move here (measured by polling in 161's
    # shape, with the plugin's hover-clock guard in): the 900 ms hover delay
    # plus the effect's own settle. One read at 1.2 s caught it too early, and
    # a read loop before the guard restarted the clock on every pass.
    sleep 2.5
    c state
    assert_eq "the rest focused Konsole" "$(head -1 <<<"$LAST_STATE" | grep -c 'focus=.*Konsole')" 1
    assert_eq "and the hover lifts it above the web" "$(eget Konsole z)" 2000
    assert_eq "and the raise shifted KCalc down one" "$(eget KCalc z)" 1001
    c cancel
}
