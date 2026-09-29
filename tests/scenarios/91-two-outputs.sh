#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="two outputs: one frame and one wallpaper tile per output, the camera around the screen the pointer is on, and a corner push on the second output"
# ceil() of the tile grid computeBackdropTiles() lays out, from the state's own
# screen lines: the arrangement's bounding box in primary-screen steps.
tiles_for() {   # tiles_for REACH X0 Y0 W0 H0 X1 Y1 W1 H1
    awk -v r="$1" -v ax="$2" -v ay="$3" -v aw="$4" -v ah="$5" -v bx="$6" -v by="$7" -v bw="$8" -v bh="$9" 'BEGIN{
        vx = (ax < bx ? ax : bx); vy = (ay < by ? ay : by);
        vr = (ax + aw > bx + bw ? ax + aw : bx + bw);
        vb = (ay + ah > by + bh ? ay + ah : by + bh);
        cols = int((vr - vx + aw - 1) / aw) + 2 * r;
        rows = int((vb - vy + ah - 1) / ah) + 2 * r;
        print 2 + cols * rows }'
}
run_scenario() {
    c state
    if [ "$(sget screens)" != 2 ]; then skip "needs two outputs (make test-two-outputs)"; return; fi
    local x0 y0 w0 h0 x1 y1 w1 h1
    read -r x0 y0 w0 h0 <<<"$(screenrect 0)"
    read -r x1 y1 w1 h1 <<<"$(screenrect 1)"
    assert_true "the two outputs make a desktop bigger than one" \
        "$(awk -v ax="$x0" -v ay="$y0" -v aw="$w0" -v ah="$h0" \
                -v bx="$x1" -v by="$y1" -v bw="$w1" -v bh="$h1" 'BEGIN{
            vw = (ax + aw > bx + bw ? ax + aw : bx + bw) - (ax < bx ? ax : bx);
            vh = (ay + ah > by + bh ? ay + ah : by + bh) - (ay < by ? ay : by);
            print (vw >= aw + 100 || vh >= ah + 100) }')" = 1

    # Every activity has a frame on every output, and the wallpaper has a tile
    # at every output's place: the plane is the whole arrangement, not the
    # primary output with the rest filled in. The padding tiles come outward
    # from the arrangement's bounding box, at primary-screen steps.
    open_1to1
    setcfg BackdropReach 0
    c state
    assert_eq "a wallpaper tile per output" "$(sget backdrop)" 2
    setcfg BackdropReach 2
    c state
    assert_eq "and the padding tiles cover the arrangement" "$(sget backdrop)" \
        "$(tiles_for 2 "$x0" "$y0" "$w0" "$h0" "$x1" "$y1" "$w1" "$h1")"

    # Hiding one output's frame leaves the other's: what is hidden is a
    # (activity, output) pair, named by the output KWin reports.
    c "hide 0 1"
    assert_eq "the second output's frame is hidden" "$(tget 0 hidden)" "$(screenname 1)"
    c "hide 0 0"
    assert_eq "both, when both are" "$(tget 0 hidden)" "$(screenname 0),$(screenname 1)"
    c "show 0 1"; c "show 0 0"
    assert_eq "and shown again" "$(tget 0 hidden)" ""

    # Zoom to fit fits the output the pointer is on, not the primary one and not
    # the focused window's. The fit divides the box into the *action screen*, so
    # moving the pointer one screen to the right moves the camera one screen to
    # the left at the fit's zoom: the two views differ by exactly the seam over
    # the zoom, and by nothing in y when the outputs are side by side. (With two
    # outputs an activity's frame group is the whole arrangement wide, so the
    # activities stand two screens and a gap apart and the fit zoom is small.)
    input move $((x0 + w0 / 2)) $((y0 + h0 / 2))
    sleep 0.3
    c extents
    local vx0 vy0 vx1 vy1 fz
    vx0=$(sget viewx); vy0=$(sget viewy); fz=$(sget zoom)
    input move $((x1 + w1 / 2)) $((y1 + h1 / 2))
    sleep 0.3
    c extents
    vx1=$(sget viewx); vy1=$(sget viewy)
    assert_near "fit is around the output the pointer is on, x" \
        "$(awk -v a="$vx0" -v b="$vx1" 'BEGIN{printf "%.3f", b - a}')" \
        "$(awk -v d=$((x0 - x1)) -v z="$fz" 'BEGIN{printf "%.3f", d / z}')" 2
    assert_near "and y" \
        "$(awk -v a="$vy0" -v b="$vy1" 'BEGIN{printf "%.3f", b - a}')" \
        "$(awk -v d=$((y0 - y1)) -v z="$fz" 'BEGIN{printf "%.3f", d / z}')" 2

    # A corner is on every output (ElectricBorderAllScreenCorner), and the
    # canvas steps out around the screen that was pushed: BorderZoom's anchor
    # is that screen's centre, so the camera lands a quarter of that centre
    # short of the frames. On the primary output that is the same -240 the
    # single-output scenario checks; on the second it is that output's own
    # centre, which is what makes a corner on the far screen open around the
    # far screen.
    setcfg BorderZoom 0.8
    set_borders 3
    # A push while the canvas is open enters instead of stepping out, so the
    # nest is closed and at 1:1 before the pointer goes to the corner.
    c cancel
    sleep 0.4
    c home
    sleep 0.3
    c state
    local tx0 ty0; tx0=$(tget 0 x); ty0=$(tget 0 y)
    push_border_on 3 "$x1" "$y1" "$w1" "$h1"
    sleep 0.7; c state
    assert_eq "the corner on the second output opened the canvas" "$(sget visible)" true
    assert_near "stepped out to BorderZoom" "$(sget zoom)" 0.8 0.005
    assert_near "around the pushed output's centre x" "$(sget viewx)" \
        "$(awk -v t="$tx0" -v c=$((x1 + w1 / 2)) 'BEGIN{printf "%.1f", t - 0.25 * c}')" 2
    assert_near "around the pushed output's centre y" "$(sget viewy)" \
        "$(awk -v t="$ty0" -v c=$((y1 + h1 / 2)) 'BEGIN{printf "%.1f", t - 0.25 * c}')" 2
    snap two-output-corner

    # The chord enters the location under the pushed output's centre, which at
    # 1:1 is exactly the point the push came back to: the two anchors are the
    # same screen, so entering undoes the step out and the viewport, the
    # frames and every window are where they were before the push.
    c enter
    sleep 0.6; c state
    assert_eq "entering closed the canvas" "$(sget visible)" false
    assert_eq "and left the viewport where the push found it" "$(tget 0 x),$(tget 0 y)" "$tx0,$ty0"
    assert_eq "with the windows unwritten" "$(eget KCalc fx),$(eget KCalc fy)" "100,120"

    c open
    c home
    set_borders 7
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key BorderZoom --delete
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key BackdropReach --delete
    c state
    assert_eq "the defaults are back" "$(sget backdrop)" \
        "$(tiles_for 2 "$x0" "$y0" "$w0" "$h0" "$x1" "$y1" "$w1" "$h1")"
    arrange >/dev/null
}
