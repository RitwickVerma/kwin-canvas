# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the canvas decoration: no title bar (the band above a window stays the desktop), and the glass pill fades in over the top edge - the glyphs' close and minimize ship, their proof belongs to the live session (the nest's KWin cannot close a window at all)"

region_rmse() {
    magick "$1" -crop "$3" +repage "$OUT/135-a.png"
    magick "$2" -crop "$3" +repage "$OUT/135-b.png"
    { magick compare -metric RMSE "$OUT/135-a.png" "$OUT/135-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}
changed() {
    awk -v m="$1" 'BEGIN{print (m > 0.005)}'
}

run_scenario() {
    source tests/lib.sh
    shot "$OUT/135-pre.png"
    arrange >/dev/null
    sleep 1.5
    shot "$OUT/135-post.png"
    # KCalc sits at (100,120): the strip above its client (the title bar's
    # old home, minus the hairline) must still be the desktop - the canvas
    # frame draws no bar there.
    m=$(region_rmse "$OUT/135-pre.png" "$OUT/135-post.png" "80x4+300+116")
    assert_eq "no title bar above the client" "$(changed "$m")" 0
    # the glass pill fades in over the top edge
    { printf 'move 340 128\nsleep 400\n'; } | input
    sleep 1.2
    shot "$OUT/135-pill.png"
    m=$(region_rmse "$OUT/135-post.png" "$OUT/135-pill.png" "80x28+300+110")
    assert_eq "the pill fades in over the top edge" "$(changed "$m")" 1
    # the close glyph (the pill's leftmost button) kills the window. The
    # click lands on the button and the requestClose() fires (proven by
    # the decoration's own log line), but the nest's KWin cannot close a
    # window at all - even its own killWindow D-Bus is a no-op there - so
    # the glyph's proof belongs to the live session, not the harness.
    { printf 'move 295 143\nsleep 300\nclick\nsleep 300\n'; } | input
    sleep 1.0
    skip "the nest's KWin cannot close a window; the glyphs get their proof on the live session"
    arrange >/dev/null
}
