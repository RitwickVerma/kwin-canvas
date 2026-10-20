# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a commit that gives a window another activity while little of it is on that activity's screen leaves it where the canvas wrote it: KWin looks at the position again after the activity change and pulls a window with under 100 px of its width on the screen (or its top below the screen's last 28 px) to the edge, and the canvas writes it back, so the plane coordinates never shift; a window with plenty on the screen is left alone, and so is a window that a script insists on (207 holds the insisting one)"
# The real frames of the three windows this scenario places: "KCalc=x,y Konsole=x,y Gwenview=x,y".
frames3() {
    kwinjs 'var o = []; ["KCalc","Konsole","Gwenview"].forEach(function (k) { workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(k) >= 0) o.push(k + "=" + Math.round(x.frameGeometry.x) + "," + Math.round(x.frameGeometry.y)); }); }); print("ACTFRAMES " + o.join(" "));' 0.4
    grep -a "ACTFRAMES " "$STATE/kwin.log" | tail -1 | sed 's/.*ACTFRAMES //'
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    c state >/dev/null
    # The second activity's frame is the plane rect 2160..4080 by 0..1080. Gwenview at 4000 overlaps
    # it by 80 px, so the commit gives it that activity and writes it at x=1840, where 80 px of it
    # are on the 1920 px screen. KCalc at (3000, 1060) overlaps it by 20 px of height: written at
    # y=1060, below the last 28 px of the screen. Konsole at (2400, 200) is wholly inside.
    assert_eq "the second activity's frame sits at 2160" "$(tget 1 x)" 2160
    open_1to1
    c "placeby Gwenview 4000 300 460 420"
    c "placeby KCalc 3000 1060 480 420"
    c "placeby Konsole 2400 200 620 420"
    c commit
    sleep 1.0
    c state
    assert_eq "Gwenview went to the second activity" "$(eget Gwenview activity)" "Activity 2"
    assert_eq "KCalc went to the second activity" "$(eget KCalc activity)" "Activity 2"
    assert_eq "Konsole went to the second activity" "$(eget Konsole activity)" "Activity 2"
    assert_eq "the windows are where the commit wrote them, KWin's check after the activity change notwithstanding" \
        "$(frames3)" "KCalc=840,1060 Konsole=240,200 Gwenview=1840,300"
    # The next hold reads the windows again from KWin: they come back at the same plane spots.
    open_1to1
    assert_eq "an open afterwards reads Gwenview at 4000" "$(eget Gwenview x)" 4000
    assert_eq "and KCalc at 1060" "$(eget KCalc y)" 1060
    c cancel
    sleep 2.0
    # A script that brings a parked window (80 px of it on the screen) to 220 px on the screen is
    # indistinguishable from KWin's pull, which has the same shape: the same size, from out of reach to
    # in reach. The canvas takes it for KWin's and puts it back; only a script that insists is let be.
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Gwenview") >= 0) x.frameGeometry = {x: 1700, y: 300, width: 460, height: 420}; });' 1
    assert_eq "a move from out of reach to in reach is taken for KWin's and put back" "$(frames3 | sed 's/.*Gwenview=//')" "1840,300"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
