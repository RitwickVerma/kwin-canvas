# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the seam's ground is one picture: the wallpaper plugin draws the same grid the effect draws, a pan off the frame continues it without a seam, and the effect's grid knobs reach the wallpaper"

rmse_crop() {
    magick "$1" -crop "$3" +repage "$OUT/w1.png"
    magick "$2" -crop "$4" +repage "$OUT/w2.png"
    { magick compare -metric RMSE "$OUT/w1.png" "$OUT/w2.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}
changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }
# The two hosts render the same QML with their own antialiasing: a real
# seam reads as the same picture within two percent, not pixel-identical.
similar() { awk -v m="$1" 'BEGIN{print (m<0.02)}'; }

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    sleep 0.5

    # The nest seeds the stock image wallpaper (the frame interior is a
    # real picture). The ground wallpaper is the seam's other half, so the
    # scenario puts it up itself - the same switch a session uses.
    nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
        for (const d of desktops()) {
            d.wallpaperPlugin = 'kwin-canvas-ground';
            d.currentConfigGroup = ['Wallpaper', 'kwin-canvas-ground', 'General'];
        }" >/dev/null
    sleep 3

    # The plain-grid backdrop makes the comparison honest: both sides draw
    # the full Ground (its own background included), so the closed
    # desktop's strip and the canvas's strip are the same render or a real
    # bug. The commit publishes the ground to the wallpaper.
    setcfg Backdrop grid
    c commit
    sleep 1.2
    shot "$OUT/wa.png" >/dev/null 2>&1

    # Open at the committed view and pan: the frame tile slides away and
    # the effect's ground shows in the top-left strip. The same world
    # region in the closed shot must be the same picture - the grid's
    # phase, spacing and labels all hand in hand with the wallpaper's.
    c open
    c "pan -80 -60"
    sleep 0.8
    c state
    shot "$OUT/wb.png" >/dev/null 2>&1
    assert_eq "the ground continues across the frame's edge" "$(similar "$(rmse_crop "$OUT/wa.png" "$OUT/wb.png" "80x60+80+60" "80x60+0+0")")" 1

    # The knobs ride the same channel: a wider grid set in the effect
    # reaches the wallpaper, so the closed desktop shows it too.
    setcfg GridBase 240
    c commit
    sleep 2.5
    shot "$OUT/wc.png" >/dev/null 2>&1
    assert_eq "the wider grid reached the desktop" "$(changed "$(rmse_crop "$OUT/wa.png" "$OUT/wc.png" "80x60+80+60" "80x60+80+60")")" 1

    # And the continuity still holds at the new spacing.
    c open
    c "pan -80 -60"
    sleep 0.8
    c state
    shot "$OUT/wd.png" >/dev/null 2>&1
    assert_eq "and the seam holds at the new spacing" "$(similar "$(rmse_crop "$OUT/wc.png" "$OUT/wd.png" "80x60+80+60" "80x60+0+0")")" 1

    c cancel
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Backdrop --delete
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key GridBase --delete
    # Put the nest's stock image wallpaper back: the scenarios after this
    # one in a batch expect the fixture picture inside the frame.
    nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
        for (const d of desktops()) {
            d.wallpaperPlugin = 'org.kde.image';
            d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
            d.writeConfig('Image', 'file://$FIXTURES/wallpaper-1.png');
            d.writeConfig('FillMode', 2);
            d.reloadConfig();
        }" >/dev/null
    sleep 2
    arrange
}
