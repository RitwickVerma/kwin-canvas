# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="separate cameras: with the overview open on one monitor, the pointer on a window on the other monitor hovers it at once and a click activates it (the other monitor is the real desktop); with the cameras merged it waits out the hover delay"
hovered() { nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state 2>/dev/null | sed -n 's/.* hover=\(.*\) nav=.*/\1/p'; }
active_caption() {
    kwinjs 'print("INPACTIVE " + (workspace.activeWindow ? workspace.activeWindow.caption : "-"));' 0.4
    grep -a "INPACTIVE" "$STATE/kwin.log" | tail -1 | sed 's/.*INPACTIVE //'
}
run_scenario() {
    source tests/lib.sh
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then skip "pass-through plugin not loaded (make plugin)"; return; fi
    c state >/dev/null
    if [ "$(sget screens)" != 2 ]; then skip "needs two outputs (NEST_OUTPUTS=2)"; return; fi
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    setcfg SmoothZoom false
    setcfg HoverDelay 900
    run kscreen-doctor output.Virtual-0.position.0,0 output.Virtual-1.position.1920,0 output.Virtual-0.scale.1 output.Virtual-1.scale.1 >/dev/null 2>&1
    sleep 2.5
    c state >/dev/null
    local r0x r0y r0w r0h r1x r1y r1w r1h dx dy
    read -r r0x r0y r0w r0h <<<"$(screenrect 0)"
    read -r r1x r1y r1w r1h <<<"$(screenrect 1)"
    dx=$((r1x + 380 + 350)); dy=$((300 + 180))
    local mode
    for mode in merged separate; do
        setcfg Cameras $mode
        arrange >/dev/null
        kwinjs "var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"Dolphin\") >= 0) w = x; }); w.frameGeometry = {x: $((r1x + 380)), y: 300, width: 700, height: 360};" 0.6
        input move $((r0x + r0w / 2)) $((r0y + r0h / 2)); sleep 0.3
        c open >/dev/null; sleep 1.2
        input move $((dx - 20)) $((dy - 20)); sleep 0.1
        input move "$dx" "$dy"; sleep 0.4
        if [ "$mode" = separate ]; then
            assert_true "separate: the pointer on the other monitor hovers its window at once" "$(hovered)" = "fixtures — Dolphin"
            printf 'move %d %d\nsleep 80\ndown\nsleep 80\nup\n' "$dx" "$dy" | input
            sleep 0.6
            assert_true "separate: a click there activates it" "$(active_caption)" = "fixtures — Dolphin"
        else
            assert_true "merged: the same pointer has not handed Dolphin the input yet (the hover delay)" "$(hovered)" != "fixtures — Dolphin"
        fi
        c cancel >/dev/null 2>&1; sleep 0.8
    done
    setcfg Cameras merged
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key HoverDelay --delete >/dev/null
    arrange >/dev/null
}
