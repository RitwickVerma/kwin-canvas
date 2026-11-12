# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="side buttons: a quick press of the canvas modifier reaches the window as the button the mouse sent - a real mouse's back button (BTN_SIDE) arrives as Back, where KWin's Qt-button seat call turned it into BTN_BACK, which no app reads as Back"
# The Qt values the probe logs: Back (BTN_SIDE) is 8, Forward (BTN_EXTRA) 16 and
# ExtraButton4 (BTN_BACK) 64, as QtWayland maps them.
# probe_seen: every press and release the probe logged, as "press:8 release:8 ...".
probe_seen() {
    grep -a -E 'PROBE Probe Buttons (press|release) ' "$STATE/probe.log" \
        | sed -E 's/.*Buttons (press|release) .* button ([0-9]+)$/\1:\2/' | tr '\n' ' ' | sed 's/ $//'
}
probe_presses() { grep -a -c "PROBE Probe Buttons press " "$STATE/probe.log"; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "pass-through plugin not loaded (make plugin)"; return
    fi
    : > "$STATE/probe.log"
    probe Buttons
    local i
    for i in $(seq 1 40); do grep -a -q "PROBE Probe Buttons active true" "$STATE/probe.log" && break; sleep 0.2; done
    kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption) === \"Probe Buttons\") w = x; }); w.frameGeometry = {x: 700, y: 250, width: 400, height: 300}; workspace.activeWindow = w;" 0.6
    c state
    assert_eq "closed to start" "$(sget visible)" false
    # Every click comes from one injector, as from a mouse that stays plugged in. A fakeinput
    # per click makes KWin drop and re-add the seat's pointer around each one (40 capability
    # changes for 10 clicks), and the probe loses about a third of the events while it rebinds:
    # that measures the harness, not the replay.
    : > "$STATE/probe.log"
    local stream="move 900 400\nsleep 60\n" b
    for b in side side side back extra; do stream+="down $b\nsleep 40\nup $b\nsleep 300\n"; done
    printf "$stream" | input
    sleep 0.6
    local seen; seen=$(probe_seen)
    # A real mouse's back button is BTN_SIDE. Under the default modifier (BackButton) each quick
    # press is the hold candidate, replayed to the window on the release.
    assert_eq "three quick presses of a real mouse's back button (BTN_SIDE) reach the window as Back, press and release" \
        "$(cut -d' ' -f1-6 <<<"$seen")" "press:8 release:8 press:8 release:8 press:8 release:8"
    # A mouse that sends BTN_BACK for it is caught by the same mask (ExtraButton4) and keeps its own button.
    assert_eq "a BTN_BACK press stays BTN_BACK, not BTN_EXTRA (Forward)" "$(cut -d' ' -f7-8 <<<"$seen")" "press:64 release:64"
    # The forward button is not the modifier: never held, never replayed - the control.
    assert_eq "the forward button (BTN_EXTRA), not the modifier, reaches it as Forward" "$(cut -d' ' -f9-10 <<<"$seen")" "press:16 release:16"
    c state
    assert_eq "no quick press opened the canvas" "$(sget visible)" false
    # The modifier itself still works from the real mouse's code: a held BTN_SIDE opens the
    # grasp, and the window sees no press of it.
    local before; before=$(probe_presses)
    printf 'move 900 400\nsleep 60\ndown side\nsleep 900\nup side\n' | input &
    sleep 0.7; c state
    assert_eq "a held BTN_SIDE opens the canvas as the grasp" "$(head -1 <<<"$LAST_STATE" | grep -c 'visible=true quiet grasp')" 1
    wait
    sleep 0.6
    assert_eq "and the window saw no press of the held button" "$(probe_presses)" "$before"
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption) === \"Probe Buttons\") x.closeWindow(); });" 0.4
}
