# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the frame classifier's edges: a window that insists on being moved is adopted after two reverts (no fight), a window the user is allowed to have brought in when following the activation is off, a window moved between two places on the open canvas's screen is followed, and a window KWin rescues from a monitor that goes away is adopted"
real() { # CAPTION -> "x y"
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) print(\"FAUPOS \" + x.frameGeometry.x + \" \" + x.frameGeometry.y); });" 0.35
    grep -a "FAUPOS " "$STATE/kwin.log" | tail -1 | sed 's/.*FAUPOS //'
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    setcfg Perf true
    c state >/dev/null
    local sw; read -r _ _ sw _ <<<"$(screenrect 0)"
    # 1. A script that forces a window onto the screen every time it is moved off it: reverted twice,
    # then adopted, and no more than that.
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Dolphin") >= 0) x.frameGeometry = {x: 9000, y: 300, width: 700, height: 360}; });' 0.6
    local mark; mark=$(wc -l <"$LOG")
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"Dolphin\") >= 0) { var w = x; w.frameGeometryChanged.connect(function () { var g = w.frameGeometry; if (g.x > $((sw - 100))) w.frameGeometry = {x: 200, y: 300, width: g.width, height: g.height}; }); } }); workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"Dolphin\") >= 0) x.frameGeometry = {x: 9100, y: 300, width: 700, height: 360}; });" 0.2
    # the line above is the insisting script's own write; now it keeps forcing it on screen for 3 s
    sleep 3
    local n; n=$(tail -n +"$((mark + 1))" "$LOG" | grep -ac "perf: reverted win=.*Dolphin")
    assert_true "an insisting window is reverted at most twice" "$n" -le 2
    assert_true "and is then left where it insists to be (on the screen)" "$(real Dolphin | cut -d' ' -f1)" -lt "$sw"
    arrange >/dev/null
    # 2. FollowActivation off: KDE brings the activated window in, and the canvas leaves it there.
    setcfg FollowActivation false
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) x.frameGeometry = {x: 300, y: -60, width: 480, height: 420}; if (String(x.caption).indexOf("Konsole") >= 0) workspace.activeWindow = x; });' 0.8
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) workspace.activeWindow = x; });' 1.2
    assert_eq "following off: the activated window above the screen is brought in by KDE, not put back" "$(real KCalc)" "300 0"
    setcfg FollowActivation true
    arrange >/dev/null
    # 3. The open canvas follows a window moved between two places on the screen.
    open_1to1; c state >/dev/null
    local x0; x0=$(eget KCalc x)
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) x.frameGeometry = {x: 700, y: 400, width: 480, height: 420}; });' 0.6
    c state >/dev/null
    assert_true "overview: a window moved between two places on the screen is followed (its entry moved)" "$(eget KCalc x)" -ne "$x0"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
    # 4. A monitor going away: KWin brings its windows onto the one that is left, and that is adopted.
    c state >/dev/null
    if [ "$(sget screens)" = 2 ]; then
        local r1x r1y r1w r1h; read -r r1x r1y r1w r1h <<<"$(screenrect 1)"
        kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"Konsole\") >= 0) x.frameGeometry = {x: $((r1x + 300)), y: 200, width: 620, height: 420}; });" 0.6
        run kscreen-doctor output.Virtual-1.disable >/dev/null 2>&1; sleep 2.5
        assert_true "a window on a monitor that went away is rescued onto the one that is left, and stays" "$(real Konsole | cut -d' ' -f1)" -lt "$sw"
        run kscreen-doctor output.Virtual-1.enable >/dev/null 2>&1; sleep 2.5
    fi
    setcfg Perf false
    arrange >/dev/null
}
