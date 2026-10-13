# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the hover spotlight: the window the pointer rests on steps forward into the light, nothing tints the bare plane behind it, and the light is the same when the hand leaves when the hand leaves"

region_rmse() {   # before after region
    magick "$1" -crop "$3" +repage "$OUT/ho-a.png"
    magick "$2" -crop "$3" +repage "$OUT/ho-b.png"
    { magick compare -metric RMSE "$OUT/ho-a.png" "$OUT/ho-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}

changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }

run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    open_1to1
    c "zoom 0.5 960 540"
    sleep 0.5
    c state
    assert_eq "the overworld is up at half zoom" "$(sget visible)" true
    shot "$OUT/ho-pre.png" >/dev/null
    # The pointer rests on KWrite's centre ((640,120,700,520) at half zoom,
    # the view (-960,-540)): canvas (990,380) -> screen (975,460). The rest
    # passes the 320 ms grace + the 200 ms settle, then the glow and the
    # spotlight come on together.
    input move 975 460
    sleep 1.4
    shot "$OUT/ho-dim.png" >/dev/null
    # A bare stretch of the plane behind every window: canvas (2040,2840) ->
    # screen (60,880). Only the veil has ever touched it.
    # The veil is gone (the look is raw): the wallpaper behind is never tinted.
    assert_eq "the plane behind is not tinted" "$(changed "$(region_rmse "$OUT/ho-pre.png" "$OUT/ho-dim.png" "120x120+60+880")")" 0
    # The hand leaves for the empty ground; the light comes back.
    input move 1600 900
    sleep 0.8
    shot "$OUT/ho-back.png" >/dev/null
    assert_eq "and it is the same when the hand leaves" "$(changed "$(region_rmse "$OUT/ho-pre.png" "$OUT/ho-back.png" "120x120+60+880")")" 0
    c cancel
    arrange >/dev/null
}
