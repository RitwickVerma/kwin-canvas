# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the canvas decoration is the invisible frame: the window wears nothing above its client - no title bar, no pill - the band over the top edge stays the desktop; the pill belongs to the effect (scenario 136)"

region_rmse() {
    magick "$1" -crop "$3" +repage "$OUT/135-a.png"
    magick "$2" -crop "$3" +repage "$OUT/135-b.png"
    { magick compare -metric RMSE "$OUT/135-a.png" "$OUT/135-b.png" null: 2>&1 || true; } \
        | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}

changed() {
    awk -v m="$1" 'BEGIN{print (m > 0.005)}'
}

run_scenario() {
    source tests/lib.sh
    # The bare desktop first, then the arranged fixtures: the band above
    # each window's client must stay the desktop - the decoration draws
    # nothing there, so the pre/post pictures agree in that strip.
    shot "$OUT/135-pre.png"
    arrange >/dev/null
    sleep 1.5
    shot "$OUT/135-post.png"
    m=$(region_rmse "$OUT/135-pre.png" "$OUT/135-post.png" "80x24+300+120")
    assert_eq "the window wears nothing above its client" "$(changed "$m")" 0
    arrange >/dev/null
}
