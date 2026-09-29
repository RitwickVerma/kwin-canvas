# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="activating an off-screen window slides the plane to it, and a half-off one is brought wholly on screen"
run_scenario() {
    # Activation only fires for a window that is not already active.
    c "activate Dolphin"
    c "shift 3000 0"
    assert_eq "KCalc off-screen" "$(eget KCalc fx)" 3100
    c "activate KCalc"
    sleep 0.4
    c state
    local fx; fx=$(eget KCalc fx)
    assert_true "KCalc on screen" "$(awk -v x="$fx" 'BEGIN{print (x>=0 && x<1920)}')" = 1
    assert_near "Dolphin kept its offset" "$(eget Dolphin fx)" "$(awk -v x="$fx" 'BEGIN{print x+680}')" 1
    # A window hanging half off the screen is not visible: focusing it slides
    # the least that brings it wholly on screen - its edge ends at the
    # screen's margin - keeping the rest of the desk in view rather than
    # centring it. The layout is restored first, and Dolphin is activated
    # while fully visible, so the KCalc activation is the only fly.
    arrange >/dev/null
    c "activate Dolphin"
    sleep 0.3
    c "shift 1500 0"
    c "activate KCalc"
    sleep 0.4
    c state
    assert_true "a half-off window is brought wholly on screen" \
        "$(awk -v x="$(eget KCalc fx)" 'BEGIN{print (x>=0 && x+480<=1920)}')" = 1
    assert_true "with the least movement, its edge near the margin" \
        "$(awk -v x="$(eget KCalc fx)" 'BEGIN{print (x + 480 > 1820 && x + 480 <= 1920)}')" = 1
    arrange >/dev/null
    assert_eq "layout restored" "$(eget KCalc fx)" 100
}
