# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the canvas follows the global animation speed: the effect reads AnimationDurationFactor (NEST_ANIM starts the nest at one), and the slide's length is its usual length times that factor"
run_scenario() {
    source tests/lib.sh
    c state >/dev/null
    local want="${NEST_ANIM:-1}" got
    got=$(sed -n '1s/.* anim=\([0-9.]*\).*/\1/p' <<<"$LAST_STATE")
    assert_eq "the effect read the global animation factor" "$got" "$(awk -v w="$want" 'BEGIN{printf "%.2f", w}')"
    setcfg SmoothZoom true
    setcfg Perf true
    arrange >/dev/null
    local mark ms
    mark=$(wc -l <"$LOG")
    c "slide 500 0" >/dev/null; sleep $(awk -v w="$want" 'BEGIN{printf "%.1f", 1.5 + 0.4 * w}')
    ms=$(tail -n +"$((mark + 1))" "$LOG" | grep -a "perf: slide" | sed -n 's/.* ms=\([0-9]*\).*/\1/p' | head -1)
    # 500 px is a quarter of a screen's diagonal-ish: the reference length is 220 ms x 0.8..1.5, so the
    # measured wall-clock (a frame or two over) divided by the factor sits in that band.
    assert_true "the slide ran in about its usual time times the factor ($ms ms at $want)" "$(awk -v m="${ms:-0}" -v w="$want" 'BEGIN{r = m / w; print (r >= 150 && r <= 420)}')" = 1
    setcfg Perf false
    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
