# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="two outputs: the canvas's chrome (toolbar, minimap, toast, switcher) sits on the screen the canvas was opened on and follows the pointer once it rests on another screen, not on the primary display; a quick pass across the seam does not move it"
chrome() { c state >/dev/null; sed -n '1s/.* chrome=\([^ ]*\).*/\1/p' <<<"$LAST_STATE"; }
run_scenario() {
    c state
    if [ "$(sget screens)" != 2 ]; then skip "needs two outputs (make test-two-outputs ARGS=172)"; return; fi
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    local x0 y0 w0 h0 x1 y1 w1 h1
    read -r x0 y0 w0 h0 <<<"$(screenrect 0)"
    read -r x1 y1 w1 h1 <<<"$(screenrect 1)"
    arrange >/dev/null
    input move $((x1 + w1 / 2)) $((y1 + h1 / 2)); sleep 0.3
    c open >/dev/null; sleep 1
    assert_eq "opened with the pointer on the second output, the chrome is on it" "$(chrome)" "Virtual-1"
    input move $((x0 + w0 / 2)) $((y0 + h0 / 2)); sleep 0.15
    input move $((x1 + w1 / 2)) $((y1 + h1 / 2)); sleep 0.8
    assert_eq "a quick pass over the first output leaves it where it was" "$(chrome)" "Virtual-1"
    input move $((x0 + w0 / 2)) $((y0 + h0 / 2)); sleep 1
    assert_eq "resting on the first output moves the chrome there" "$(chrome)" "Virtual-0"
    c cancel >/dev/null 2>&1; sleep 0.8
    input move $((x1 + w1 / 2)) $((y1 + h1 / 2)); sleep 0.3
    c open >/dev/null; sleep 1
    assert_eq "a new open starts on the screen the pointer is on" "$(chrome)" "Virtual-1"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
