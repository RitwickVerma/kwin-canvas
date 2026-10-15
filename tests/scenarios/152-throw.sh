# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a window flicked away keeps going and comes to rest a short way past the release; one set down slowly stays where the hand put it"
run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # The canvas takes the pointer, not the plugin, so the drag moves the
    # thumbnail (the plugin's own scenario is 85).
    setcfg Passthrough false
    setcfg WindowPhysics true
    setcfg MovesGlide true
    arrange >/dev/null
    open_1to1
    c state
    local x0; x0=$(eget KCalc x)
    # KCalc sits at 100,120 480x420: grab its body. A slow drag, then a pause
    # before letting go: a set-down.
    printf 'move 300 300\nsleep 50\ndown\nsleep 60\n' > "$OUT/slow.in"
    local i; for i in $(seq 1 20); do printf 'rel 10 0\nsleep 25\n' >> "$OUT/slow.in"; done
    printf 'sleep 300\nup\n' >> "$OUT/slow.in"
    input < "$OUT/slow.in"
    sleep 1
    c state
    assert_eq "a slow set-down throws nothing" "$(sget throw)" "-"
    assert_near "and the window is where the hand left it" "$(eget KCalc x)" "$((x0 + 200))" 3
    local x1; x1=$(eget KCalc x)
    # A flick: fast motion right up to the release.
    printf 'move 500 300\nsleep 50\ndown\nsleep 60\n' > "$OUT/fast.in"
    for i in $(seq 1 10); do printf 'rel 30 0\nsleep 8\n' >> "$OUT/fast.in"; done
    printf 'up\n' >> "$OUT/fast.in"
    input < "$OUT/fast.in"
    sleep 1.2
    c state
    assert_true "a flick throws" "$(sget throw)" != "-"
    assert_true "and the window comes to rest past the release point" "$(eget KCalc x)" -gt "$((x1 + 300 + 20))"
    assert_true "but not off into the dark" "$(eget KCalc x)" -lt "$((x1 + 300 + 400))"
    rm -f "$OUT/slow.in" "$OUT/fast.in"
    setcfg Passthrough true
    setcfg MovesGlide false
    c cancel
    arrange >/dev/null
}
