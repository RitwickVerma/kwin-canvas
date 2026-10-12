# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the seam: a pointer parked on the desk's outer border - where a shared mouse (deskflow) parks it while another machine has the mouse - hovers nothing and moves nothing, in the effect and in the pass-through"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    # A window whose top pokes past the desk's top seam, committed for real:
    # both the effect's picture and the pass-through see it at the border, so
    # a pointer parked at the seam rests inside its frame and an unguarded
    # hover would focus it, hand it the input, and pan the camera to bring it
    # into view.
    open_1to1
    c "placeby KCalc 600 -300 480 420"
    c commit
    sleep 0.6
    open_1to1
    for _ in $(seq 1 30); do c state; [ "$(sget cam)" = "-" ] && break; sleep 0.15; done
    assert_true "the window really sits under the seam point" \
        "$(awk -v x="$(eget KCalc x)" -v y="$(eget KCalc y)" 'BEGIN{print (x <= 840 && x + 480 >= 840 && y <= 2 && y + 420 >= 2)}')" = 1
    input move 840 2
    sleep 1.6
    c state
    assert_eq "the parked pointer reads as the seam" "$(sget seam)" 1
    assert_eq "and hovers nothing" "$(head -1 <<<"$LAST_STATE" | grep -c 'focus=-')" 1
    assert_near "and the camera stays put, x" "$(sget viewx)" 0 0.5
    assert_near "and y" "$(sget viewy)" 0 0.5
    if nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        local ps
        ps=$(nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state)
        assert_eq "the pass-through hands the parked pointer to no window" \
            "$(sed -n 's/.*hover=\([^ ]*\).*/\1/p' <<<"$ps")" "-"
    fi
    # A few pixels in, the pointer is the hand's again: the same rest is a
    # real hover, which focuses the window and pans it wholly into view.
    input move 840 30
    sleep 1.6
    c state
    assert_eq "a real rest is not the seam" "$(sget seam)" 0
    assert_eq "and it focuses the window" "$(head -1 <<<"$LAST_STATE" | grep -c 'focus="KCalc"')" 1
    for _ in $(seq 1 30); do c state; [ "$(sget cam)" = "-" ] && break; sleep 0.15; done
    local want
    want=$(awk -v y="$(eget KCalc y)" 'BEGIN{print y - 24}')
    assert_near "and the smart pan brings it on screen" "$(sget viewy)" "$want" 4
    c cancel
    arrange >/dev/null
}
