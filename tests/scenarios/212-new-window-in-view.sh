# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a new window that a script puts back at a spot off every monitor as it opens (Remember Window Positions does this with a spot from another day) is brought to the middle of the monitor under the pointer; a new window KWin places on the screen is left where it is, and NewWindowsInView off leaves the far one far"

# The real frame of the window titled $1: "x y w".
frame_of() {
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) print(\"NWF \" + Math.round(x.frameGeometry.x) + \" \" + Math.round(x.frameGeometry.y) + \" \" + Math.round(x.frameGeometry.width)); });" 0.3
    grep -a "NWF " "$STATE/kwin.log" | tail -1 | sed 's/.*NWF //'
}
# A script that sends every new window whose title holds $1 to (9000, 400) the moment it appears.
# It stays loaded for 4 s (kwinjs unloads a script after its settle time), in the background
# while the window is launched; the caller waits it out before the next kwinjs.
park_on_open() {
    kwinjs "workspace.windowAdded.connect(function (w) { var go = function () { if (String(w.caption).indexOf(\"$1\") >= 0 && w.frameGeometry.x < 5000) w.frameGeometry = {x: 9000, y: 400, width: w.frameGeometry.width, height: w.frameGeometry.height}; }; go(); w.captionChanged.connect(go); });" 4 &
    sleep 0.6
}

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg Verbose true
    c state >/dev/null
    if have_input; then input <<<"move 960 540" >/dev/null 2>&1; fi
    local x y w

    park_on_open "FarAway"
    run konsole --separate --nofork -p tabtitle=FarAway -e sleep 300 >/dev/null
    wait; sleep 0.5
    read -r x y w <<<"$(frame_of FarAway)"
    echo "# FarAway at $x,$y width $w"
    assert_true "the far new window was brought onto the screen (x=$x)" "${x:-9000}" -lt 1920
    assert_true "and onto it whole" "${x:-0}" -ge 0
    assert_eq "the canvas did it" "$(grep -ac 'newwindow: .*FarAway.*off every monitor' "$LOG")" 1

    run konsole --separate --nofork -p tabtitle=OnScreen -e sleep 300 >/dev/null
    sleep 2.0
    local x0; read -r x0 _ _ <<<"$(frame_of OnScreen)"
    sleep 1.5
    local x1; read -r x1 _ _ <<<"$(frame_of OnScreen)"
    assert_eq "a new window KWin placed on the screen is left where it is" "$x1" "$x0"

    setcfg NewWindowsInView false
    park_on_open "StaysFar"
    run konsole --separate --nofork -p tabtitle=StaysFar -e sleep 300 >/dev/null
    wait; sleep 0.5
    read -r x _ _ <<<"$(frame_of StaysFar)"
    assert_eq "NewWindowsInView off leaves it far" "$x" 9000

    kwinjs 'workspace.stackingOrder.forEach(function (x) { var c = String(x.caption); if (c.indexOf("FarAway") >= 0 || c.indexOf("OnScreen") >= 0 || c.indexOf("StaysFar") >= 0) x.closeWindow(); });' 1.0
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key NewWindowsInView --delete
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Verbose --delete
    c state >/dev/null
    arrange >/dev/null
}
