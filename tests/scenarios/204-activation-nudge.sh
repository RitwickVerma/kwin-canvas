# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="KWin moves a window toward the screen when it is activated (top edge to y=0, left edge past the right edge minus 100 px back to that line); the canvas undoes that, so an auto fly to a partly or wholly off-screen window, an activation in the open overview and a focus-follows-mouse hover change no window's plane coordinate"
# plane(): every window's plane coordinate while the canvas is closed: its real frame plus the camera.
plane() {
    kwinjs 'var o = []; workspace.stackingOrder.forEach(function (x) { var n = String(x.caption); ["KCalc","Konsole","sample.txt","Dolphin","Gwenview"].forEach(function (k) { if (n.indexOf(k) >= 0) o.push(k + "=" + x.frameGeometry.x + "," + x.frameGeometry.y); }); }); print("NDGPOS " + o.join(" "));' 0.45
    c state >/dev/null
    local vx vy; vx=$(sget viewx); vy=$(sget viewy)
    grep -a "NDGPOS " "$STATE/kwin.log" | tail -1 | sed 's/.*NDGPOS //' | tr ' ' '\n' | sort | awk -F'[=,]' -v vx="$vx" -v vy="$vy" '{printf "%s=%.1f,%.1f ", $1, $2 + vx, $3 + vy}'
}
activate() { kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) workspace.activeWindow = x; });" 0.3; }
put() { kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"KCalc\") >= 0) x.frameGeometry = {x: $1, y: $2, width: 480, height: 420}; });" 0.5; }
kcalc_inside() { # is KCalc wholly on the screen now?
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) { var g = x.frameGeometry; print("NDGIN " + (g.x >= 0 && g.y >= 0 && g.x + g.width <= workspace.virtualScreenSize.width && g.y + g.height <= workspace.virtualScreenSize.height ? "yes" : "no " + g.x + "," + g.y)); } });' 0.4
    grep -a "NDGIN " "$STATE/kwin.log" | tail -1 | sed 's/.*NDGIN //'
}
run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    kwriteconfig6 --file "$CONF/kwinrc" --group Windows --key FocusPolicy FocusFollowsMouse
    kwriteconfig6 --file "$CONF/kwinrc" --group Windows --key DelayFocusInterval 150
    nq org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1; sleep 1
    setcfg SmoothZoom false
    arrange >/dev/null
    c state >/dev/null
    local sw; read -r _ _ sw _ <<<"$(screenrect 0)"
    local spec name x y before after
    # The fly: a window above the screen's top edge, one wholly past its right edge.
    for spec in "top-edge-off 300 -60" "wholly-off-right $((sw + 60)) 250"; do
        set -- $spec; name=$1; x=$2; y=$3
        arrange >/dev/null
        put "$x" "$y"
        input move 1000 700; sleep 0.4
        before=$(plane)
        activate Konsole; sleep 1.8
        activate KCalc; sleep 2.4
        after=$(plane)
        assert_eq "$name: an auto fly to it changed no window's plane coordinate" "$after" "$(awk -v b="$before" 'BEGIN{print b}')"
        assert_eq "$name: and it ended wholly on the screen" "$(kcalc_inside)" yes
    done
    # The open overview: an activation there must not move the entry either.
    arrange >/dev/null
    put 300 -60
    input move 1000 700; sleep 0.4
    c open >/dev/null; sleep 0.9; c state >/dev/null
    local ex ey; ex=$(eget KCalc x); ey=$(eget KCalc y)
    activate KCalc; sleep 1.2; c state >/dev/null
    assert_eq "overview: activating a window above the screen leaves its plane spot" "$(eget KCalc x),$(eget KCalc y)" "$ex,$ey"
    c cancel >/dev/null; sleep 0.8
    # Focus follows the pointer: resting on the part of a window that is on the screen.
    arrange >/dev/null
    put 600 -60
    input move 1000 700; sleep 0.5
    before=$(plane)
    input move 800 120; sleep 3
    after=$(plane)
    assert_eq "hover: focus-follows-mouse activating a window above the screen moved no window's plane coordinate" "$after" "$(awk -v b="$before" 'BEGIN{print b}')"
    kwriteconfig6 --file "$CONF/kwinrc" --group Windows --key FocusPolicy --delete >/dev/null
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
