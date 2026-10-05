# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

scenario_desc="the plane in perspective: the 1:1 seam never tilts, zooming out does, a drag through the tilt lands where it was put, and the fidelity ladder flattens it under load"

run_scenario() {
    source tests/lib.sh

    region_rmse() {
        magick "$1" -crop "$3" +repage "$OUT/d3-a.png"
        magick "$2" -crop "$3" +repage "$OUT/d3-b.png"
        { magick compare -metric RMSE "$OUT/d3-a.png" "$OUT/d3-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
    }
    changed() {
        awk -v m="$1" 'BEGIN{print (m>0.005)}'
    }

    arrange >/dev/null
    open_1to1
    sleep 0.5

    # The seam: at 1:1 the world is the location, and the location never
    # tilts - the scene must be pixel-identical with the 3D on and off.
    shot "$OUT/d3-seam-on.png"
    setcfg Depth3D false
    sleep 0.5
    shot "$OUT/d3-seam-off.png"
    assert_eq "the seam never tilts" "$(changed "$(region_rmse "$OUT/d3-seam-on.png" "$OUT/d3-seam-off.png" "1800x1000+60+40")")" 0
    setcfg Depth3D true

    # The tilt: zooming out tips the camera back, so the picture changes.
    c "zoom 0.5 960 540"
    sleep 1
    shot "$OUT/d3-tilt-on.png"
    setcfg Depth3D false
    sleep 0.5
    shot "$OUT/d3-tilt-off.png"
    assert_eq "zooming out tilts the plane" "$(changed "$(region_rmse "$OUT/d3-tilt-on.png" "$OUT/d3-tilt-off.png" "1800x1000+60+40")")" 1
    setcfg Depth3D true
    sleep 0.5

    # The input: a drag on the ground still lands where the flat math puts it.
    # (1600,900) is open ground - canvas (2240,1260) - clear of every
    # fixture, so the press can never hit a window body and move a window
    # instead of the camera.
    c state
    assert_eq "the tilted view holds" "$(sget viewx)" "-960.0"
    { printf 'move 1600 900\nsleep 300\ndown left\nsleep 200\nglide 1800 900 30 400\nsleep 200\nup left\n'; } | input >/dev/null 2>&1
    sleep 1
    c state
    assert_near "a drag through the tilt lands where it was put" "$(sget viewx)" -1360.0 10
    assert_near "and neither axis skids" "$(sget viewy)" -540.0 10

    # The ladder: minimal fidelity and below flatten the world even at zoom.
    setcfg CpuBare 0
    sleep 2.6
    c state
    assert_eq "the ladder is bare" "$(sget ql)" 3
    shot "$OUT/d3-bare-on.png"
    setcfg Depth3D false
    sleep 0.5
    shot "$OUT/d3-bare-off.png"
    assert_eq "minimal fidelity flattens the tilt" "$(changed "$(region_rmse "$OUT/d3-bare-on.png" "$OUT/d3-bare-off.png" "1800x1000+60+40")")" 0

    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key CpuBare --delete
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Depth3D --delete
    c cancel
    arrange >/dev/null
}
