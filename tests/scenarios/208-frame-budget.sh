# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the frame budget: on a desk shaped like the maintainer's (two stacked outputs at scale 1.25, eleven windows in clusters, two of them floated), a zoom-to-fit open, a slide and a window drag in the overview keep every frame on time and create no scene item while the camera or the hand is moving (a rebuild on the frame path once cost a zoomed-out overview 650 ms a frame)"

# The Perf lines written since line $1 of the log.
since() { tail -n +"$(($1 + 1))" "$LOG" | grep -a "kwin-canvas perf: "; }
# "p95 max stalls moving" for the session that started after line $1.
budget() {
    local l; l=$(since "$1")
    local p95 max st mv
    p95=$(grep -a "perf: ticks" <<<"$l" | head -1 | grep -ao "p95=[0-9]*" | cut -d= -f2)
    max=$(grep -a "perf: ticks" <<<"$l" | head -1 | grep -ao "max=[0-9]*" | cut -d= -f2)
    st=$(grep -ac "perf: stall" <<<"$l")
    mv=$(grep -a "perf: built" <<<"$l" | head -1 | grep -ao "moving=[0-9]*" | cut -d= -f2)
    echo "${p95:-999} ${max:-999} ${st:-0} ${mv:-999}"
}
toggle_chord() { nq org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Toggle Canvas" >/dev/null 2>&1; }
# The budget. Items built while moving are deterministic and must be none. The
# frame times are the nest's: it renders in software (llvmpipe), so two scaled
# outputs cost the host's CPU what the real desktop's GPU does not, and a busy
# host adds noise. The limits are set to catch a rebuild on the frame path (650 ms
# frames once), not to grade a software renderer: p95 under 30 ms on one output
# and 60 ms on two, and no frame over 250 ms.
P95_MAX=30
MAX_MAX=250
check_budget() { # label mark
    local p95 max st mv
    read -r p95 max st mv <<<"$(budget "$2")"
    echo "# $1: p95=${p95}ms max=${max}ms stalls=$st built-while-moving=$mv"
    assert_true "$1: frames on time (p95 ${p95} ms)" "$p95" -le "$P95_MAX"
    assert_true "$1: no frame over ${MAX_MAX} ms (max ${max} ms)" "$max" -lt "$MAX_MAX"
    assert_eq "$1: no scene item built while moving" "$mv" 0
}

run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    c state >/dev/null
    local two=0
    if [ "$(sget screens)" = 2 ]; then
        two=1
        P95_MAX=60
        run kscreen-doctor output.Virtual-0.position.0,864 output.Virtual-1.position.480,0 output.Virtual-0.scale.1.25 output.Virtual-1.scale.1.25 >/dev/null 2>&1
    else
        run kscreen-doctor output.Virtual-0.scale.1.25 >/dev/null 2>&1
    fi
    sleep 3
    arrange >/dev/null
    # Six more windows, so the desk has eleven: separate Konsole processes, each
    # with its own title.
    local i
    for i in 1 2 3 4 5 6; do run konsole --separate --nofork -p tabtitle="Extra$i" -e sleep 900 >/dev/null; done
    sleep 4
    # Two clusters on the plane around the fixtures, and two floated windows.
    kwinjs 'var n = 0; workspace.stackingOrder.forEach(function (x) {
        if (String(x.caption).indexOf("Extra") < 0 || !x.normalWindow) return;
        var col = n % 3, row = Math.floor(n / 3); n++;
        x.frameGeometry = {x: 2300 + col * 540, y: 120 + row * 460, width: 500, height: 400}; });
        workspace.stackingOrder.forEach(function (x) { var c = String(x.caption);
        if (c.indexOf("KCalc") >= 0 || c.indexOf("Extra1") >= 0) x.onAllDesktops = true; });' 1.0
    # The knobs this sets are put back to what the nest had, not deleted: a deleted key falls
    # back to the effect's default, which is not the nest's (SmoothZoom is seeded false).
    local was_smooth was_open
    was_smooth=$(kreadconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key SmoothZoom --default __unset__)
    was_open=$(kreadconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key OpenZoom --default __unset__)
    setcfg SmoothZoom true
    setcfg OpenZoom fit
    setcfg Perf true
    c state >/dev/null
    sleep 1

    # A zoom-to-fit open through the chord, the camera flying out and resting.
    local mark; mark=$(wc -l <"$LOG")
    toggle_chord; sleep 2.5
    c state >/dev/null
    local n z; n=$(sget entries); z=$(sget zoom)
    echo "# fit zoom: $z"
    assert_true "the overview holds eleven windows or more ($n)" "${n:-0}" -ge 11
    toggle_chord; sleep 1.5
    check_budget "zoom-to-fit open" "$mark"

    # A slide at 1:1.
    mark=$(wc -l <"$LOG")
    c "slide 500 0" >/dev/null; sleep 2.0
    check_budget "slide" "$mark"

    # A window dragged by its title bar in the open overview at 1:1, inside its
    # cluster, in small steps as a hand would.
    open_1to1
    c state >/dev/null
    local vx vy kx ky
    vx=$(sget viewx); vy=$(sget viewy); kx=$(eget sample.txt x); ky=$(eget sample.txt y)
    local sx sy; sx=$(awk -v a="$kx" -v v="$vx" 'BEGIN{printf "%d", a - v + 200}'); sy=$(awk -v a="$ky" -v v="$vy" 'BEGIN{printf "%d", a - v + 14}')
    mark=$(wc -l <"$LOG")
    { printf 'move %d %d\nsleep 80\ndown left\n' "$sx" "$sy"; for i in $(seq 1 30); do printf 'move %d %d\nsleep 16\n' "$((sx + i * 4))" "$((sy + i * 2))"; done; printf 'up left\nsleep 200\n'; } | input
    sleep 0.5
    c cancel >/dev/null; sleep 1.2
    check_budget "window drag" "$mark"

    # Put the nest back: the floated windows, the extra windows, the scale and layout.
    kwinjs 'workspace.stackingOrder.forEach(function (x) { var c = String(x.caption);
        if (c.indexOf("KCalc") >= 0) x.onAllDesktops = false;
        if (c.indexOf("Extra") >= 0) x.closeWindow(); });' 1.0
    setcfg Perf false
    local k v
    for k in SmoothZoom OpenZoom; do
        [ "$k" = SmoothZoom ] && v=$was_smooth || v=$was_open
        if [ "$v" = __unset__ ]; then kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key "$k" --delete
        else kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key "$k" -- "$v"; fi
    done
    c state >/dev/null
    if [ "$two" = 1 ]; then
        run kscreen-doctor output.Virtual-0.position.0,0 output.Virtual-1.position.1920,0 output.Virtual-0.scale.1 output.Virtual-1.scale.1 >/dev/null 2>&1
    else
        run kscreen-doctor output.Virtual-0.scale.1 >/dev/null 2>&1
    fi
    sleep 3
    arrange >/dev/null
}
