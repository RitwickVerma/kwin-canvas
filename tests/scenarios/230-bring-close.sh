# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the arrange menu's Bring here fetches the selection to the middle of the screen, keeping each window's place in it, as one undo step; and Close (the Delete key) asks the selected window to close as its own close button would, with nothing else moved"
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    open_1to1
    c state
    local kx ky gx gy dx0
    kx=$(eget KCalc x); ky=$(eget KCalc y); gx=$(eget Gwenview x); gy=$(eget Gwenview y)
    dx0=$(eget Dolphin x)
    # The camera goes away: KCalc and Gwenview are now far off the screen.
    c "panpx -3000 -1200" >/dev/null; sleep 0.6; c state
    local cvx cvy; cvx=$(sget viewx); cvy=$(sget viewy)
    c "select $(eget KCalc index)"
    c "selectadd $(eget Gwenview index)"
    c bringhere; sleep 0.8; c state
    # The two together: their box comes to the middle of the screen, each keeping its place in it.
    local nkx nky ngx ngy
    nkx=$(eget KCalc x); nky=$(eget KCalc y); ngx=$(eget Gwenview x); ngy=$(eget Gwenview y)
    local mid
    mid=$(awk -v a="$nkx" -v aw="$(eget KCalc w)" -v b="$ngx" -v bw="$(eget Gwenview w)" -v v="$cvx" -v w="$WIDTH" \
        'BEGIN { l = a < b ? a : b; r = a + aw > b + bw ? a + aw : b + bw; printf "%.0f", (l + r) / 2 - (v + w / 2) }')
    assert_near "Bring here puts the selection's box in the middle of the screen (x)" "$mid" 0 2
    mid=$(awk -v a="$nky" -v ah="$(eget KCalc h)" -v b="$ngy" -v bh="$(eget Gwenview h)" -v v="$cvy" -v h="$HEIGHT" \
        'BEGIN { t = a < b ? a : b; d = a + ah > b + bh ? a + ah : b + bh; printf "%.0f", (t + d) / 2 - (v + h / 2) }')
    assert_near "and (y)" "$mid" 0 2
    assert_eq "each window keeps its place in it (x)" $((ngx - nkx)) $((gx - kx))
    assert_eq "and (y)" $((ngy - nky)) $((gy - ky))
    assert_eq "nothing else came along" "$(eget Dolphin x)" "$dx0"
    # One undo step (the open canvas's move history, which the state line does not show): a single
    # undo puts both back.
    c undo; sleep 0.8; c state
    assert_eq "one undo puts KCalc back (x)" "$(eget KCalc x)" "$kx"
    assert_eq "and (y)" "$(eget KCalc y)" "$ky"
    assert_eq "and Gwenview with it (x)" "$(eget Gwenview x)" "$gx"
    assert_eq "and (y)" "$(eget Gwenview y)" "$gy"
    c clearsel
    c bringhere; sleep 0.3; c state
    assert_eq "with nothing selected nothing moves" "$(eget KCalc x)" "$kx"
    c cancel >/dev/null; sleep 0.6

    # Close: a window of its own, so the fixtures stay five.
    local n; n=$(nwindows)
    run kcalc >/dev/null 2>&1
    mapped $((n + 1)) || echo "230: the second kcalc did not map in time" >&2
    sleep 1
    open_1to1
    c state
    local idx; idx=$(grep -a "^  \[[0-9]*\] .*KCalc" <<<"$LAST_STATE" | tail -1 | sed -n 's/^  \[\([0-9]*\)\].*/\1/p')
    assert_true "a second KCalc is on the canvas" -n "$idx"
    c "select $idx"
    c closesel
    local i
    for i in $(seq 1 15); do sleep 0.3; [ "$(nwindows)" = "$n" ] && break; done
    assert_eq "Close closed the selected window" "$(nwindows)" "$n"
    # The canvas lets go of a closed window's entry at its next resync (a second at most).
    sleep 1.2; c state
    assert_eq "the fixtures are all still there" "$(sget entries)" 5
    c cancel >/dev/null
    rm -f "$CONF"/kcalcrc
    arrange >/dev/null
}
