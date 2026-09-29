# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the backdrop: the exact wallpaper on the desks, its blurred and dimmed continuation beyond them with the grid over it, and grid mode"
run_scenario() {
    open_1to1
    c state
    # The wallpaper haze: one blur layer per output, drawing the desktop
    # window itself.
    assert_eq "a blur layer per output" "$(sget backdrop)" 1
    # A zoomed-out view is where the haze can be seen at all: at 1:1 the
    # monitor frame covers the view exactly and the layer is hidden. 0.6 shows
    # the plane around the desk, which is what the wallpaper is for.
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
    # The blur knob: 0 is the wallpaper sharp beyond the desk, which reads as
    # it repeating; the default is a haze. The two have to differ on screen.
    setcfg BackdropBlur 0
    c state
    snap backdrop-sharp
    assert_differs "the blur softens the continuation" backdrop-sharp backdrop-wallpaper
    setcfg BackdropBlur 48
    # Backdrop=grid is the plane of old: no wallpaper, the ground's own
    # background and the grid.
    setcfg Backdrop grid
    c state
    assert_eq "grid mode draws no wallpaper" "$(sget backdrop)" 0
    assert_eq "and the canvas is still open" "$(sget visible)" true
    snap backdrop-grid
    assert_differs "grid mode drops the wallpaper from the plane" backdrop-grid backdrop-wallpaper
    # A quiet slide at 1:1 is the desktop itself: the frame covers the view, so
    # the haze is hidden and what slides is the wallpaper the desktop was
    # showing and nothing else.
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
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key BackdropBlur --delete
    c state
    assert_eq "the defaults are back" "$(sget backdrop)" 1
    arrange >/dev/null
}
