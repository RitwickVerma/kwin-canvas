# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="tidy lays the island's windows out in rows: sorted, packed left to right with the tidy gap, the real frames following the commit"

run_scenario() {
    arrange >/dev/null
    open_1to1
    sleep 0.4
    c "tidy"
    sleep 0.3
    c state
    assert_eq "the first row sorts by y then x" "$(eget KCalc x) $(eget KCalc y)" "32 32"
    assert_eq "the second window packs beside it" "$(eget "sample.txt" x) $(eget "sample.txt" y)" "544 32"
    assert_eq "the third fills the row" "$(eget "wallpaper.png" x) $(eget "wallpaper.png" y)" "1276 32"
    assert_eq "the fourth wraps to the next row" "$(eget Konsole x) $(eget Konsole y)" "32 584"
    assert_eq "the fifth closes that row" "$(eget Dolphin x) $(eget Dolphin y)" "684 584"
    c commit
    open_1to1
    sleep 0.4
    c state
    assert_eq "the commit wrote the first window's real frame" "$(eget KCalc fx) $(eget KCalc fy)" "32 32"
    assert_eq "and the second's" "$(eget "sample.txt" fx) $(eget "sample.txt" fy)" "544 32"
    assert_eq "and the wrapped one's" "$(eget Konsole fx) $(eget Konsole fy)" "32 584"
    assert_eq "and the last one's" "$(eget Dolphin fx) $(eget Dolphin fy)" "684 584"
    arrange >/dev/null
}
