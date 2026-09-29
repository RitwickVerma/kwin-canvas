# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="pushing the pointer into every configured screen border opens the canvas"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    c state
    assert_eq "closed to start" "$(sget visible)" false
    # Every border the Screen Edges page can write, one at a time: a border
    # fires only when it is the one the effect reserved, so a pass here is a
    # pass for that border alone, corner or edge. push_border carries the
    # timing KWin needs - two events on the border's own pixel, between
    # ElectricBorderDelay (75 ms) and ElectricBorderCooldown (350 ms) apart,
    # and no push after the second one, because a push that keeps going past
    # the cooldown re-triggers the border and its second toggle enters the
    # location, leaving the canvas closed. See tests/lib.sh.
    local b
    for b in 7 1 3 5 0 2 4 6; do
        set_borders "$b"
        push_border "$b"
        sleep 0.5; c state
        assert_eq "border $b opened the canvas" "$(sget visible)" true
        c cancel; sleep 0.4; c state
        assert_eq "border $b left it closed" "$(sget visible)" false
    done
    # All eight at once, as the settings page can be set. The corner pixels
    # belong to the corner - an edge strip stops cornerOffset (40 px) short of
    # its corners - so a push into a corner is one border, one toggle: the
    # canvas stays open instead of opening and closing at the same corner.
    set_borders "0,1,2,3,4,5,6,7"
    push_border 7
    sleep 0.5; c state
    assert_eq "corner with all eight configured opened it once" "$(sget visible)" true
    # Escape would go to the focused window with pass-through live; the
    # chord enters the location, which moved nothing.
    printf 'key leftctrl down\nkey leftalt down\nkey space\nkey leftalt up\nkey leftctrl up\n' | input
    sleep 0.6; c state
    assert_eq "the chord closed it" "$(sget visible)" false
    assert_eq "nothing moved" "$(eget KCalc fx)" 100

    # A border opens the canvas stepped out around its own screen: BorderZoom,
    # anchored at that screen's centre, so the push shows the desks around the
    # screen that was pushed instead of the desktop that was on it. At 1:1 on
    # the frames the canvas point under the centre is the target plus half a
    # screen - (960,540) - and pinning it puts the camera at
    # (0,0) + (960,540) - (960,540)/0.8 = (-240,-135). The frame's centre is
    # then under the screen centre, and the point the push left there is the
    # point applying comes back to.
    setcfg BorderZoom 0.8
    push_border 7
    sleep 0.6; c state
    assert_eq "a border opens the canvas" "$(sget visible)" true
    assert_near "stepped out to BorderZoom" "$(sget zoom)" 0.8 0.005
    assert_near "around that screen's centre x" "$(sget viewx)" -240 2
    assert_near "around that screen's centre y" "$(sget viewy)" -135 2
    snap corner-zoom
    c cancel; sleep 0.4
    # BorderZoom=1 opens at 1:1, the old behaviour, for anyone who wants the
    # push to hand over the desktop exactly as it was.
    setcfg BorderZoom 1
    push_border 7
    sleep 0.5; c state
    assert_near "BorderZoom 1 stays at 1:1" "$(sget zoom)" 1 0.001
    c cancel; sleep 0.4

    # A pointer a KVM switch drops onto the border pixel is not a push: KWin
    # wants two motion events on the pixel between ElectricBorderDelay (75 ms)
    # and ElectricBorderCooldown (350 ms), so a single placement - and the move
    # away the user makes next - never arms the border. Deskflow, a network KVM
    # and a remote session all place the pointer like this when they hand the
    # machine over.
    setcfg BorderZoom 0.8
    kvm_drop_on_border 7
    sleep 0.4; c state
    assert_eq "a KVM's placement on the corner pixel does not open it" "$(sget visible)" false
    # A fast traverse across the edge is not a push either: the two events have
    # to be within DISTANCE_RESET (30 px) of each other, so a pointer crossing
    # the border at speed passes through instead of arming it.
    input move 0 5
    sleep 0.12
    input move 0 90
    sleep 0.5; c state
    assert_eq "a fast slide across the edge does not open it" "$(sget visible)" false
    input move 960 540

    # Back to the nest's defaults, so a later scenario in the same nest does not
    # inherit eight reservations.
    set_borders 7
    setcfg BorderZoom 0.8
    c state >/dev/null
}
