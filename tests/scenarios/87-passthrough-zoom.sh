# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="pass-through at zoom: the handoff and the click land at the picture's own place, not a zoom-scaled one"
pt_state() { nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state; }
aget() { sed -n 's/.*active="\(.*\)".*/\1/p' <<<"$(head -1 <<<"$LAST_STATE")"; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "pass-through plugin not loaded (make plugin)"; return
    fi
    # Zoomed out, the pointer rests on KWrite's picture at nine tenths of
    # its width. The canvas point under the pointer is inside the window, so
    # the hover must engage and hand the click over; the window's surface
    # must receive it at that same nine-tenths spot. A transform that fed the
    # window the raw canvas delta instead of the screen one would land the
    # click at 1.8 of the width - outside every input region - and the
    # handoff would never engage.
    c "activate Dolphin"
    c state
    local kx ky kw kh vx vy z sx sy
    kx=$(eget KWrite x); ky=$(eget KWrite y); kw=$(eget KWrite w); kh=$(eget KWrite h)
    c open
    c "zoom 0.5 960 540"
    sleep 0.6; c state
    vx=$(sget viewx); vy=$(sget viewy); z=$(sget zoom)
    read -r sx sy <<<"$(awk -v vx="$vx" -v vy="$vy" -v z="$z" -v kx="$kx" -v ky="$ky" -v kw="$kw" -v kh="$kh" 'BEGIN{
        printf "%d %d\n", (kx - vx) * z + kw * z * 0.9, (ky - vy) * z + kh * z * 0.5
    }')"
    input move "$sx" "$sy"
    sleep 0.6
    assert_eq "the hover engages over the picture" "$(pt_state | grep -c 'hover=sample.txt')" 1
    input click
    sleep 0.6; c state
    assert_eq "the click reaches KWrite at the picture's place" "$(aget)" "sample.txt — KWrite"
    c cancel
    arrange >/dev/null
}
