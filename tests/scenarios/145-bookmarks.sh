# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="bookmarks: a saved view is flown back to exactly (place and zoom), an empty slot does nothing, and the slots survive in the config"
settle() { # wait for the camera to stop flying
    local i
    for i in $(seq 1 25); do c state; [ "$(sget cam)" = "-" ] && return; sleep 0.2; done
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom true
    open_1to1
    c "zoom 0.5 960 540"; settle
    local x1 y1 z1; x1=$(sget viewx); y1=$(sget viewy); z1=$(sget zoom)
    c "bookmark set 3"; c state
    assert_eq "one bookmark is held" "$(sget bookmarks)" 1
    # Somewhere else, at another zoom.
    c "zoom 0.25 400 300"; settle
    c "panpx 500 200"
    c state
    assert_true "the camera has left the bookmark" "$(sget zoom)" != "$z1"
    c "bookmark go 3"; settle
    assert_near "the flight lands on the bookmark's zoom" "$(sget zoom)" "$z1" 0.01
    assert_near "and its x" "$(sget viewx)" "$x1" 2
    assert_near "and its y" "$(sget viewy)" "$y1" 2
    # An empty slot moves nothing.
    local vx; vx=$(sget viewx)
    c "bookmark go 7"; settle
    assert_near "an empty slot leaves the camera where it is" "$(sget viewx)" "$vx" 0.5
    # The keys themselves: Ctrl+2 saves, Alt+2 flies back. The plugin stands
    # down so the keys reach the canvas (the plugin's own scenario is 85).
    if have_input; then
        setcfg Passthrough false
        c "zoom 0.4 700 400"; settle
        local x2 z2; x2=$(sget viewx); z2=$(sget zoom)
        printf 'key leftctrl down\nkey 2\nkey leftctrl up\n' | input
        sleep 0.4; c state
        assert_eq "Ctrl+2 saved a second slot" "$(sget bookmarks)" 2
        c "zoom 0.8 200 200"; settle
        printf 'key leftalt down\nkey 2\nkey leftalt up\n' | input
        sleep 0.4; settle
        assert_near "Alt+2 flies back to the zoom" "$(sget zoom)" "$z2" 0.01
        assert_near "and to the place" "$(sget viewx)" "$x2" 2
        setcfg Passthrough true
    fi
    # The slot is in the config, so a restart keeps it.
    assert_true "the slots are written to the config" "$(kreadconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Bookmarks)" != ""
    # Leave the nest as it was.
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Bookmarks --delete
    setcfg SmoothZoom false
    c cancel
    c state
    arrange >/dev/null
}
