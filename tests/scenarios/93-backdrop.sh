# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the backdrop: the exact wallpaper on the desks, its blurred and dimmed continuation beyond them with the grid over it, and grid mode"
run_scenario() {
    open_1to1
    c state
    # The wallpaper haze: one blur layer per output, drawing the desktop
    # window itself.
    assert_eq "a blur layer per output" "$(sget backdrop)" 1
    # A video or scene wallpaper exists only as the desktop window's texture:
    # the zoomed-out view draws that window, so it must have a handle.
    assert_eq "the desktop window has a handle for the zoomed-out view" "$(sget deskwin)" 1
    # A zoomed-out view is where the haze can be seen at all: at 1:1 the
    # monitor frame covers the view exactly and the layer is hidden. 0.6 shows
    # the plane around the desk, which is what the wallpaper is for.
    c "zoom 0.6 960 540"
    # The wallpaper rides through raw below 1:1: no blur, no dim, no tint.
    # BackdropDim and BackdropBlur are inert knobs now, kept so an old
    # config still loads; the scenario pins that they change nothing, which
    # a golden alone would not say.
    c state
    snap backdrop-wallpaper
    setcfg BackdropDim 1
    setcfg BackdropBlur 0
    c state
    snap backdrop-knobs
    assert_same "the dim and blur knobs are inert" backdrop-wallpaper backdrop-knobs
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
