# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the shader channel: every commit writes the plane's remembered state - the view and the clusters - as a plain text file the shader wallpaper's engine can hand to a fragment shader"

run_scenario() {
    source tests/lib.sh
    if ! have_input; then
        skip "fakeinput not built (make tools)"
        return
    fi
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "the pass-through plugin is not loaded in the nest (make plugin)"
        return
    fi
    arrange >/dev/null
    open_1to1
    c commit
    sleep 0.5
    statefile="$CONF/kwin-canvas-state.txt"
    assert_true "the shader state lands on disk" -f "$statefile"
    assert_eq "with the saved view" "$(grep -c '^view=' "$statefile")" 1
    assert_eq "with the ground's own knobs" "$(grep -c '^grid=' "$statefile")" 1
    assert_eq "and one line per cluster" "$(grep -c '^cluster=' "$statefile")" "$(sget clusters)"
    clusterx=$(grep '^cluster=' "$statefile" | head -1 | cut -d= -f2 | cut -d, -f1)
    assert_near "with the light where the room sits" "$clusterx" 900 60
    c open
    c "pan 600 0"
    # The live feed: while the canvas runs, the state file follows the
    # camera without a commit. The tick publishes every second, so a beat
    # and a half catches it.
    sleep 1.5
    liveview=$(grep '^view=' "$statefile" | cut -d= -f2)
    if awk -v v="${liveview%,*}" 'BEGIN { exit !(v != -0.0 && v < 0) }'; then
        ok "and the state feeds live while the canvas runs"
    else
        fail "and the state feeds live while the canvas runs (got $liveview)"
    fi
    c commit
    sleep 0.5
    c cancel
    arrange
}
