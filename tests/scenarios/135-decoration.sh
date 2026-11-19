# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the canvas decoration: every window wears one title bar, drawn edge to edge in the colour scheme's title bar colours, active for the focused window and inactive for the rest, and the colours follow the focus; the frame's top corners are the bar, so a frame-shaping effect rounds what the eye sees - the close glyph's proof belongs to the live session (the nest's KWin cannot close a window)"

# dominant IMG GEOM: "COUNT HEX" of the most common colour in that crop.
dominant() {
    magick "$1" -crop "$2" +repage -alpha off -depth 8 -format %c histogram:info:- \
        | sort -rn | head -1 | awk '{ c = $1; sub(":", "", c); for (i = 2; i <= NF; i++) if ($i ~ /^#/) { print c, $i; exit } }'
}
# pixel IMG X Y: that pixel as #RRGGBB.
pixel() { echo "#$(magick "$1" -alpha off -depth 8 -format "%[hex:p{$2,$3}]" info:)"; }

run_scenario() {
    source tests/lib.sh
    if [ "${NEST_DECOR:-}" != canvas ]; then
        skip "the canvas decoration is not loaded (make test-decor / NEST_DECOR=canvas)"
        return
    fi
    arrange >/dev/null
    sleep 1.5
    # The arrange's activation chain ends at KCalc (frame 100,120 480 wide):
    # it wears the active bar, Konsole (100,600, 620 wide) the inactive one.
    shot "$OUT/135-a.png"
    local ka kn ca cn ka2 kn2
    read -r ca ka <<<"$(dominant "$OUT/135-a.png" "480x32+100+120")"
    read -r cn kn <<<"$(dominant "$OUT/135-a.png" "620x32+100+600")"
    echo "# active bar $ka over $ca px, inactive bar $kn over $cn px"
    assert_true "the focused window wears a drawn bar (its colour covers most of the band)" "$ca" -ge $((480 * 32 * 6 / 10))
    assert_true "and so does the unfocused one" "$cn" -ge $((620 * 32 * 6 / 10))
    assert_true "the active and inactive bars wear different colours ($ka, $kn)" "$([ "$ka" != "$kn" ] && echo 1 || echo 0)" -eq 1
    # The frame's top corners are the bar, not the wallpaper: a frame-shaping effect's
    # rounding falls on pixels the eye sees.
    assert_eq "the frame's top left corner is the bar" "$(pixel "$OUT/135-a.png" 100 120)" "$ka"
    assert_eq "and its top right corner" "$(pixel "$OUT/135-a.png" 579 120)" "$ka"
    c "activate Konsole"
    sleep 1.2
    shot "$OUT/135-b.png"
    read -r _ ka2 <<<"$(dominant "$OUT/135-b.png" "480x32+100+120")"
    read -r _ kn2 <<<"$(dominant "$OUT/135-b.png" "620x32+100+600")"
    assert_eq "the focus moved: KCalc's bar went inactive" "$ka2" "$kn"
    assert_eq "and Konsole's went active" "$kn2" "$ka"
    # The state marks wear the colour scheme's accent: a floated window's pin is drawn in it,
    # never in the fallback blue (KCalc, unfocused now, on its inactive bar). The first build read
    # the window's QPalette, which QML cannot read into, so every mark wore the fallback blue,
    # and the read built KWin's palette mid-binding: a binding loop for every window that opened
    # (2026-11-19: twelve in a login).
    local hl hlhex fbhex
    hl=$(kreadconfig6 --file "$CONF/kdeglobals" --group "Colors:Selection" --key BackgroundNormal)
    hl=${hl:-61,174,233}
    # shellcheck disable=SC2086 # the three channels are meant to split
    hlhex=$(printf '#%02X%02X%02X' ${hl//,/ })
    fbhex="#2A6DDF"
    count_in_bar() { magick "$OUT/135-c.png" -crop "480x32+100+120" +repage -alpha off -depth 8 -format %c histogram:info:- | awk -v h="$1" 'toupper($0) ~ h { s += $1 } END { print s + 0 }'; }
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) x.onAllDesktops = true; });' 1.2
    shot "$OUT/135-c.png"
    local hits fbhits; hits=$(count_in_bar "$hlhex"); fbhits=$(count_in_bar "$fbhex")
    echo "# KCalc's floated bar: $hits px of the accent $hlhex, $fbhits of the fallback $fbhex"
    assert_true "a floated window's pin wears the scheme's accent" "$hits" -ge 4
    assert_eq "and not the fallback blue" "$fbhits" 0
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) x.onAllDesktops = false; });' 1.2
    assert_eq "the decoration reports no binding loop" "$(grep -cE 'kwin-canvas-decoration.*Binding loop' "$LOG")" 0
    # The close glyph kills the window. The click lands and the requestClose()
    # fires, but the nest's KWin cannot close a window at all - even its own
    # killWindow D-Bus is a no-op there - so the glyph's proof belongs to the
    # live session.
    skip "the nest's KWin cannot close a window; the glyphs get their proof on the live session"
    arrange >/dev/null
}
