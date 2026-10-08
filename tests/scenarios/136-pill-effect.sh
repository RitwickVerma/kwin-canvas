# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

scenario_desc="the effect's one pill: the pointer riding a window's top edge on the closed desktop quietly opens the seam and draws the pill there, and the pointer leaving closes it again"

run_scenario() {
    source tests/lib.sh
    region_rmse() {
        magick "$1" -crop "$3" +repage "$OUT/p-a.png"
        magick "$2" -crop "$3" +repage "$OUT/p-b.png"
        { magick compare -metric RMSE "$OUT/p-a.png" "$OUT/p-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
    }
    changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }

    arrange >/dev/null
    open_1to1; c commit; sleep 0.3
    shot "$OUT/p-pre.png"

    # The pointer rides KCalc's top edge: the frame (100,120), the plugin's
    # band reaches from 36px above the top to 14px below, so (340,100) is
    # well inside it and horizontally inside the frame (100..580).
    { printf 'move 340 100\nsleep 400\n'; } | input
    sleep 0.8
    c state
    assert_eq "the pill opens the seam" "$(sget visible)" true
    assert_eq "quietly" "$(head -1 <<<"$LAST_STATE" | grep -c ' quiet')" 1
    assert_eq "and targets the window" "$(sget pill)" 1
    shot "$OUT/p-on.png"
    if [ "$(changed "$(region_rmse "$OUT/p-pre.png" "$OUT/p-on.png" "100x24+284+88")")" = 1 ]; then
        ok "the pill draws its glass over the desktop"
    else
        fail "the pill draws its glass over the desktop"
    fi

    # The pointer leaves: the target clears and the pill closes the seam it
    # opened, leaving the desktop untouched.
    input move 1700 1000
    sleep 0.8
    c state
    assert_eq "the pill closes its seam" "$(sget visible)" false

    # Any edge: the pill rides the bottom, the left and the right bands too
    # (the target reports the edge, the pill hugs whichever one).
    { printf 'move 340 550\nsleep 400\n'; } | input
    sleep 0.8
    c state
    assert_eq "the bottom edge brings the pill" "$(sget pill)" 1
    input move 1700 1000
    sleep 0.8
    { printf 'move 70 330\nsleep 400\n'; } | input
    sleep 0.8
    c state
    assert_eq "the left edge brings the pill" "$(sget pill)" 1
    input move 1700 1000
    sleep 0.8
    { printf 'move 590 330\nsleep 400\n'; } | input
    sleep 0.8
    c state
    assert_eq "the right edge brings the pill" "$(sget pill)" 1
    input move 1700 1000
    sleep 0.8

    # The grab: the pill's empty stretch (its leftmost cell) is the drag
    # handle - the window rides the pointer, the real frame moving with it.
    # The pill travels its edge to the pointer, so the press must ride
    # INTO the frozen pill (the pointer inside the pill keeps it put):
    # the first move parks at the edge (the pill appears at that x), the
    # second steps onto the grab cell - 60px left of the pill's centre.
    { printf 'move 280 105\nsleep 300\nmove 220 105\nsleep 200\ndown left\nsleep 200\nglide 440 105 10 20\nsleep 200\nup left\n'; } | input
    sleep 1.2
    # The entries snapshot the frames at the last resync; re-open so the
    # effect reads the frame the grab moved.
    c cancel
    open_1to1
    c state
    assert_near "the grab drags the window" "$(eget KCalc fx)" 320 20
    input move 1700 1000
    sleep 0.8
    c cancel

    # The pill never paints over another window: KWrite overlaps KCalc's
    # bottom edge, so the covered stretch hides the pill and the clear
    # stretch shows it. The pill lives on the closed desktop - the quiet
    # seam - so this part runs there (the grab's tail already cancelled).
    c "placeby sample.txt 400 100 700 520"
    c commit
    sleep 0.3
    c state
    echo "DBG-NEWPART: kcalc-fx=$(eget KCalc fx) kwrite-fx=$(eget sample.txt fx) kwrite-fy=$(eget sample.txt fy)"
    input move 480 550
    sleep 0.6
    c state
    assert_eq "the covered stretch hides the pill" "$(sget pill)" 0
    # The clear stretch: KCalc's left edge (the grab parked the window at
    # 320, and KWrite covers its bottom rightward of 400).
    input move 300 450
    sleep 0.6
    c state
    assert_eq "the clear stretch shows it again" "$(sget pill)" 1
    input move 1700 1000
    sleep 0.8
    c cancel
    arrange >/dev/null
}
