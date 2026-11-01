# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="with the Rounded Corners effect on, the canvas's window pictures wear its corners (a thumbnail is drawn past KWin's effects, so it was square): a corner shows the plane behind it, the rest of the picture is the same pixels as before, an excluded window stays square (maximized, tiled and fullscreen are the unit tests'), and ThumbnailCorners off draws them all square"

corners() { c state >/dev/null; grep -o ' corners=[^ ]*' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2; }
# RMSE between the same region of two screenshots.
region_rmse() {
    magick "$1" -crop "$3" +repage "$OUT/rc-a.png"; magick "$2" -crop "$3" +repage "$OUT/rc-b.png"
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
    open_1to1; sleep 0.6; c state
    local line; line=$(corners)
    echo "# corners=$line"
    local ki gi; ki=$(eget KCalc index); gi=$(eget wallpaper.png index)
    assert_eq "KCalc wears the effect's radius" "$(tr ',' '\n' <<<"$line" | sed -n "$((ki + 1))p")" 40
    assert_eq "Gwenview, excluded, wears none" "$(tr ',' '\n' <<<"$line" | sed -n "$((gi + 1))p")" 0
    shot "$OUT/tc-round.png" >/dev/null
    c cancel >/dev/null; sleep 0.6

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

    nq org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect kwin4_effect_shapecorners >/dev/null 2>&1
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key ThumbnailCorners --delete
    kwriteconfig6 --file "$CONF/kwinrc" --group Round-Corners --key Size --delete
    for k in InactiveCornerRadius Squircleness Exclusions; do kwriteconfig6 --file "$CONF/kwinrc" --group Round-Corners --key "$k" --delete; done
    c state >/dev/null
    arrange >/dev/null
}
