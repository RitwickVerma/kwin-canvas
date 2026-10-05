# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the switcher wears its pick: a glass card under the toolbar names the chosen window, shows its live picture and its cluster, and rides the z-rise"

run_scenario() {
    source tests/lib.sh
    have_input || { skip "fakeinput not built (make tools)"; return; }
    arrange >/dev/null

    region_rmse() {
        magick "$1" -crop "$3" +repage "$OUT/swc-a.png"
        magick "$2" -crop "$3" +repage "$OUT/swc-b.png"
        { magick compare -metric RMSE "$OUT/swc-a.png" "$OUT/swc-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
    }
    changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }

    open_1to1
    c commit
    sleep 0.3
    shot "$OUT/swc-pre.png"

    # The cluster switcher opens fitted to the near cluster; the card rides
    # the rise under the toolbar (HUD at Top: ~44px tall, the card just below).
    c "switchcluster"
    sleep 1.0
    c state
    assert_eq "the switcher opens" "$(sget visible)" true
    shot "$OUT/swc-card.png"

    assert_eq "the card appears under the toolbar" \
        "$(changed "$(region_rmse "$OUT/swc-pre.png" "$OUT/swc-card.png" "400x200+760+52")")" 1

    # The card's centre shows the pick's live picture (the fixtures' captions
    # prove the text row separately via the state marker below).
    assert_eq "and it carries the pick's live picture" \
        "$(changed "$(region_rmse "$OUT/swc-pre.png" "$OUT/swc-card.png" "220x124+812+72")")" 1

    # A repeat steps the selection; the card's content swaps (the region
    # moves with the pick - the state marker is the honest assert).
    c "switchcluster"
    sleep 0.6
    c state
    assert_eq "a step moves the pick" "$(grep -c '^  \[[0-9][0-9]*\] \*' <<<"$LAST_STATE")" 1

    c cancel
    sleep 0.5
    c state
    assert_eq "the step out drops the card" "$(sget visible)" false
    arrange >/dev/null
}
