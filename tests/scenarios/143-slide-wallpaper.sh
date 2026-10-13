# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a wallpaper KWin.DesktopBackground cannot draw (a video, a scene) is not painted black over the real desktop during a quiet slide; a picture wallpaper keeps its frame"
setwp() { # plugin
    nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
        for (const d of desktops()) {
            d.wallpaperPlugin = '$1';
            d.currentConfigGroup = ['Wallpaper', '$1', 'General'];
        }" >/dev/null
    sleep 2.5
}
slide_patch() { # name: mean RGB of a bare patch, with a quiet slide held
    c "swipe 0 0 0.5"
    sleep 1
    shot "$OUT/$1.png" >/dev/null 2>&1
    c "swipe 0 0 cancel"
    sleep 0.6
    magick "$OUT/$1.png" -crop 200x120+1700+940 +repage -colorspace sRGB -format '%[fx:mean.r+mean.g+mean.b]' info:
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    c cancel >/dev/null 2>&1
    # The wallpaper as the closed desktop shows it, the reference.
    shot "$OUT/slide-closed.png" >/dev/null 2>&1
    local ref; ref=$(magick "$OUT/slide-closed.png" -crop 200x120+1700+940 +repage -colorspace sRGB -format '%[fx:mean.r+mean.g+mean.b]' info:)
    # A picture wallpaper: the frame draws it, nothing is black.
    local pic; pic=$(slide_patch slide-picture)
    echo "# closed=$ref picture=$pic"
    assert_eq "a picture wallpaper shows through the slide" "$(awk -v a="$ref" -v b="$pic" 'BEGIN{print (b > a * 0.5)}')" 1
    # A wallpaper that is not a picture: the same patch must not go black.
    setwp org.kde.plasma.worldmap
    shot "$OUT/slide-closed2.png" >/dev/null 2>&1
    local ref2; ref2=$(magick "$OUT/slide-closed2.png" -crop 200x120+1700+940 +repage -colorspace sRGB -format '%[fx:mean.r+mean.g+mean.b]' info:)
    local other; other=$(slide_patch slide-other)
    echo "# closed=$ref2 other=$other"
    assert_eq "a wallpaper that is not a picture is not painted black over the desktop" "$(awk -v a="$ref2" -v b="$other" 'BEGIN{print (b > a * 0.5)}')" 1
    # Leave the nest as it was.
    setwp org.kde.image
    nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
        for (const d of desktops()) {
            d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
            d.writeConfig('Image', 'file://$FIXTURES/wallpaper-1.png');
            d.writeConfig('FillMode', 2);
            d.reloadConfig();
        }" >/dev/null
    sleep 2
    arrange >/dev/null
}
