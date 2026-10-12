# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="cursor-anchored zoom, pan, and zoom to fit"
run_scenario() {
    open_1to1
    c "zoom 0.4 960 540"
    assert_near "zoom" "$(sget zoom)" 0.4 0.001
    assert_near "view x after zoom" "$(sget viewx)" -1440 1
    assert_near "view y after zoom" "$(sget viewy)" -810 1
    c "pan -300 -200"
    # The pan is the torch now: the same drag sweeps more plane the
    # further from home the view sits (the tan acceleration).
    assert_near "view x after pan" "$(sget viewx)" -358.2 1
    assert_near "view y after pan" "$(sget viewy)" -310.7 1
    snap zoom-pan
    c extents
    assert_true "fit zoom below 1" "$(awk -v z="$(sget zoom)" 'BEGIN{print (z<1)}')" = 1
    snap extents
    c cancel
}
