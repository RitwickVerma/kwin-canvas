# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the hover clock keeps running while the effect is reconfigured: debug commands sent during the rest (each one re-publishes HoverDelay) do not restart it, so the rest still lands"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    open_1to1
    c "zoom 0.5 960 540"
    local kx ky kw kh vx vy z sx sy
    kx=$(eget Konsole x); ky=$(eget Konsole y); kw=$(eget Konsole w); kh=$(eget Konsole h)
    for _ in 1 2 3 4 5 6 7 8 9 10; do c state; [ "$(sget cam)" = "-" ] && break; sleep 0.15; done
    vx=$(sget viewx); vy=$(sget viewy); z=$(sget zoom)
    read -r sx sy <<<"$(awk -v vx="$vx" -v vy="$vy" -v z="$z" -v kx="$kx" -v ky="$ky" -v kw="$kw" -v kh="$kh" 'BEGIN{
        printf "%d %d\n", (kx - vx) * z + kw * z * 0.5, (ky - vy) * z + kh * z * 0.5
    }')"
    input move "$sx" "$sy"
    # A state read every ~0.4 s for 4 s, none of them quiet for the 900 ms the
    # clock needs if each one restarts it. The reads are the point: a plugin
    # that restarts a running clock on every reconfigure never lets it fire.
    for _ in 1 2 3 4 5 6 7 8 9 10; do c state; sleep 0.1; done
    assert_eq "a rest that is polled still focuses Konsole" "$(head -1 <<<"$LAST_STATE" | grep -c 'focus=.*Konsole')" 1
    c cancel
}
