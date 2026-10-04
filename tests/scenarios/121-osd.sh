# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the canvas's own desktop OSD: a switch brings up a glass card over the real desktop, and it fades without touching a window"

run_scenario() {
    source tests/lib.sh

    region_rmse() {   # before after region
        magick "$1" -crop "$3" +repage "$OUT/osd-a.png"
        magick "$2" -crop "$3" +repage "$OUT/osd-b.png"
        { magick compare -metric RMSE "$OUT/osd-a.png" "$OUT/osd-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
    }
    changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }

    arrange
    if ! have_input; then
        skip "fakeinput not built (make tools)"
        return
    fi

    setcfg DesktopOsdMs 2500
    shot "$OUT/osd-pre.png"

    c "newdesktop Two"
    sleep 0.5
    c state
    assert_eq "the plane has two desktops" "$(sget desktops)" 2

    c "desktop 1"
    sleep 0.8
    c state
    assert_eq "the switch quietly opened the seam" "$(sget visible)" true
    assert_eq "at 1:1" "$(sget zoom)" "1.0000"
    assert_eq "quietly" "$(head -1 <<<"$LAST_STATE" | grep -c ' quiet')" 1

    shot "$OUT/osd-on.png"
    for _ in $(seq 1 30); do
        c state
        [ "$(sget visible)" = false ] && break
        sleep 0.3
    done
    assert_eq "the card faded and the seam closed" "$(sget visible)" false

    shot "$OUT/osd-off.png"
    assert_true "the card stood over the empty desktop" "$(changed "$(region_rmse "$OUT/osd-on.png" "$OUT/osd-off.png" "240x80+840+190")")"
    assert_true "the switch happened" "$(changed "$(region_rmse "$OUT/osd-pre.png" "$OUT/osd-off.png" "200x100+800+100")")"
    assert_eq "the quiet close wrote no geometry" "$(eget KCalc fx)" 100
    assert_eq "or moved its frame" "$(eget KCalc fy)" 120

    # the overworld variant: the fly and the card
    open_1to1
    c "zoom 0.5 960 540"
    c "desktop 0"
    sleep 0.5
    c state
    assert_eq "the fly landed on the first island" "$(sget viewy)" "0.0"
    c cancel

    # cleanup: the extra desktop goes away
    c "desktop 0"
    c "rmdesktop 1"
    sleep 1.0
    c state
    assert_eq "the extra desktop is gone" "$(sget desktops)" 1

    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key DesktopOsdMs --delete
    arrange
}
