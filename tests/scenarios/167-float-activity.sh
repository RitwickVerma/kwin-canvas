# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a floated window rides the eye into another activity's frame: stepping into that activity (goto, a cross-activity focus) lands the float against the frame it is written to, on screen, in that activity - with the step taken at once and with the animated one"
onscreen_frame() { # the real frame of KCalc wholly inside the 1920x1080 screen?
    float_frame | awk '{print ($1 >= 0 && $2 >= 0 && $1 + $3 <= 1920 && $2 + $4 <= 1080) ? "yes" : "no " $0}'
}
# Leave the nest as it was: Activity 1 current, KCalc unpinned and back home,
# the third activity (if the case made one) gone.
restore() {
    c "activity 0" >/dev/null
    sleep 0.8
    open_1to1
    c state >/dev/null; local k; k=$(eget KCalc index)
    c "unpin $k" >/dev/null
    c "placeby KCalc 100 120" >/dev/null
    c commit >/dev/null
    sleep 0.5
    c state >/dev/null
    if [ "$(sget nactivities)" = 3 ]; then c "rmactivity 2" >/dev/null; sleep 1.2; c state >/dev/null; fi
    arrange >/dev/null
}
step_in() { # MODE: goto | focus. KCalc floated in Activity 1's view, Activity 2 entered.
    local mode=$1 k
    open_1to1
    c state >/dev/null
    k=$(eget KCalc index)
    case $mode in
        goto)
            # Floated at its coordinates in Activity 1's frame; the step goes to Activity 2.
            c "pin $k" >/dev/null
            sleep 0.3
            c "goto 1" >/dev/null ;;
        focus)
            # A third activity of its own, so the smart placement moving its
            # viewport leaves the seeded ones alone. The window is parked in
            # its frame and the camera is looking there, so the float sits at
            # its coordinates (not displaced) and focusWindow takes the
            # cross-activity branch: it flies to Activity 3 and switches.
            c addactivity >/dev/null
            sleep 1.2
            c state >/dev/null
            local tx ty vx vy; tx=$(tget 2 x); ty=$(tget 2 y); vx=$(sget viewx); vy=$(sget viewy)
            c "placeby KCalc $((tx + 200)) $((ty + 200))" >/dev/null
            c "panpx $((${vx%.*} - tx)) $((${vy%.*} - ty))" >/dev/null
            sleep 1.2
            c "pin $k" >/dev/null
            sleep 0.3
            c "focus $k" >/dev/null ;;
    esac
    local i
    for i in $(seq 1 12); do c state >/dev/null; [ "$(sget visible)" = false ] && break; sleep 0.4; done
    sleep 1
    c state >/dev/null
}
run_scenario() {
    c state >/dev/null
    assert_eq "two seeded activities" "$(sget nactivities)" 2
    arrange >/dev/null

    # The step taken at once (SmoothZoom off): the camera is still on Activity
    # 1's frame when the commit runs, and the switch is not yet reported.
    setcfg SmoothZoom false
    step_in goto
    assert_eq "goto, at once: the canvas closed on Activity 2" "$(sget activity)" "Activity 2"
    assert_eq "goto, at once: the floated window was written to Activity 2" "$(eget KCalc activity)" "Activity 2"
    assert_eq "goto, at once: the real frame is on screen" "$(onscreen_frame)" yes
    restore

    # The animated step in.
    setcfg SmoothZoom true
    step_in goto
    assert_eq "goto, animated: the canvas closed on Activity 2" "$(sget activity)" "Activity 2"
    assert_eq "goto, animated: the floated window was written to Activity 2" "$(eget KCalc activity)" "Activity 2"
    assert_eq "goto, animated: the real frame is on screen" "$(onscreen_frame)" yes
    restore
    setcfg SmoothZoom false

    # A cross-activity focus of a floated window parked in a third activity's frame.
    step_in focus
    assert_eq "focus, at once: the canvas closed on Activity 3" "$(sget activity)" "Activity 3"
    assert_eq "focus, at once: the floated window was written to Activity 3" "$(eget KCalc activity)" "Activity 3"
    assert_eq "focus, at once: the real frame is on screen" "$(onscreen_frame)" yes
    restore
}
