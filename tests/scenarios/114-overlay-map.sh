# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the map is one map: the overlay wears the desks and a chip per cluster, and a chip flies the camera to fit its cluster"

region_rmse() {   # before after region
    magick "$1" -crop "$3" +repage "$OUT/om-a.png"
    magick "$2" -crop "$3" +repage "$OUT/om-b.png"
    { magick compare -metric RMSE "$OUT/om-a.png" "$OUT/om-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}

changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }

run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null

    # Two clusters: the three near fixtures, and a pair beyond Activity 2's
    # frame - Gwenview and Dolphin at (4000,300)/(4400,350). The far pair is
    # the chip's destination: the camera fits it at 0.75 (the cap that keeps
    # the overlay up), centred on the pair.
    open_1to1
    c "placeby Gwenview 4000 300 460 420"
    c "placeby Dolphin 4400 350 700 360"
    c commit
    sleep 0.4
    c state
    assert_eq "the plane holds two clusters" "$(sget clusters)" 2

    # The map geometry: the world is the two frames (1920x1080 at (0,0) and
    # (2160,0)) plus the windows out to x=5100. The overlay is the glass
    # card at (249.6,140.4,1420.8,799.2): sc = 1408.8/5100, ox = 6,
    # oy = (799.2 - 1080*sc)/2. The far cluster's centroid is (4490,520) -
    # the mean of the members' centres.
    local sx sy cx cy wx wy
    sx=$(awk 'BEGIN{printf "%d\n", 249.6 + (1420.8 - 5100 * (1408.8 / 5100)) / 2 + 4490 * (1408.8 / 5100)}')
    sy=$(awk 'BEGIN{printf "%d\n", 140.4 + (799.2 - 1080 * (1408.8 / 5100)) / 2 + 520 * (1408.8 / 5100)}')
    cx=$(awk -v s="$sx" 'BEGIN{print int(s + 8)}')   # the chip's east edge, inside the circle
    cy=$(awk -v s="$sy" 'BEGIN{print int(s)}')
    wx=$(awk 'BEGIN{print int(249.6 + (1420.8 - 5100 * (1408.8 / 5100)) / 2 + 2240 * (1408.8 / 5100))}')   # inside Activity 2's frame
    wy=$(awk 'BEGIN{print int(140.4 + (799.2 - 1080 * (1408.8 / 5100)) / 2 + 40)}')

    # The real desktop, then the hold's overlay: the desks and the chip are
    # what the map brings to the screen.
    shot "$OUT/om-pre.png" >/dev/null
    { printf 'down back\nsleep 12000\nup back\n'; } | input &
    local holdpid=$!
    sleep 1.2
    c "zoom 0.6 960 540"
    sleep 1.2
    c state
    assert_eq "the overlay is up" "$(sget map)" "overlay"
    shot "$OUT/om-map.png" >/dev/null

    local b1 b2
    b1=$(awk -v x="$cx" -v y="$cy" 'BEGIN{printf "%dx%d+%d+%d\n", 10, 10, x - 5, y - 5}')
    b2=$(awk -v x="$wx" -v y="$wy" 'BEGIN{printf "%dx%d+%d+%d\n", 10, 10, x - 5, y - 5}')
    assert_eq "the far cluster's chip is on the map" \
        "$(changed "$(region_rmse "$OUT/om-pre.png" "$OUT/om-map.png" "$b1")")" 1
    assert_eq "and the desks are" \
        "$(changed "$(region_rmse "$OUT/om-pre.png" "$OUT/om-map.png" "$b2")")" 1

    # The chip flies: the camera fits the far pair, centred on it, keeping
    # the map up. The bounds are (4000,300,1100,420): the fit would be 1.67,
    # so the 0.75 cap takes it.
    input move "$sx" "$sy"
    sleep 0.3
    input click
    local i
    for i in $(seq 1 20); do
        c state
        [ "$(sget zoom)" = "0.7500" ] && break
        sleep 0.2
    done
    sleep 0.4
    c state
    assert_eq "the camera fit the cluster" "$(sget zoom)" "0.7500"
    assert_near "centred on it" "$(sget viewx)" "3270.0" 3
    assert_near "vertically too" "$(sget viewy)" "-210.0" 3

    # The release lands the location the chip flew to: the commit writes
    # the viewport with the canvas point under the screen centre kept, so
    # at 1:1 the cluster's centre (4550,510) stays under the centre:
    # view = (4550-960, 510-540) = (3590,-30).
    kill "$holdpid" 2>/dev/null
    for i in $(seq 1 20); do
        c state
        [ "$(sget visible)" = false ] && break
        sleep 0.2
    done
    sleep 0.4
    c state
    assert_eq "the release lands the location" "$(sget visible)" false
    assert_near "at the cluster" "$(sget viewx)" "3590.0" 3
    assert_near "its centre kept" "$(sget viewy)" "-30.0" 3
    arrange >/dev/null
}
