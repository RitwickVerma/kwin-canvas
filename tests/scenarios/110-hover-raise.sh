# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the hover raises for real: a rest in the overworld puts the window on top of the canvas and of KWin's real stacking together, and the raise survives the step back in"
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
    assert_eq "KCalc starts on top" "$(awk '/^  \[/{e=$0} END{print e}' <<<"$LAST_STATE" | grep -c KCalc)" 1
    # Rest on Konsole, which the fixtures stack below KCalc, Gwenview and
    # Dolphin: the settle raises it in the canvas and in KWin together.
    input move "$sx" "$sy"
    sleep 1.2; c state
    assert_eq "the rest focused Konsole" "$(head -1 <<<"$LAST_STATE" | grep -c 'focus=.*Konsole')" 1
    assert_eq "and the canvas put it on top" "$(awk '/^  \[/{e=$0} END{print e}' <<<"$LAST_STATE" | grep -c Konsole)" 1
    assert_eq "and the real stacking agrees" "$(c list; grep -a '^  \*' <<<"$LAST_STATE" | tail -1 | grep -c Konsole)" 1
    # Step back in: the raise was the desktop's, so it survives the commit.
    c home
    for _ in 1 2 3 4 5 6 7 8 9 10; do c state; [ "$(sget cam)" = "-" ] && break; sleep 0.15; done
    c commit
    sleep 0.5
    c list
    assert_eq "the raise survived the step back in" "$(grep -a '^  \*' <<<"$LAST_STATE" | tail -1 | grep -c Konsole)" 1
    c cancel
}
