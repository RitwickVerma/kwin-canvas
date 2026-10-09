# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the shader channel: every commit writes the plane's remembered state - the view, the clusters and the day-trail - as a plain text file the shader wallpaper's engine can hand to a fragment shader"

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
    # The trail is pinned off in the nest's seed (it would grow in every
    # scenario's pans); this part turns it on for its own proof.
    setcfg DayTrail true
    c open
    c "pan 600 0"
    c commit
    sleep 0.5
    assert_eq "and the trail rides the same file" "$(grep -c '^trail=' "$statefile")" 1
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key DayTrail --delete
    c cancel
    arrange
}
