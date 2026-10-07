# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the plane remembers the day: the camera's path draws itself on the ground as a faint fading trail, gone when the knob turns off and never at the 1:1 seam"

run_scenario() {
    source tests/lib.sh

    region_rmse() {
        magick "$1" -crop "$3" +repage "$OUT/trail-a.png"
        magick "$2" -crop "$3" +repage "$OUT/trail-b.png"
        { magick compare -metric RMSE "$OUT/trail-a.png" "$OUT/trail-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
    }
    changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }

    arrange >/dev/null
    open_1to1
    setcfg DayTrail true
    c "zoom 0.5 960 540"
    sleep 0.6
    shot "$OUT/trail-t0.png"

    # The pan carries the camera's centre from the canvas (960,540) down to
    # (960,-1860) - straight through bare ground below every fixture - so the
    # trail's visible stretch is the vertical line at the screen's centre.
    c "pan 0 1200"
    sleep 0.6
    c state
    if awk -v t="$(sget trail)" 'BEGIN{exit !(t+0 >= 2)}'; then
        ok "the path keeps its points"
    else
        fail "the path keeps its points"
    fi
    shot "$OUT/trail-t1.png"
    if [ "$(changed "$(region_rmse "$OUT/trail-t0.png" "$OUT/trail-t1.png" "20x200+950+560")")" = 1 ]; then
        ok "the trail draws itself on the ground"
    else
        fail "the trail draws itself on the ground"
    fi

    setcfg DayTrail false
    sleep 0.6
    shot "$OUT/trail-t2.png"
    if [ "$(changed "$(region_rmse "$OUT/trail-t1.png" "$OUT/trail-t2.png" "20x200+950+560")")" = 1 ]; then
        ok "and the knob takes it away"
    else
        fail "and the knob takes it away"
    fi

    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key DayTrail --delete
    c state >/dev/null
    c cancel
    arrange >/dev/null
}
