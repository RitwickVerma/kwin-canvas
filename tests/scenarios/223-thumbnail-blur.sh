# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="with a blur effect on, the canvas's window pictures have its blur behind them (a thumbnail is drawn past KWin's effects, so a translucent window showed the plane sharp behind it): the state line names the windows Better Blur DX's force blur takes, a translucent window shows the wallpaper blurred through it, an opaque one is the same pixels as before, and ThumbnailBlur off draws none (the class list and asked-for regions are the unit tests')"

blur() { c state >/dev/null; grep -o ' blur=[^ ]*' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2; }
# RMSE between the same region of two screenshots.
region_rmse() {
    magick "$1" -crop "$3" +repage "$OUT/tb-a.png"; magick "$2" -crop "$3" +repage "$OUT/tb-b.png"
    { magick compare -metric RMSE "$OUT/tb-a.png" "$OUT/tb-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}
opacity_of() {
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) { x.opacity = $2; print(\"TBOPACITY \" + x.opacity); } });"
    grep -a "TBOPACITY " "$STATE/kwin.log" | tail -1 | sed 's/.*TBOPACITY //'
}

run_scenario() {
    source tests/lib.sh
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "the pass-through plugin is not loaded (make plugin)"; return
    fi
    # Better Blur DX forcing blur on every window: an empty list it blurs all but.
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-better-blur-dx --key BlurMatching false
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-better-blur-dx --key WindowClasses ""
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-better-blur-dx --key BlurStrength 12
    if [ "$(nq org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect better_blur_dx 2>/dev/null)" != true ] \
        && [ "$(nq org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded better_blur_dx 2>/dev/null)" != true ]; then
        kwriteconfig6 --file "$CONF/kwinrc" --group Effect-better-blur-dx --key BlurMatching --delete
        kwriteconfig6 --file "$CONF/kwinrc" --group Effect-better-blur-dx --key WindowClasses --delete
        kwriteconfig6 --file "$CONF/kwinrc" --group Effect-better-blur-dx --key BlurStrength --delete
        skip "Better Blur DX (better_blur_dx) is not installed or not built for this KWin"; return
    fi
    arrange >/dev/null
    setcfg SmoothZoom false
    # KCalc half see-through over the wallpaper's sun, whose sharp edge is what a blur softens
    # (the rest of the fixture wallpaper is a smooth gradient, which blurs to itself): the two
    # windows that stand there moved off the screen first.
    open_1to1
    c "placeby Gwenview 2400 120"; c "placeby sample.txt 2400 700"; c "placeby KCalc 1066 92"
    sleep 0.6; c commit; c "activate KCalc"; sleep 0.6
    assert_eq "KCalc is half see-through" "$(opacity_of KCalc 0.5)" 0.5
    # A thumbnail is redrawn when its window is damaged, and an opacity change alone is not:
    # a focus there and back repaints the decoration.
    c "activate Konsole"; sleep 0.3; c "activate KCalc"; sleep 0.6
    open_1to1; sleep 0.6; c state
    local line; line=$(blur)
    echo "# blur=$line"
    assert_true "every window is blurred whole ($line)" "$(tr ',' '\n' <<<"$line" | grep -cv '^1$')" -eq 0
    shot "$OUT/tb-blur.png" >/dev/null
    c cancel >/dev/null; sleep 0.6

    setcfg ThumbnailBlur false
    open_1to1; sleep 0.6; c state
    assert_eq "ThumbnailBlur off: no blur" "$(blur)" off
    shot "$OUT/tb-sharp.png" >/dev/null
    c cancel >/dev/null; sleep 0.6

    # The sun (centre 1306,302, radius 120) under KCalc, clear of every other window; Konsole's
    # frame at (100, 600) 620x420 (arrange) is opaque.
    local d
    d=$(region_rmse "$OUT/tb-blur.png" "$OUT/tb-sharp.png" "260x260+1176+172")
    assert_true "the translucent window shows a different plane through it (rmse $d)" "$(awk -v d="${d:-0}" 'BEGIN{print (d > 0.01)}')" -eq 1
    # And it is the wallpaper blurred: where the sun's edge crosses KCalc's display, a flat strip
    # of the window, the sharpest step between neighbouring pixels is far softer.
    local eb es
    eb=$(magick "$OUT/tb-blur.png" -crop 120x30+1150+215 +repage -colorspace gray -morphology edge diamond:1 -format '%[fx:maxima]' info:)
    es=$(magick "$OUT/tb-sharp.png" -crop 120x30+1150+215 +repage -colorspace gray -morphology edge diamond:1 -format '%[fx:maxima]' info:)
    assert_true "and it is the wallpaper blurred: the sun's edge softer ($eb < half of $es)" "$(awk -v b="$eb" -v s="$es" 'BEGIN{print (b < s / 2)}')" -eq 1
    d=$(region_rmse "$OUT/tb-blur.png" "$OUT/tb-sharp.png" "300x200+200+700")
    assert_true "an opaque window is the same pixels (rmse $d)" "$(awk -v d="${d:-1}" 'BEGIN{print (d < 0.004)}')" -eq 1

    opacity_of KCalc 1 >/dev/null
    nq org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect better_blur_dx >/dev/null 2>&1
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key ThumbnailBlur --delete
    for k in BlurMatching WindowClasses BlurStrength; do kwriteconfig6 --file "$CONF/kwinrc" --group Effect-better-blur-dx --key "$k" --delete; done
    c state >/dev/null
    arrange >/dev/null
}
