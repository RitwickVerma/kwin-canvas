# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the canvas decoration: no title bar (the band above a window stays the desktop), and the glass pill sits on the top edge - the glyphs' close and minimize ship, their proof belongs to the live session (the nest's KWin cannot close a window at all)"

region_rmse() {
    magick "$1" -crop "$3" +repage "$OUT/135-a.png"
    magick "$2" -crop "$3" +repage "$OUT/135-b.png"
    { magick compare -metric RMSE "$OUT/135-a.png" "$OUT/135-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}
changed() {
    awk -v m="$1" 'BEGIN{print (m > 0.005)}'
}
region_ae() {
    magick "$1" -crop "$3" +repage "$OUT/135-c.png"
    magick "$2" -crop "$3" +repage "$OUT/135-d.png"
    { magick compare -metric AE "$OUT/135-c.png" "$OUT/135-d.png" null: 2>&1 || true; } | head -1
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
    # The pill is always visible, so its proof is the glyphs' answer to the
    # pointer: resting on the close glyph swells it and fills its glass.
    { printf 'move 295 137\nsleep 500\n'; } | input
    sleep 1.2
    shot "$OUT/135-pill.png"
    ae=$(region_ae "$OUT/135-post.png" "$OUT/135-pill.png" "30x30+282+124")
    assert_eq "the close glyph answers the pointer" "$(awk -v n="$ae" 'BEGIN{print (n > 50)}')" 1
    # the close glyph (the pill's leftmost button) kills the window. The
    # click lands on the button and the requestClose() fires (proven by
    # the decoration's own log line), but the nest's KWin cannot close a
    # window at all - even its own killWindow D-Bus is a no-op there - so
    # the glyph's proof belongs to the live session, not the harness.
    { printf 'move 295 137\nsleep 300\nclick\nsleep 300\n'; } | input
    sleep 1.0
    skip "the nest's KWin cannot close a window; the glyphs get their proof on the live session"
    arrange >/dev/null
}
