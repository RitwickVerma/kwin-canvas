# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="two outputs stacked and offset (the maintainer's layout): activating a window that sits across the seam between monitors, or in the dead corner where no monitor is, brings it wholly onto the monitor the pointer is on; a window already wholly on one monitor is left alone"
# KCalc's real frame, and the verdict against each output.
kframe() {
    kwinjs 'var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) w = x; }); var g = w.frameGeometry; print("ONEMON " + Math.round(g.x) + " " + Math.round(g.y) + " " + Math.round(g.width) + " " + Math.round(g.height));' 0.5
    grep -a "ONEMON" "$STATE/kwin.log" | tail -1 | sed 's/.*ONEMON //'
}
# on_output N RECT: is RECT wholly inside output N?
on_output() {
    local x y w h ox oy ow oh
    read -r x y w h <<<"$2"
    read -r ox oy ow oh <<<"$(screenrect "$1")"
    awk -v x="$x" -v y="$y" -v w="$w" -v h="$h" -v ox="$ox" -v oy="$oy" -v ow="$ow" -v oh="$oh" 'BEGIN{print (x >= ox && y >= oy && x + w <= ox + ow && y + h <= oy + oh) ? "yes" : "no"}'
}
place() { # X Y: Konsole active first, then KCalc put at a REAL position by the canvas (a script's move of a
    # window that is out of reach onto a monitor is KWin's rule to the canvas, and is put back)
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Konsole") >= 0) workspace.activeWindow = x; });' 2.4
    c open >/dev/null; sleep 0.5; c state >/dev/null
    local px py
    px=$(awk -v x="$1" -v v="$(sget viewx)" 'BEGIN{printf "%d", x + v}')
    py=$(awk -v y="$2" -v v="$(sget viewy)" 'BEGIN{printf "%d", y + v}')
    c "placeby KCalc $px $py" >/dev/null; c commit >/dev/null; sleep 0.8
}
activate_kcalc() {
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) workspace.activeWindow = x; });' 2.4
}
run_scenario() {
    source tests/lib.sh
    c state >/dev/null
    if [ "$(sget screens)" != 2 ]; then skip "needs two outputs (NEST_OUTPUTS=2)"; return; fi
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    run kscreen-doctor output.Virtual-0.position.0,864 output.Virtual-1.position.480,0 >/dev/null 2>&1
    sleep 2.5
    arrange >/dev/null
    local r0x r0y r0w r0h r1x r1y r1w r1h
    read -r r0x r0y r0w r0h <<<"$(screenrect 0)"
    read -r r1x r1y r1w r1h <<<"$(screenrect 1)"
    # The pointer on output 0 (the lower one).
    input move $((r0x + r0w / 2)) $((r0y + r0h / 2)); sleep 0.3
    # Across the seam: the top of output 0 is y=864, the bottom of output 1.
    place 700 700
    activate_kcalc
    assert_eq "across the seam: brought wholly onto the pointer's monitor" "$(on_output 0 "$(kframe)")" yes
    # In the dead corner: x < 480 above output 0, where no monitor is.
    place 40 120
    activate_kcalc
    assert_eq "in the dead corner: brought wholly onto the pointer's monitor" "$(on_output 0 "$(kframe)")" yes
    # Wholly on the other monitor: left alone.
    place 900 100
    activate_kcalc
    assert_eq "wholly on the other monitor: not moved" "$(kframe)" "900 100 480 420"
    # Wholly on the pointer's monitor: left alone.
    place 200 1000
    activate_kcalc
    assert_eq "wholly on the pointer's monitor: not moved" "$(kframe)" "200 1000 480 420"
    # The pointer on the upper output: a straddling window comes to that one.
    input move $((r1x + r1w / 2)) $((r1y + r1h / 2)); sleep 0.3
    place 700 700
    activate_kcalc
    assert_eq "pointer on the upper monitor: the straddling window comes to it" "$(on_output 1 "$(kframe)")" yes
    # The nest's default layout back, for the scenarios that follow.
    run kscreen-doctor output.Virtual-0.position.0,0 output.Virtual-1.position.1920,0 output.Virtual-0.scale.1 output.Virtual-1.scale.1 >/dev/null 2>&1
    sleep 2.5
    arrange >/dev/null
}
