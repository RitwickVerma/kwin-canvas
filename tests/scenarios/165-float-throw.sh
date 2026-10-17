# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a floated window is not thrown: flicked fast and let go it stays where the hand let go, where the same flick throws a free window on (a guard for the deliberate exclusion in endDrag)"
flick() { # fast motion right up to the release, from KCalc's body
    { printf 'move 300 300\nsleep 50\ndown\nsleep 60\n'
      local i; for i in $(seq 1 10); do printf 'rel 30 0\nsleep 8\n'; done
      printf 'up\n'; } > "$OUT/165.in"
    input < "$OUT/165.in"
    sleep 1.2
}
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    setcfg Passthrough false
    setcfg WindowPhysics true
    setcfg MovesGlide true
    arrange >/dev/null
    open_1to1
    c state >/dev/null
    local x0; x0=$(eget KCalc x)
    # The free window, as the control: the flick throws it well past the hand.
    flick
    c state >/dev/null
    assert_true "a free window is thrown" "$(sget throw)" != "-"
    local free; free=$(eget KCalc x)
    assert_true "and comes to rest past the release point" "$free" -gt "$((x0 + 300 + 20))"
    # The same flick on the floated window, put back where it was.
    c "place $(eget KCalc index) $x0 120" >/dev/null
    c "pin $(eget KCalc index)"
    sleep 0.3
    flick
    c state >/dev/null
    local floated; floated=$(eget KCalc x)
    assert_true "a floated window stays where the hand let go" "$floated" -lt "$((x0 + 300 + 20))"
    assert_true "having followed the hand" "$floated" -gt "$((x0 + 200))"
    assert_eq "its picture is inside the screen" "$(float_inside)" yes
    c "unpin $(eget KCalc index)"
    rm -f "$OUT/165.in"
    setcfg Passthrough true
    setcfg MovesGlide false
    setcfg WindowPhysics false
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
