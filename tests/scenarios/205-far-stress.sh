# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="windows parked thousands of pixels away keep their plane coordinate through the operations the maintainer uses all day: the overview opened and cancelled, an auto fly to another window, step in, on the maintainer's layout (two stacked outputs at scale 1.25) with focus following the mouse"
WINS="KCalc Konsole sample.txt Dolphin Gwenview"
plane() { # prints "Name=x,y ..." in PLANE coordinates (real frame + the closed camera)
    kwinjs 'var o = []; workspace.stackingOrder.forEach(function (x) { var n = String(x.caption); ["KCalc","Konsole","sample.txt","Dolphin","Gwenview"].forEach(function (k) { if (n.indexOf(k) >= 0) o.push(k + "=" + x.frameGeometry.x + "," + x.frameGeometry.y); }); }); print("FSPOS " + o.join(" "));' 0.45
    c state >/dev/null
    local vx vy; vx=$(sget viewx); vy=$(sget viewy)
    grep -a "FSPOS " "$STATE/kwin.log" | tail -1 | sed 's/.*FSPOS //' | tr ' ' '\n' | sort | awk -F'[=,]' -v vx="$vx" -v vy="$vy" '{printf "%s=%.0f,%.0f ", $1, $2 + vx, $3 + vy}'
}
act() { kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) workspace.activeWindow = x; });" 0.3; }
park() { # place windows far away in REAL coordinates, canvas closed
    kwinjs 'workspace.stackingOrder.forEach(function (x) { var n = String(x.caption);
        if (n.indexOf("Dolphin") >= 0) x.frameGeometry = {x: 9000, y: 300, width: 700, height: 360};
        if (n.indexOf("Gwenview") >= 0) x.frameGeometry = {x: -7000, y: 500, width: 460, height: 420};
        if (n.indexOf("Konsole") >= 0) x.frameGeometry = {x: 200, y: 2600, width: 620, height: 420};
        if (n.indexOf("sample.txt") >= 0) x.frameGeometry = {x: 3000, y: -4000, width: 700, height: 520};
        if (n.indexOf("KCalc") >= 0) x.frameGeometry = {x: 100, y: 120, width: 480, height: 420}; });' 0.8
}
check() { # label: compare to the baseline
    local now; now=$(plane)
    if [ "$now" = "$BASE" ]; then ok "$1: every window keeps its plane coordinate"; else fail "$1: a window's plane coordinate changed. before: $BASE now: $now"; BASE=$now; fi
}
run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    c state >/dev/null
    if [ "$(sget screens)" = 2 ]; then
        run kscreen-doctor output.Virtual-0.position.0,864 output.Virtual-1.position.480,0 output.Virtual-0.scale.1.25 output.Virtual-1.scale.1.25 >/dev/null 2>&1; sleep 3
    else
        run kscreen-doctor output.Virtual-0.scale.1.25 >/dev/null 2>&1; sleep 3
    fi
    kwriteconfig6 --file "$CONF/kwinrc" --group Windows --key FocusPolicy FocusFollowsMouse
    kwriteconfig6 --file "$CONF/kwinrc" --group Windows --key DelayFocusInterval 150
    kwriteconfig6 --file "$CONF/kwinrc" --group Windows --key AutoRaise true
    kwriteconfig6 --file "$CONF/kwinrc" --group Windows --key AutoRaiseInterval 300
    kwriteconfig6 --file "$CONF/kwinrc" --group Windows --key ClickRaise false
    nq org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1; sleep 1
    setcfg SmoothZoom true
    setcfg Perf true
    arrange >/dev/null; c state >/dev/null
    park
    act KCalc; sleep 0.5
    input move 600 400; sleep 0.5
    BASE=$(plane)
    echo "# start: $BASE"
    local i
    for i in 1 2 3; do
        c open >/dev/null; sleep 1.2; c cancel >/dev/null; sleep 1.2
        check "round $i: overview opened and cancelled"
        act Konsole; sleep 1.8; act KCalc; sleep 2.2
        check "round $i: auto fly to a far window and back"
        c open >/dev/null; sleep 0.8; c enter >/dev/null; sleep 1.5
        check "round $i: overview and step in"
    done
    c cancel >/dev/null 2>&1
    echo "# end:   $(plane)"
    echo "# KWin's pulls the canvas saw: moved=$(grep -ac 'perf: moved' "$LOG") nudged=$(grep -ac 'perf: nudged' "$LOG") pulled=$(grep -ac 'perf: pulled' "$LOG"); sizes: $(grep -a 'perf: moved' "$LOG" | sed -n 's/.*moved win=\([^ ]*\) cls=[^ ]* dx=\(-\?[0-9.]*\) dy=\(-\?[0-9.]*\) open=\([01]\) quiet=\([01]\).*/\1:\2,\3(o\4q\5)/p' | cut -c1-34 | tr '\n' ' ')"
        # Put the nest back as other scenarios expect it: the scale, the layout, the focus policy.
    local k
    for k in FocusPolicy DelayFocusInterval AutoRaise AutoRaiseInterval ClickRaise; do
        kwriteconfig6 --file "$CONF/kwinrc" --group Windows --key "$k" --delete >/dev/null
    done
    setcfg Perf false
    if [ "$(sget screens)" = 2 ]; then
        run kscreen-doctor output.Virtual-0.position.0,0 output.Virtual-1.position.1920,0 output.Virtual-0.scale.1 output.Virtual-1.scale.1 >/dev/null 2>&1
    else
        run kscreen-doctor output.Virtual-0.scale.1 >/dev/null 2>&1
    fi
    sleep 2.5
    nq org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1
    arrange >/dev/null
}
