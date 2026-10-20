# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a floated window that grows while its picture rides the edge: the picture glides in to its new bounds instead of jumping, stays on screen, and the real window lands where the picture rests"
run_scenario() {
    arrange >/dev/null
    open_1to1
    c state >/dev/null
    local k; k=$(eget KCalc index)
    c "pin $k"
    c "panpx 1500 0" >/dev/null
    sleep 1.2
    local px py pw ph
    read -r px py pw ph <<<"$(float_picture)"
    assert_eq "pushed out, the picture rides the right edge" "$px" "1432.0"
    # The window grows to 1100 wide: its bounds close in to 812. The picture
    # was at the old bound, 620 px beyond the new one.
    c "resize $k 1100 700" >/dev/null
    read -r px py pw ph <<<"$(float_picture)"
    # The glide is a critically damped spring (about 7/s): a state read takes up to
    # a second on a loaded machine, by which time it is within a few px of the bound,
    # so "mid-glide" is anything clear of the bound by 12 px, where a jump would be
    # exactly on it.
    assert_true "the first look after the resize is not already at the bound (a jump would be at 812)" "$(awk -v x="$px" 'BEGIN{print (x > 824)}')" = 1
    sleep 1.5
    read -r px py pw ph <<<"$(float_picture)"
    assert_eq "and it settles on the new bound" "$px" "812.0"
    assert_eq "inside the screen" "$(float_inside)" yes
    c enter >/dev/null
    sleep 1.5
    assert_eq "the real window lands where the picture rested" "$(float_frame)" "812 120 1100 700"
    c open >/dev/null; c state >/dev/null; k=$(eget KCalc index); c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
