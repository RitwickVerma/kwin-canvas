# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the world is the map: cluster chips float on the plane, a chip flies the camera to fit its cluster, and the release lands there"

region_rmse() {   # before after region
    magick "$1" -crop "$3" +repage "$OUT/om-a.png"
    magick "$2" -crop "$3" +repage "$OUT/om-b.png"
    { magick compare -metric RMSE "$OUT/om-a.png" "$OUT/om-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}

changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }

run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    # The click lands on the chip's flat position; the 3D tilt shifts the
    # plane's rendering, so it is pinned off here (126 covers the tilt).
    setcfg Depth3D false

    # Two clusters: the five near fixtures, and a pair stacked vertically
    # beyond them - Gwenview and Dolphin at (2200,300)/(2200,800). The far
    # pair's chip floats at its centroid (2490,745), which sits in the gap
    # between the two windows, uncovered. The chip flies the camera to fit
    # the pair's bounds (2200,300,700,860) at the 0.75 cap, centred on them.
    open_1to1
    c "placeby Gwenview 2200 300 460 420"
    c "placeby Dolphin 2200 800 700 360"
    c commit
    sleep 0.4
    c state
    assert_eq "the plane holds two clusters" "$(sget clusters)" 2
    c "verbose on"
    # The chip's screen spot: hold at zoom 0.5 from the anchor leaves the
    # view at (-960,-540); the chip centre is ((2490+960)*0.5, (745+540)*0.5).
    local sx sy hx hy
    sx=1725
    sy=642
    hx=940   # inside the hint strip at the bottom centre
    hy=1015

    # The real desktop, then the hold's world: the chip and the hint strip
    # are what the world as the map brings to the screen.
    shot "$OUT/om-pre.png" >/dev/null
    { printf 'move 1700 900\nsleep 60\ndown back\nsleep 3000\nmove 1725 642\nsleep 2500\nclick\nsleep 3000\nup back\n'; } | input &
    local holdpid=$!
    sleep 1.2
    c "zoom 0.5 960 540"
    sleep 0.2
    c state
    sleep 1.0
    c state
    assert_eq "the world is the map - no card" "$(sget map)" "-"
    shot "$OUT/om-map.png" >/dev/null

    local b1 b2
    b1=$(awk -v x="$sx" -v y="$sy" 'BEGIN{printf "%dx%d+%d+%d\n", 10, 10, x - 5, y - 5}')
    b2=$(awk -v x="$hx" -v y="$hy" 'BEGIN{printf "%dx%d+%d+%d\n", 20, 20, x - 10, y - 10}')
    assert_eq "the far cluster's chip floats on the plane" \
        "$(changed "$(region_rmse "$OUT/om-pre.png" "$OUT/om-map.png" "$b1")")" 1
    assert_eq "and the hint strip teaches the grasp" \
        "$(changed "$(region_rmse "$OUT/om-pre.png" "$OUT/om-map.png" "$b2")")" 1

    # The chip flies: the camera fits the far pair, centred on it, keeping
    # the world up. The bounds are (2200,300,700,860): the fit would be
    # 1080/908, so the 0.75 cap takes it. Centre (2550,730) ->
    # view (2550-1280, 730-720) = (1270,10).
    input move "$sx" "$sy"
    sleep 0.3
    c state
    local i
    for i in $(seq 1 20); do
        c state
        [ "$(sget zoom)" = "0.7500" ] && break
        sleep 0.2
    done
    sleep 0.4
    c state
    assert_eq "the camera fit the cluster" "$(sget zoom)" "0.7500"
    assert_near "centred on it" "$(sget viewx)" "1270.0" 3
    assert_near "vertically too" "$(sget viewy)" "10.0" 3

    # The release lands the location the chip flew to: the commit writes
    # the viewport with the canvas point under the screen centre kept, so
    # at 1:1 the cluster's centre (2550,730) stays under the centre:
    # view = (2550-960, 730-540) = (1590,190).
    kill "$holdpid" 2>/dev/null
    for i in $(seq 1 20); do
        c state
        [ "$(sget visible)" = false ] && break
        sleep 0.2
    done
    sleep 0.4
    c state
    assert_eq "the release lands the location" "$(sget visible)" false
    assert_near "at the cluster" "$(sget viewx)" "1590.0" 3
    assert_near "its centre kept" "$(sget viewy)" "190.0" 3
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Depth3D --delete
    arrange >/dev/null
}
