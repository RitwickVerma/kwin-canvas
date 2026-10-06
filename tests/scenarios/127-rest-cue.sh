# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the pass-through's rest is anticipated: while the pointer waits out the hover delay over a window, a thin line fills along its top edge, and the handoff that follows ends it"

region_rmse() {
    magick "$1" -crop "$3" +repage "$OUT/rc-a.png"
    magick "$2" -crop "$3" +repage "$OUT/rc-b.png"
    { magick compare -metric RMSE "$OUT/rc-a.png" "$OUT/rc-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}
changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }

pt_state() {
    nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state
}

run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "the pass-through plugin is not loaded (make plugin)"; return
    fi
    arrange >/dev/null
    # The default hover delay gives the cue a visible run; the scenario's
    # rests assume it, so it is pinned and cleaned up after.
    setcfg HoverDelay 900
    open_1to1
    sleep 1.0
    c state
    assert_eq "the overworld is up with the pass-through" "$(pt_state | grep -c 'active=true')" 1
    shot "$OUT/pre.png" >/dev/null 2>&1

    # The rest over KWrite's client area: the cue fills its top edge while
    # the delay runs, and the scene's own hover has not fired yet.
    input move 990 380
    sleep 0.4
    c state
    assert_eq "the rest is running" "$(grep -o ' rest=[01]' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2)" 1
    shot "$OUT/mid.png" >/dev/null 2>&1
    assert_eq "the cue fills the window's edge" "$(changed "$(region_rmse "$OUT/pre.png" "$OUT/mid.png" "200x3+640+120")")" 1

    # Past the delay the handoff happens: the rest ends and the window is
    # the pointer's.
    sleep 1.0
    c state
    assert_eq "the handoff ends the rest" "$(grep -o ' rest=[01]' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2)" 0
    assert_eq "and the window takes the pointer" "$(pt_state | grep -c 'hover=sample.txt')" 1
    shot "$OUT/post.png" >/dev/null 2>&1
    assert_eq "the cue is gone with it" "$(changed "$(region_rmse "$OUT/mid.png" "$OUT/post.png" "200x3+640+120")")" 1

    input move 1700 1000
    sleep 0.5
    c cancel
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key HoverDelay --delete
    arrange
}
