# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a slide whose destination is wholly off the screen flies: the quiet scene eases out, travels and lands at 1:1 (the perf line names the arc's lowest zoom), the windows keep their plane spots, a short slide stays a slide, and a fly turned mid-way lands where it was sent"

# perf_lines FROM: the "kwin-canvas perf:" lines the log gained after line FROM.
perf_lines() { tail -n +"$(($1 + 1))" "$LOG" | grep -a "kwin-canvas perf: " | sed 's/.*kwin-canvas perf: //'; }
# perf_val LINES EVENT KEY: the number after KEY= on EVENT's first line.
perf_val() { grep -a "^$2\( \|$\)" <<<"$1" | head -1 | sed -n "s/.* $3=\([-0-9.]*\).*/\1/p"; }

# wait_closed_at X: the slide has landed and closed with the view at X.
wait_closed_at() {
    local i
    for i in $(seq 1 25); do
        c state
        [ "$(sget visible)" = false ] && [ "$(printf '%.0f' "$(sget viewx)")" = "$1" ] && return 0
        sleep 0.2
    done
    return 1
}

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg Perf true
    c cancel
    sleep 0.4

    # Where KCalc sits on the plane, and the view.
    open_1to1
    c state
    local vx kx ky
    vx=$(printf '%.0f' "$(sget viewx)")
    kx=$(eget KCalc x)
    ky=$(eget KCalc y)
    c cancel
    sleep 0.4

    # Three screens and more to the right: nothing of the start is on the screen there.
    local far=$((WIDTH * 3 + 300)) mark lines arc
    mark=$(wc -l <"$LOG")
    cmd "slide $far 0" >/dev/null 2>&1
    sleep 0.2
    # Mid-flight, for the eye (not compared): the plane seen from above.
    shot "$OUT/far-fly-mid.png" >/dev/null 2>&1
    wait_closed_at $((vx + far)) || true
    assert_eq "the far slide lands on the view it was sent to" "$(printf '%.0f' "$(sget viewx)")" $((vx + far))
    lines=$(perf_lines "$mark")
    assert_near "its slide line names the distance" "$(perf_val "$lines" slide dist)" "$far" 2
    arc=$(perf_val "$lines" slide arc)
    assert_true "it flew: the slide line names the arc's lowest zoom" -n "$arc"
    assert_true "and the camera eased well out ($arc)" "$(awk -v z="${arc:-1}" 'BEGIN { print (z > 0 && z < 0.6) }')" = 1
    assert_true "it took longer than a hop, under a second and a half ($(perf_val "$lines" slide ms) ms)" \
        "$(perf_val "$lines" slide ms)" -ge 250
    assert_true "and not too long" "$(perf_val "$lines" slide ms)" -lt 1500

    # The windows kept their plane spots: only the view moved.
    open_1to1
    c state
    assert_eq "the canvas opens at 1:1 after the fly" "$(sget zoom)" 1.0000
    assert_near "KCalc's plane spot is unchanged (x)" "$(eget KCalc x)" "$kx" 1
    assert_near "and (y)" "$(eget KCalc y)" "$ky" 1
    assert_near "and its frame is where the new view puts it" "$(eget KCalc fx)" $((kx - vx - far)) 1
    c cancel
    sleep 0.4

    # A short slide is still a slide: no arc.
    mark=$(wc -l <"$LOG")
    cmd "slide 600 0" >/dev/null 2>&1
    wait_closed_at $((vx + far + 600)) || true
    lines=$(perf_lines "$mark")
    assert_true "a short slide writes its slide line" -n "$(perf_val "$lines" slide dist)"
    assert_eq "and does not fly" "$(perf_val "$lines" slide arc)" ""

    # A fly re-aimed mid-way (the same destination asked again) carries on from where it is.
    cmd "slide $((-far - 600)) 0" >/dev/null 2>&1
    sleep 0.15
    cmd "slide 0 0" >/dev/null 2>&1
    wait_closed_at "$vx" || true
    assert_eq "a fly re-aimed mid-way lands on its view" "$(printf '%.0f' "$(sget viewx)")" "$vx"
    # A fly sent back mid-way turns round from the zoomed-out camera and lands at home.
    cmd "slide $far 0" >/dev/null 2>&1
    sleep 0.15
    cmd "slide $((-far)) 0" >/dev/null 2>&1
    wait_closed_at "$vx" || true
    assert_eq "a fly turned round mid-way lands where it was sent" "$(printf '%.0f' "$(sget viewx)")" "$vx"
    open_1to1
    c state
    assert_eq "at 1:1" "$(sget zoom)" 1.0000
    assert_near "with KCalc back where it was on the screen" "$(eget KCalc fx)" $((kx - vx)) 1
    c cancel
    sleep 0.3

    setcfg Perf false
    arrange >/dev/null
}
