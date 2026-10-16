# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the float across interactions: unpinning while the picture rides the edge leaves the window where the eye saw it, a screen-sized floated window leaves the canvas flush, and the picture stays inside the screen through zoom, pan and a drag"
# The picture's screen spot and size for KCalc, from the state line: its
# canvas spot in view coordinates plus the float's offset.
picture() { # -> "x y w h"
    c state >/dev/null
    # The state prints a negative offset as "+-N"; awk reads that as 0.
    local line; line=$(grep -a "KCalc canvas=" <<<"$LAST_STATE" | head -1 | sed 's/+-/-/g; s/+\([0-9]\)/\1/g')
    awk -v L="$line" -v vx="$(sget viewx)" -v vy="$(sget viewy)" -v z="$(sget zoom)" 'BEGIN{
        match(L, /canvas=\(-?[0-9.]+,-?[0-9.]+ [0-9]+x[0-9]+\)/); s = substr(L, RSTART + 8, RLENGTH - 9);
        split(s, a, /[, x]/); cx = a[1]; cy = a[2]; w = a[3]; h = a[4];
        fx = 0; fy = 0;
        if (match(L, /float=\([+-]?[0-9.-]+,[+-]?[0-9.-]+\)/)) { f = substr(L, RSTART + 7, RLENGTH - 8); split(f, b, ","); fx = b[1] + 0; fy = b[2] + 0 }
        printf "%.1f %.1f %.1f %.1f", (cx - vx) * z + fx, (cy - vy) * z + fy, w * z, h * z }'
}
inside() { # picture is wholly inside the 1920x1080 screen?
    read -r px py pw ph <<<"$(picture)"
    awk -v x="$px" -v y="$py" -v w="$pw" -v h="$ph" 'BEGIN{print (x >= -1 && y >= -1 && x + w <= 1921 && y + h <= 1081) ? "yes" : "no " x " " y " " w " " h}'
}
frame() { # KCalc's real frame: "x y w h"
    kwinjs 'var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) w = x; }); var g = w.frameGeometry; print("MATRIXFRAME " + Math.round(g.x) + " " + Math.round(g.y) + " " + Math.round(g.width) + " " + Math.round(g.height));' 0.6
    grep -a "MATRIXFRAME" "$STATE/kwin.log" | tail -1 | sed 's/.*MATRIXFRAME //'
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    open_1to1
    c state >/dev/null
    local k; k=$(eget KCalc index)
    c "pin $k"
    sleep 0.3
    # Unpin while the picture rides the edge: the window stays where it was seen.
    c "panpx -900 0" >/dev/null
    sleep 1
    assert_eq "pinned and pushed out, the picture rides inside the screen" "$(inside)" yes
    c "unpin $k"
    sleep 0.8
    assert_eq "unpinned there, the window is still wholly on screen" "$(inside)" yes
    c cancel >/dev/null 2>&1
    arrange >/dev/null
    # The picture stays inside through zoom and pan.
    open_1to1
    c state >/dev/null; k=$(eget KCalc index)
    c "pin $k"
    local z
    for z in 0.8 0.5 0.3; do
        c "zoom $z 960 540" >/dev/null
        c "panpx 700 -400" >/dev/null
        sleep 0.7
        assert_eq "inside at zoom $z after a pan" "$(inside)" yes
    done
    c "panpx -5000 3000" >/dev/null
    sleep 0.7
    assert_eq "inside after a far jump" "$(inside)" yes
    c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
    # A screen-sized floated window leaves the canvas flush, not 8 px off.
    c "placeby KCalc 0 0 1920 1080" >/dev/null
    sleep 0.6
    open_1to1
    c state >/dev/null; k=$(eget KCalc index)
    c "pin $k"
    c "panpx -400 -300" >/dev/null
    sleep 0.8
    c enter >/dev/null
    sleep 1.5
    assert_eq "a screen-sized floated window lands flush at the origin" "$(frame)" "0 0 1920 1080"
    c state >/dev/null; k=$(eget KCalc index); c "unpin $k"
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
