# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="two outputs: every output's backdrop is its own desktop window (the one covering it), never the other output's; KWin 6.8 gives a desktop window no readable screen, and a match on it gave every output the first desktop window"

run_scenario() {
    source tests/lib.sh
    c state >/dev/null
    if [ "$(sget screens)" != 2 ]; then skip "needs two outputs (NEST_OUTPUTS=2)"; return; fi
    # The owner's layout: stacked and offset, so the two desktop windows differ in place and size.
    run kscreen-doctor output.Virtual-0.position.0,864 output.Virtual-1.position.480,0 >/dev/null 2>&1; sleep 3
    c state
    local line; line=$(grep -o ' deskfor=[^ ]*' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2)
    echo "# deskfor=$line"
    local r0x r0y r1x r1y
    read -r r0x r0y _ _ <<<"$(screenrect 0)"; read -r r1x r1y _ _ <<<"$(screenrect 1)"
    assert_eq "the first output's backdrop is the desktop window on it" "$(tr ';' '\n' <<<"$line" | sed -n 1p | cut -d: -f2)" "$r0x,$r0y"
    assert_eq "the second output's is its own" "$(tr ';' '\n' <<<"$line" | sed -n 2p | cut -d: -f2)" "$r1x,$r1y"
    run kscreen-doctor output.Virtual-0.position.0,0 output.Virtual-1.position.1920,0 >/dev/null 2>&1; sleep 3
}
