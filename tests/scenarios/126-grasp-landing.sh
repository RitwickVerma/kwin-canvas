# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the grasp shows its destinations: the ring at the screen centre marks where the release lands and fades past the widen boundary, and the window under the pointer is named as the click's fly target"

run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    # The windows park in one corner cluster so the screen centre - the
    # landing ring's spot - is empty ground at every zoom the part uses.
    open_1to1
    c "placeby KCalc 200 1200 480 420"
    c "placeby sample.txt 700 1200 700 520"
    c "placeby Konsole 200 1650 620 420"
    c "placeby Dolphin 850 1700 700 360"
    c "placeby wallpaper.png 1400 1200 460 420"
    c commit
    sleep 0.3
    # Park the closed camera at the origin so the grid's phase under the
    # centre is the same in every run - the ring's probe needs a known
    # ground.
    c open
    c home
    sleep 0.5
    c commit
    sleep 0.3

    # The hold at 0.8: the ring's white arc crosses the spot just above the
    # screen centre - measured at (960,522) - where the ground alone reads
    # dark past the boundary.
    { printf 'move 1700 900\nsleep 60\ndown back\nsleep 22000\nup back\n'; } | input >/dev/null 2>&1 &
    holdpid=$!
    sleep 1.2
    c "zoom 0.8 960 540"
    sleep 0.8
    c state
    assert_eq "the hold is quiet at the eighth" "$(sget zoom)" "0.8000"
    assert_eq "and the keyhole is quiet" "$(grep -c ' quiet' <<<"$(head -1 <<<"$LAST_STATE")")" 1
    shot "$OUT/h8.png" >/dev/null 2>&1
    m8=$(magick "$OUT/h8.png" -crop 10x4+956+523 +repage -format "%[fx:mean.r]" info:)
    if awk -v m="$m8" 'BEGIN{exit !(m>0.45)}'; then ok "the centre wears the landing ring"; else fail "the centre wears the landing ring: got $m8"; fi

    # The window under the pointer is the click's target: park the pointer
    # on KCalc and let the grasp's pick name it.
    input move 352 1068
    sleep 0.8
    c state
    ki=$(eget KCalc index)
    assert_eq "the pointer's window is named as the fly target" "$(grep -o 'graspTarget=[0-9-]*' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2)" "$ki"

    # Past the 0.72 boundary the release widens instead of landing: the
    # same spot reads as the plain ground - the ring is gone.
    c "zoom 0.6 960 540"
    sleep 0.8
    c state
    assert_eq "the hold deepens to the sixth" "$(sget zoom)" "0.6000"
    shot "$OUT/h6.png" >/dev/null 2>&1
    m6=$(magick "$OUT/h6.png" -crop 10x4+956+523 +repage -format "%[fx:mean.r]" info:)
    if awk -v m="$m6" 'BEGIN{exit !(m<0.40)}'; then ok "past the boundary the ring is gone"; else fail "past the boundary the ring is gone: got $m6"; fi

    kill "$holdpid"
    wait "$holdpid" 2>/dev/null || true
    sleep 1.2
    c cancel
    arrange
}
