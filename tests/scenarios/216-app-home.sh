# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="an app's home: \"Open new windows of this app here\" on a Konsole remembers its plane spot, the next Konsole that opens is put there and the camera slides to it, and forgetting it lets the next one open where KDE puts it"

# The plane spot of the newest window titled $1: real frame plus the closed camera.
plane_of() {
    kwinjs "var f = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) f = x.frameGeometry; }); if (f) print(\"AHPOS \" + Math.round(f.x) + \" \" + Math.round(f.y));" 0.3
    c state >/dev/null
    local rx ry; read -r rx ry <<<"$(grep -a "AHPOS " "$STATE/kwin.log" | tail -1 | sed 's/.*AHPOS //')"
    echo "$(awk -v r="$rx" -v v="$(sget viewx)" 'BEGIN{printf "%d", r + v}') $(awk -v r="$ry" -v v="$(sget viewy)" 'BEGIN{printf "%d", r + v}') $rx"
}

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    open_1to1
    c "placeby Konsole 3000 200 620 420"
    c state
    c "select $(eget Konsole index)"
    c "apphome set"
    c cancel >/dev/null; sleep 0.8
    run konsole --separate --nofork -p tabtitle=HomeOne -e sleep 300 >/dev/null
    sleep 4.0
    local px py rx
    read -r px py rx <<<"$(plane_of HomeOne)"
    assert_near "the new Konsole opened at the app's home on the plane" "$px" 3000 2
    assert_near "and its y" "$py" 200 2
    assert_true "and the camera slid to it, so it is on the screen (x $rx)" "${rx:-9999}" -lt 1920
    assert_true "wholly" "${rx:--1}" -ge 0

    open_1to1; c state
    c "select $(eget Konsole index)"
    c "apphome forget"
    c cancel >/dev/null; sleep 0.8
    run konsole --separate --nofork -p tabtitle=HomeTwo -e sleep 300 >/dev/null
    sleep 4.0
    read -r px py rx <<<"$(plane_of HomeTwo)"
    assert_true "forgotten: the next one opens where KDE puts it, not at the old home (plane x $px)" "$(( px < 2900 || px > 3100 ))" -eq 1
    kwinjs 'workspace.stackingOrder.forEach(function (x) { var c = String(x.caption); if (c.indexOf("HomeOne") >= 0 || c.indexOf("HomeTwo") >= 0) x.closeWindow(); });' 1.0
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key AppHomes --delete
    c reloadstate >/dev/null
    arrange >/dev/null
}
