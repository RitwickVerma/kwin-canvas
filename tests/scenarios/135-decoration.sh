# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the canvas decoration: the glass pill rides the focused window's top edge, follows the focus, and disappears from every other window - the close glyph's proof belongs to the live session (the nest's KWin cannot close a window at all)"

glass_count() {
    # The pill's glass over the wallpaper: the glass blends to a
    # distinctive deep tone (51,40,66)-ish, while the fixture wallpaper's
    # purple (114,83,140) stays above these gates - so only the pill's
    # own pixels count, wherever it sits along the band.
    magick "$1" -crop "$2" +repage -depth 8 txt: \
        | awk -F'[(),]' 'NR>1 { if ($3 < 80 && $4 < 70 && $5 < 110) n++ } END { print n + 0 }'
}

run_scenario() {
    source tests/lib.sh
    if [ "${NEST_DECOR:-}" != canvas ]; then
        skip "the canvas decoration is not loaded (make test-decor / NEST_DECOR=canvas)"
        return
    fi
    arrange >/dev/null
    sleep 1.5
    # The arrange's activation chain ends at KCalc: the active window wears
    # the pill, the Konsole does not.
    shot "$OUT/135-a.png"
    a1=$(glass_count "$OUT/135-a.png" "480x32+100+120")   # KCalc's band
    a2=$(glass_count "$OUT/135-a.png" "620x32+100+600")   # Konsole's band
    c "activate Konsole"
    sleep 1.2
    shot "$OUT/135-b.png"
    b1=$(glass_count "$OUT/135-b.png" "480x32+100+120")
    b2=$(glass_count "$OUT/135-b.png" "620x32+100+600")
    assert_eq "the pill left KCalc's edge" \
        "$(awk -v a="$a1" -v b="$b1" 'BEGIN{print (a - b > 1200)}')" 1
    assert_eq "and arrived on Konsole's" \
        "$(awk -v a="$a2" -v b="$b2" 'BEGIN{print (b - a > 1200)}')" 1
    # The close glyph (the pill's leftmost button) kills the window. The
    # click lands and the requestClose() fires, but the nest's KWin cannot
    # close a window at all - even its own killWindow D-Bus is a no-op
    # there - so the glyph's proof belongs to the live session.
    skip "the nest's KWin cannot close a window; the glyphs get their proof on the live session"
    arrange >/dev/null
}
