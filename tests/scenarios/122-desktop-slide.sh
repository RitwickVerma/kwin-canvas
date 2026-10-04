# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a desktop switch with the canvas closed glides the camera across the plane: the canvas opens quietly at the old island, pans down to the new one, and closes again - the OSD card joins it when it is on"

run_scenario() {
    # shellcheck source=tests/lib.sh
    source tests/lib.sh

    arrange >/dev/null
    open_1to1
    c "newdesktop Two"
    sleep 0.5
    c state
    assert_eq "the plane has two desktops" "$(sget desktops)" 2

    # Stretch the glide so the mid-flight reads cannot miss it, and
    # switch the OSD off first: part A proves the bare slide.
    setcfg PanDuration 1500
    setcfg DesktopOsd false
    c commit
    sleep 0.3

    c "desktop 1"
    sleep 0.5
    c state
    assert_eq "the switch opens the canvas quietly" "$(sget visible)" true
    assert_eq "at the seam" "$(sget zoom)" "1.0000"
    vy=$(sget viewy)
    if awk -v y="$vy" 'BEGIN{exit !(y>0 && y<1320)}'; then
        ok "and glides instead of jumping"
    else
        fail "and glides instead of jumping"
    fi
    assert_eq "with the old island still under the eye" "$(awk -v y="$vy" 'BEGIN{print (y<1320)}')" 1

    for i in $(seq 1 30); do
        c state
        [ "$(sget visible)" = false ] && break
        sleep 0.3
    done
    c state
    assert_eq "the glide lands and closes again" "$(sget visible)" false
    assert_near "on the new island" "$(sget viewy)" 1320.0 2
    assert_near "with the camera's x where it began" "$(sget viewx)" 0.0 2

    # Part B: the same switch back, now with the OSD card on top.
    setcfg DesktopOsd true
    sleep 0.5
    c "desktop 0"
    sleep 0.5
    c state
    assert_eq "the card joins the slide" "$(sget visible)" true
    if awk -v y="$(sget viewy)" 'BEGIN{exit !(y>0 && y<1320)}'; then
        ok "the glide still runs"
    else
        fail "the glide still runs"
    fi
    for i in $(seq 1 40); do
        c state
        [ "$(sget visible)" = false ] && break
        sleep 0.3
    done
    c state
    assert_eq "and the card closes the canvas after it" "$(sget visible)" false
    assert_near "landing back on the first island" "$(sget viewy)" 0.0 2

    # Part C: the drift proof. Rapid switches must never lose the
    # camera's place - three round-trips with no settle between them,
    # then the landing must be exactly the first island's.
    c "desktop 1"
    c "desktop 0"
    c "desktop 1"
    c "desktop 0"
    sleep 1.0
    c state
    assert_eq "rapid switching never loses the place" "$(sget viewy)" "0.0"
    assert_eq "and neither x" "$(sget viewx)" "0.0"

    c "desktop 0"
    c "rmdesktop 1"
    sleep 1.0
    c state
    assert_eq "the plane is one desktop again" "$(sget desktops)" 1

    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key PanDuration --delete
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key DesktopOsd --delete
    arrange >/dev/null
}
