# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the small undo: in the open overview Ctrl+Z steps back the last drag or resize, one gesture at a time and newest first, before it reaches the commits; a fresh open starts with nothing to step back"

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    setcfg MovesGlide false
    open_1to1
    c state
    local ki ko kx ky ow oh
    ki=$(eget KCalc index); ko=$(eget Konsole index)
    kx=$(eget KCalc x); ky=$(eget KCalc y); ow=$(eget Konsole w); oh=$(eget Konsole h)

    c "drag $ki 300 40"; c "enddrag" >/dev/null 2>&1; sleep 0.3
    c "resize $ko 800 500"; sleep 0.6
    c state
    assert_near "the drag moved KCalc" "$(eget KCalc x)" "$((kx + 300))" 2
    assert_eq "the resize sized Konsole" "$(eget Konsole w)" 800

    c undo; sleep 0.6; c state
    assert_eq "the first undo puts Konsole's size back" "$(eget Konsole w)" "$ow"
    assert_eq "and its height" "$(eget Konsole h)" "$oh"
    assert_near "and leaves KCalc where the drag put it" "$(eget KCalc x)" "$((kx + 300))" 2

    c undo; sleep 0.6; c state
    assert_near "the second undo puts KCalc back" "$(eget KCalc x)" "$kx" 2
    assert_near "and its y" "$(eget KCalc y)" "$ky" 2

    c cancel >/dev/null; sleep 0.8
    open_1to1
    c "drag $ki 100 0"; sleep 0.3
    c cancel >/dev/null; sleep 0.8
    open_1to1; c undo; sleep 0.4; c state
    assert_near "a fresh open has no move of the last visit to step back" "$(eget KCalc x)" "$kx" 2
    c cancel >/dev/null; sleep 0.6
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key MovesGlide --delete
    c state >/dev/null
    arrange >/dev/null
}
