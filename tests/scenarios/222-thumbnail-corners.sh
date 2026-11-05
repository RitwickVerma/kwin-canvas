# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="with the Rounded Corners effect on, the canvas's window pictures wear its corners, and a moved window's picture stays itself (a thumbnail is drawn past KWin's effects, so it was square): a corner shows the plane behind it, the rest of the picture is the same pixels as before, the cornered picture stays live, an excluded window stays square (maximized, tiled and fullscreen are the unit tests'), and ThumbnailCorners off draws them all square"

corners() { c state >/dev/null; grep -o ' corners=[^ ]*' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2; }
# RMSE between a region of one screenshot and a region of another (the same one by default).
region_rmse() {
    magick "$1" -crop "$3" +repage "$OUT/rc-a.png"; magick "$2" -crop "${4:-$3}" +repage "$OUT/rc-b.png"
    { magick compare -metric RMSE "$OUT/rc-a.png" "$OUT/rc-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}

run_scenario() {
    source tests/lib.sh
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "the pass-through plugin is not loaded (make plugin)"; return
    fi
    # The real effect, with corners large enough to measure: 40 px circles, Gwenview excluded.
    kwriteconfig6 --file "$CONF/kwinrc" --group Round-Corners --key Size 40
    kwriteconfig6 --file "$CONF/kwinrc" --group Round-Corners --key InactiveCornerRadius 40
    kwriteconfig6 --file "$CONF/kwinrc" --group Round-Corners --key Squircleness 0
    kwriteconfig6 --file "$CONF/kwinrc" --group Round-Corners --key Exclusions gwenview
    if [ "$(nq org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect kwin4_effect_shapecorners 2>/dev/null)" != true ] \
        && [ "$(nq org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded kwin4_effect_shapecorners 2>/dev/null)" != true ]; then
        skip "the Rounded Corners effect (kwin4_effect_shapecorners) is not installed or not built for this KWin"; return
    fi
    arrange >/dev/null
    setcfg SmoothZoom false
    c "activate KCalc"; sleep 0.4
    open_1to1; sleep 0.6; c state
    local line; line=$(corners)
    echo "# corners=$line"
    # The corners are cut from KWin's own thumbnail texture through the plugin's helper, not
    # through a layer per window: the same pixels below prove the helper's frame lines up.
    assert_eq "the plugin's scene helper is there" "$(grep -o ' scenehelper=[^ ]*' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2)" 1
    local ki gi; ki=$(eget KCalc index); gi=$(eget wallpaper.png index)
    assert_eq "KCalc wears the effect's radius" "$(tr ',' '\n' <<<"$line" | sed -n "$((ki + 1))p")" 40
    assert_eq "Gwenview, excluded, wears none" "$(tr ',' '\n' <<<"$line" | sed -n "$((gi + 1))p")" 0
    shot "$OUT/tc-round.png" >/dev/null
    # The picture stays live: the thumbnail item that hands over KWin's texture is not drawn
    # itself, and must still be fed. The fixture Konsole's terminal switches to its alternate
    # screen, written straight to its tty while the canvas is open, and the cornered picture
    # follows; switching back restores the screen exactly, so no later golden sees it.
    local kpid tty
    kpid=$(nq | grep -o 'org.kde.konsole-[0-9]*' | head -1); kpid=${kpid##*-}
    tty=$(for p in $(pgrep -P "${kpid:-0}"); do readlink "/proc/$p/fd/1"; done | grep -m1 '^/dev/pts/')
    if [ -n "$tty" ]; then
        printf '\033[?1049h\033[2J\033[H%s\r\n%s' "$(printf 'X%.0s' {1..46})" "$(printf 'X%.0s' {1..46})" >"$tty"; sleep 0.8
        shot "$OUT/tc-live.png" >/dev/null
        printf '\033[?1049l' >"$tty"; sleep 0.4
    fi
    # A window moved on the open canvas: its entry follows (207), and its picture must show the
    # window, not the texture shifted by the move. The frame's place in KWin's texture was read
    # from the window item's scene rect, which the item updates in its own slot after the frame
    # changes; read first, it was the old place, and the cornered picture sampled the texture
    # 200 px off until something else moved the window. A slide's landing moves every window
    # in the frame, so every landing showed the shifted pictures for its last frames.
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) x.frameGeometry = {x: 300, y: 120, width: 480, height: 420}; });' 0.5
    sleep 0.4
    shot "$OUT/tc-moved.png" >/dev/null
    c cancel >/dev/null; sleep 0.6
    # Back where the square shot below expects it.
    arrange >/dev/null

    setcfg ThumbnailCorners false
    open_1to1; sleep 0.6; c state
    assert_eq "ThumbnailCorners off: no corners" "$(corners)" off
    shot "$OUT/tc-square.png" >/dev/null
    c cancel >/dev/null; sleep 0.6

    # KCalc's frame is at (100, 120) 480x420 (arrange). Its top-left 6x6 lies outside a 40 px corner.
    local d
    d=$(region_rmse "$OUT/tc-round.png" "$OUT/tc-square.png" "6x6+101+121")
    assert_true "the rounded corner differs from the square one (rmse $d)" "$(awk -v d="${d:-0}" 'BEGIN{print (d > 0.02)}')" -eq 1
    d=$(region_rmse "$OUT/tc-round.png" "$OUT/tc-square.png" "300x200+190+230")
    assert_true "and the rest of the picture is the same pixels (rmse $d)" "$(awk -v d="${d:-1}" 'BEGIN{print (d < 0.004)}')" -eq 1
    d=$(region_rmse "$OUT/tc-round.png" "$OUT/tc-square.png" "6x6+1401+121")
    assert_true "the excluded window's corner is untouched (rmse $d)" "$(awk -v d="${d:-1}" 'BEGIN{print (d < 0.004)}')" -eq 1
    # The Konsole's terminal, at (100, 600) after arrange.
    if [ -n "$tty" ]; then
        d=$(region_rmse "$OUT/tc-round.png" "$OUT/tc-live.png" "500x360+110+610")
        assert_true "the cornered picture is live: the terminal's new screen shows in it (rmse $d)" "$(awk -v d="${d:-0}" 'BEGIN{print (d > 0.05)}')" -eq 1
    else
        skip "the fixture Konsole's terminal was not found"
    fi

    d=$(region_rmse "$OUT/tc-round.png" "$OUT/tc-moved.png" "300x200+190+230" "300x200+390+230")
    assert_true "a window moved on the open canvas shows its own picture at its new place (rmse $d)" "$(awk -v d="${d:-1}" 'BEGIN{print (d < 0.004)}')" -eq 1

    nq org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect kwin4_effect_shapecorners >/dev/null 2>&1
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key ThumbnailCorners --delete
    kwriteconfig6 --file "$CONF/kwinrc" --group Round-Corners --key Size --delete
    for k in InactiveCornerRadius Squircleness Exclusions; do kwriteconfig6 --file "$CONF/kwinrc" --group Round-Corners --key "$k" --delete; done
    c state >/dev/null
    arrange >/dev/null
}
