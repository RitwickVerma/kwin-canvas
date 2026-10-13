# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a window that was dragged earlier still glides when arrange moves it: the drag's bookkeeping ends with the drag"
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    open_1to1
    local k w d; k=$(eget KCalc index); w=$(eget sample.txt index); d=$(eget Dolphin index)
    c "select $k"; c "selectadd $w"; c "selectadd $d"
    c "arrange cascade"
    c state
    assert_eq "never dragged: nothing is held back from the glide" "$(sget dragraw)" 0
    # A drag through the whole path (begin, move, release): the drag's
    # bookkeeping must be gone with it, or animateEntry skips those windows
    # for good and arrange, tidy and undo move them in a cut.
    c "cdrag 0 40 40"
    c state
    assert_eq "released: the drag holds no window" "$(sget dragraw)" 0
    setcfg MovesGlide false
    c cancel
    c state
}
