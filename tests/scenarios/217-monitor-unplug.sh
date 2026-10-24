# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="two outputs: KWin 6.8 moves a lost monitor's windows onto the one left with their layout kept and puts them back when the monitor returns, except a window the hand moved meanwhile; the canvas's frame authority must take all of it as KWin's rescue and leave it alone (the canvas adds nothing here: a group rescue of its own measured identical and was dropped)"

real_of() { # CAPTION -> "x y"
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) print(\"MUPOS \" + Math.round(x.frameGeometry.x) + \" \" + Math.round(x.frameGeometry.y)); });" 0.3
    grep -a "MUPOS " "$STATE/kwin.log" | tail -1 | sed 's/.*MUPOS //'
}

run_scenario() {
    source tests/lib.sh
    c state >/dev/null
    if [ "$(sget screens)" != 2 ]; then skip "needs two outputs (NEST_OUTPUTS=2)"; return; fi
    arrange >/dev/null
    local r1x r1y r1w r1h; read -r r1x r1y r1w r1h <<<"$(screenrect 1)"
    # Two windows on the second monitor, 400 px apart, and the pointer on the first.
    kwinjs "workspace.stackingOrder.forEach(function (x) { var c = String(x.caption);
        if (c.indexOf(\"Konsole\") >= 0) x.frameGeometry = {x: $((r1x + 200)), y: 150, width: 620, height: 420};
        if (c.indexOf(\"KCalc\") >= 0) x.frameGeometry = {x: $((r1x + 600)), y: 500, width: 480, height: 420}; });" 0.6
    if have_input; then input <<<"move 600 500" >/dev/null 2>&1; fi
    local ko kc; ko=$(real_of Konsole); kc=$(real_of KCalc)

    run kscreen-doctor output.Virtual-1.disable >/dev/null 2>&1; sleep 3
    local ax ay bx by; read -r ax ay <<<"$(real_of Konsole)"; read -r bx by <<<"$(real_of KCalc)"
    echo "# after the unplug: Konsole $ax,$ay KCalc $bx,$by"
    assert_true "Konsole is on the monitor left" "$ax" -lt 1920
    assert_true "KCalc too" "$bx" -lt 1920
    assert_eq "they kept their layout: KCalc 400 right of Konsole" "$((bx - ax))" 400
    assert_eq "and 350 below it" "$((by - ay))" 350

    run kscreen-doctor output.Virtual-1.enable >/dev/null 2>&1; sleep 3
    assert_eq "the monitor came back: Konsole went home" "$(real_of Konsole)" "$ko"
    assert_eq "and KCalc" "$(real_of KCalc)" "$kc"

    # Again, and this time KCalc is dragged by its title bar while the monitor is away: it stays
    # where the hand put it (a script's move would not do: KWin itself puts a window back on its
    # monitor when that returns, unless the user moved it).
    if have_input; then
        run kscreen-doctor output.Virtual-1.disable >/dev/null 2>&1; sleep 3
        read -r bx by <<<"$(real_of KCalc)"
        printf 'move %d %d\nsleep 100\ndown left\nsleep 100\nmove %d %d\nsleep 50\nmove %d %d\nsleep 100\nup left\nsleep 300\n' \
            "$((bx + 200))" "$((by + 12))" "$((bx + 100))" "$((by - 50))" "$((bx - 100))" "$((by - 150))" | input
        local mx my; read -r mx my <<<"$(real_of KCalc)"
        echo "# KCalc dragged to $mx,$my"
        run kscreen-doctor output.Virtual-1.enable >/dev/null 2>&1; sleep 3
        assert_eq "Konsole went home again" "$(real_of Konsole)" "$ko"
        assert_eq "KCalc, dragged meanwhile, stays where the hand put it" "$(real_of KCalc)" "$mx $my"
    fi
    arrange >/dev/null
}
