# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="pass-through gestures at zoom: a drag selects text and the wheel scrolls at the picture's place"
region_rmse() {   # before after region
    magick "$1" -crop "$3" +repage "$OUT/ptg-a.png"
    magick "$2" -crop "$3" +repage "$OUT/ptg-b.png"
    { magick compare -metric RMSE "$OUT/ptg-a.png" "$OUT/ptg-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}
changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "pass-through plugin not loaded (make plugin)"; return
    fi
    c "activate Dolphin"
    c state
    local kx ky kw kh nx ny nw nh vx vy z
    kx=$(eget KWrite x); ky=$(eget KWrite y); kw=$(eget KWrite w); kh=$(eget KWrite h)
    nx=$(eget Konsole x); ny=$(eget Konsole y); nw=$(eget Konsole w); nh=$(eget Konsole h)
    open_1to1
    c "zoom 0.5 960 540"
    sleep 0.6; c state
    vx=$(sget viewx); vy=$(sget viewy); z=$(sget zoom)
    # KWrite's picture on the primary screen, at this view and zoom.
    local sx sy sw sh
    read -r sx sy sw sh <<<"$(awk -v vx="$vx" -v vy="$vy" -v z="$z" -v kx="$kx" -v ky="$ky" -v kw="$kw" -v kh="$kh" 'BEGIN{
        printf "%d %d %d %d\n", (kx - vx) * z, (ky - vy) * z, kw * z, kh * z
    }')"
    shot "$OUT/ptg-before.png" >/dev/null
    # A drag inside the picture selects text: from three tenths to six
    # tenths across, at mid height - the surface receives it at the same
    # relative place, so the selection shows in the picture's region.
    local dx1 dy1 dx2 dy2
    dx1=$((sx + sw * 3 / 10)); dy1=$((sy + sh / 2))
    dx2=$((sx + sw * 6 / 10)); dy2=$((sy + sh / 2))
    printf "move %d %d\nsleep 300\ndrag %d %d %d %d\n" "$dx1" "$dy1" "$dx1" "$dy1" "$dx2" "$dy2" | input
    sleep 0.6
    shot "$OUT/ptg-after.png" >/dev/null
    assert_true "the drag selected text in KWrite's picture" \
        "$(changed "$(region_rmse "$OUT/ptg-before.png" "$OUT/ptg-after.png" "${sw}x${sh}+${sx}+${sy}")")" = 1
    # The wheel over Konsole's picture scrolls it.
    local ox oy cwx cwy cxo cyo
    read -r ox oy cwx cwy cxo cyo <<<"$(awk -v vx="$vx" -v vy="$vy" -v z="$z" -v nx="$nx" -v ny="$ny" -v nw="$nw" -v nh="$nh" 'BEGIN{
        printf "%d %d %d %d %d %d\n", (nx - vx) * z + nw * z / 2, (ny - vy) * z + nh * z / 2, nw * z, nh * z, (nx - vx) * z, (ny - vy) * z
    }')"
    input move "$ox" "$oy"
    sleep 0.4
    printf 'wheel 3\n' | input
    sleep 0.6
    shot "$OUT/ptg-wheel.png" >/dev/null
    assert_true "the wheel scrolled Konsole's picture" \
        "$(changed "$(region_rmse "$OUT/ptg-after.png" "$OUT/ptg-wheel.png" "${cwx}x${cwy}+${cxo}+${cyo}")")" = 1
    # Leave the fixtures as found: undo the drag's selection and the scroll.
    printf "move %d %d\nsleep 300\nclick\nkey leftctrl down\nkey z\nkey leftctrl up\n" "$dx1" "$dy1" | input
    input move "$ox" "$oy"
    sleep 0.4
    printf 'wheel -3\n' | input
    sleep 0.5
    c cancel
    arrange >/dev/null
}
