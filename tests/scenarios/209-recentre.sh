# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="kwin-canvas reset recentres a plane whose numbers drifted far from the origin: the view becomes (0, 0), every window and target moves by the same offset on the plane, a bookmark moves with them, and no real window moves; the open canvas refuses it"

# Every fixture window's real frame, "x,y" per window in a fixed order.
reals() {
    kwinjs 'var o = []; ["KCalc","sample.txt","Konsole","Dolphin","Gwenview"].forEach(function (k) { workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(k) >= 0) o.push(k + "=" + Math.round(x.frameGeometry.x) + "," + Math.round(x.frameGeometry.y)); }); }); print("RCREALS " + o.join(" "));' 0.3
    grep -a "RCREALS " "$STATE/kwin.log" | tail -1 | sed 's/.*RCREALS //'
}

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    # Drift: move the camera 250000 px away and leave it there.
    open_1to1
    c "panpx -250000 -40000" >/dev/null
    c "bookmark set 3" >/dev/null
    c enter >/dev/null; sleep 1.5
    c state
    local vx vy kx ky
    vx=$(sget viewx); vy=$(sget viewy)
    assert_true "the view drifted far from the origin ($vx)" "${vx%.*}" -gt 200000
    local before; before=$(reals)
    open_1to1; c state; kx=$(eget KCalc x); ky=$(eget KCalc y)
    # Open, it is refused.
    c recentre; c state
    assert_eq "the open canvas refuses it" "$(sget viewx)" "$vx"
    c cancel >/dev/null; sleep 0.8
    # Closed, through the CLI's command.
    c recentre; sleep 0.5; c state
    assert_near "the view is the origin" "$(sget viewx)" 0 1
    assert_near "and its y" "$(sget viewy)" 0 1
    assert_eq "no real window moved" "$(reals)" "$before"
    open_1to1; c state
    assert_near "a window moved by the same offset on the plane" "$(eget KCalc x)" "$(awk -v a="$kx" -v v="$vx" 'BEGIN{print a - v}')" 1
    assert_near "and its y" "$(eget KCalc y)" "$(awk -v a="$ky" -v v="$vy" 'BEGIN{print a - v}')" 1
    c cancel >/dev/null; sleep 0.8
    # A second recentre where the view is already the origin changes nothing.
    c recentre; c state
    assert_eq "a second reset is a no-op" "$(reals)" "$before"
    # The bookmark saved at the drifted view moved with the plane: it is the origin now.
    open_1to1
    c "panpx 500 300" >/dev/null
    c "bookmark go 3" >/dev/null; sleep 0.3; c state
    assert_near "the bookmark moved with the plane" "$(sget viewx)" 0 1
    c cancel >/dev/null; sleep 0.8
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Bookmarks --delete
    c reloadstate >/dev/null
    arrange >/dev/null
}
