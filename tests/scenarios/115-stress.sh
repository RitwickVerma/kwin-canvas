# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a camera storm cannot poison the canvas: spring flights, pan bursts and a mid-flight grasp all land on a finite, answering camera"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    local start_lines
    start_lines=$(wc -l < "$STATE/kwin.log")

    arrange
    c "activate Konsole"
    open_1to1

    # The spring is what diverges: turn the physics on for the storm.
    setcfg SmoothZoom true
    setcfg CamSpring 14

    # A burst of spring flights and pans, back to back. The debug channel
    # queues every command through the config replay, so the camera is in
    # flight for most of this loop; each state read lands mid-spring.
    local i
    for i in $(seq 1 20); do
        case $(( i % 4 )) in
            0) c "zoomto 0.4 $(( (i % 3) * 320 )) $(( (i % 2) * 270 ))" ;;
            1) c "pan $(( (i % 5) * 120 - 240 )) $(( (i % 3) * 90 - 90 ))" ;;
            2) c "zoomto 1.0 960 540" ;;
            3) c "shift $(( (i % 7) * 60 - 180 )) 0" ;;
        esac
        sleep 0.1
        c state
        if [ "$(sget zoom)" = "nan" ] || [ "$(sget zoom)" = "inf" ] || [ -z "$(sget zoom)" ]; then
            fail "the zoom went non-finite on storm step $i"
            break
        fi
        if [ "$(sget viewx)" = "nan" ] || [ "$(sget viewx)" = "inf" ] || [ "$(sget viewy)" = "nan" ] || [ "$(sget viewy)" = "inf" ]; then
            fail "the view went non-finite on storm step $i"
            break
        fi
    done

    # A hold mid-flight: the grasp starts from wherever the spring is, zooms
    # out, and the release commits. The camera must survive the whole round.
    printf 'move 960 900\nsleep 60\ndown back\nsleep 1500\nmove 960 540\nsleep 100\nclick\nsleep 300\nup back\n' | input >/dev/null 2>&1 &
    sleep 0.6
    c "zoom 0.5 960 540"
    sleep 0.8
    c state
    assert_eq "the mid-flight grasp is a grasp" "$(sget zoom)" "0.5000"
    sleep 1.2
    # Release committed (or widened); either way the camera stays finite.
    c state
    if [ "$(sget zoom)" = "nan" ] || [ "$(sget zoom)" = "inf" ]; then
        fail "the zoom went non-finite through the grasp"
    fi

    # Land on the location: a commit at 1:1 with the physics back off must
    # still answer and still be finite.
    setcfg SmoothZoom false
    c cancel
    open_1to1
    c state
    assert_eq "the canvas still opens after the storm" "$(sget visible)" "true"
    assert_eq "the camera is finite at the end" "$(sget zoom)" "1.0000"

    # No exceptions appeared in the effect's log during any of it.
    local new_errors
    # The known-benign plasmashell Menu.qml width-of-null spam aside.
    new_errors=$(tail -n +"$((start_lines + 1))" "$STATE/kwin.log" | grep "TypeError\|ReferenceError" | grep -vc "Menu.qml" || true)
    assert_eq "no exceptions during the storm" "$new_errors" "0"
}
