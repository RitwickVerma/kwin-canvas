# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="pass-through on a second output: the handoff and the click land at the picture's own place there too"
pt_state() { nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state; }
aget() { sed -n 's/.*active="\(.*\)".*/\1/p' <<<"$(head -1 <<<"$LAST_STATE")"; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "pass-through plugin not loaded (make plugin)"; return
    fi
    c state
    if [ "$(sget screens)" != 2 ]; then skip "needs two outputs (make test-two-outputs)"; return; fi
    c "activate Dolphin"
    c state
    local kx ky kw kh vx vy z x1 y1 w1 h1
    kx=$(eget KWrite x); ky=$(eget KWrite y); kw=$(eget KWrite w); kh=$(eget KWrite h)
    read -r x1 y1 w1 h1 <<<"$(screenrect 1)"
    open_1to1
    # Zoom to 0.5 anchored at the second output's far-right edge: the view
    # then puts KWrite's canvas position on that output's screen, so its
    # picture is drawn there with that screen's own origin in the mix.
    input move $((x1 + w1 - 2)) $((y1 + h1 / 2))
    sleep 0.3
    c "zoom 0.5"
    sleep 0.6; c state
    vx=$(sget viewx); vy=$(sget viewy); z=$(sget zoom)
    # The picture's screen-local position on the second output: the visual
    # transform subtracts that screen's origin, and the global pointer adds
    # it back - the two must cancel, or the input layer drifts.
    local lx ly gx gy
    read -r lx ly <<<"$(awk -v vx="$vx" -v vy="$vy" -v z="$z" -v kx="$kx" -v ky="$ky" -v kw="$kw" -v kh="$kh" -v x1="$x1" 'BEGIN{
        printf "%d %d\n", (kx - vx) * z - x1 + kw * z * 0.9, (ky - vy) * z + kh * z * 0.5
    }')"
    gx=$((x1 + lx)); gy=$((y1 + ly))
    input move "$gx" "$gy"
    sleep 0.6
    assert_eq "the hover engages on the second output" "$(pt_state | grep -c 'hover=sample.txt')" 1
    input click
    sleep 0.6; c state
    assert_eq "the click reaches KWrite there too" "$(aget)" "sample.txt — KWrite"
    c cancel
    arrange >/dev/null
}
