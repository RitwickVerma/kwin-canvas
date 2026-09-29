#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the backdrop: the desktop's own wallpaper on the plane, a tile per output and outward from them, its dim, and grid mode"
# How many tiles computeBackdropTiles() should lay out for one 1920x1080 output
# at REACH: the output itself, plus a ceil(virtual/cell)+2*reach grid of
# primary-screen-sized padding tiles centred on the arrangement.
tiles_for() {   # tiles_for REACH W H
    awk -v r="$1" -v w="$2" -v h="$3" 'BEGIN{ print 1 + (1 + 2 * r) * (1 + 2 * r) }'
}
run_scenario() {
    open_1to1
    c state
    local w h; read -r _ _ w h <<<"$(screenrect 0)"
    # The wallpaper reaches the screens only: one tile per output, no padding.
    setcfg BackdropReach 0
    c state
    assert_eq "one tile per output at reach 0" "$(sget backdrop)" 1
    # And outward from them, at primary-screen steps, so a fit view is
    # wallpaper rather than void. Each padding tile wears the nearest output's
    # wallpaper.
    setcfg BackdropReach 1
    c state
    assert_eq "reach 1 pads the plane by one screen each way" "$(sget backdrop)" "$(tiles_for 1 "$w" "$h")"
    setcfg BackdropReach 2
    c state
    assert_eq "reach 2 covers a fit view" "$(sget backdrop)" "$(tiles_for 2 "$w" "$h")"
    # Out of range values are clamped, not obeyed: 4 screens each way is the
    # most any view can use, and a negative number is none.
    setcfg BackdropReach 9
    c state
    assert_eq "reach is capped at 4" "$(sget backdrop)" "$(tiles_for 4 "$w" "$h")"
    setcfg BackdropReach -3
    c state
    assert_eq "a negative reach draws the screens only" "$(sget backdrop)" 1
    setcfg BackdropReach 2
    # A zoomed-out view is where the backdrop can be seen at all: at 1:1 the
    # monitor frames cover the screen exactly, and the plane beyond them is
    # behind the frames, so every setting looks the same there. 0.6 shows the
    # plane around the desk, which is what the wallpaper is for.
    c "zoom 0.6 960 540"
    # The dim: 0 is the wallpaper as the desktop shows it, 1 hides it behind
    # the ground's background so the desks and the windows are all there is.
    # Both are recorded as goldens, and the two have to differ on screen too -
    # which is what a golden alone would not say.
    setcfg BackdropDim 0
    c state
    snap backdrop-undimmed
    setcfg BackdropDim 1
    c state
    snap backdrop-dimmed
    assert_differs "the dim changes the plane" backdrop-dimmed backdrop-undimmed
    setcfg BackdropDim 0.45
    c state
    snap backdrop-wallpaper
    # Backdrop=grid is the plane of old: no wallpaper, the ground's own
    # background and the grid.
    setcfg Backdrop grid
    c state
    assert_eq "grid mode draws no wallpaper" "$(sget backdrop)" 0
    assert_eq "and the canvas is still open" "$(sget visible)" true
    snap backdrop-grid
    assert_differs "grid mode drops the wallpaper from the plane" backdrop-grid backdrop-wallpaper
    # A quiet slide at 1:1 is the desktop itself: the wallpaper is drawn
    # undimmed, so what slides is the wallpaper the desktop was showing and
    # nothing else. Hidden frames and the window pictures cover the rest.
    setcfg Backdrop wallpaper
    c state
    c home
    c cancel
    c "swipe 0 0 0.5"
    c state
    assert_eq "the slide is quiet" "$(head -1 <<<"$LAST_STATE" | grep -c 'visible=true quiet')" 1
    snap backdrop-slide
    c "swipe 0 0 cancel"
    sleep 0.4
    # Leave the nest as it was: the defaults are main.xml's, so unset them.
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Backdrop --delete
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key BackdropDim --delete
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key BackdropReach --delete
    c state
    assert_eq "the defaults are back" "$(sget backdrop)" "$(tiles_for 2 "$w" "$h")"
    arrange >/dev/null
}
