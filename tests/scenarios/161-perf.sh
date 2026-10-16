# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="with Perf on, an open writes the open, first-paint and settle lines (and the ticks line on the close) with sane figures, a quiet slide writes its slide line; with Perf off none of them is written"
# perf_lines FROM: the "kwin-canvas perf:" lines the log gained after line FROM.
perf_lines() { tail -n +"$(($1 + 1))" "$LOG" | grep -a "kwin-canvas perf: " | sed 's/.*kwin-canvas perf: //'; }
# perf_val LINES EVENT KEY: the number after KEY= on EVENT's first line.
perf_val() { grep -a "^$2\( \|$\)" <<<"$1" | head -1 | sed -n "s/.* $3=\([-0-9.]*\).*/\1/p"; }
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom true
    setcfg BorderZoom fit
    setcfg OpenZoom fit
    setcfg Perf true
    c cancel; sleep 0.6
    local mark lines v
    mark=$(wc -l <"$LOG")
    c open; sleep 2.5
    c state
    assert_eq "the canvas opened" "$(sget visible)" true
    c cancel; sleep 0.8
    lines=$(perf_lines "$mark")
    assert_true "the open line is written" "$(grep -ac '^open$' <<<"$lines")" -ge 1
    v=$(perf_val "$lines" first-paint ms)
    assert_true "first-paint carries a number" -n "$v"
    assert_true "first-paint is under 5 s" "${v:-99999}" -lt 5000
    v=$(perf_val "$lines" settle ms)
    assert_true "settle carries a number" -n "$v"
    assert_true "the open settled within 5 s" "${v:-99999}" -lt 5000
    # OpenZoom fit steps out: the settle is the camera arriving at the fit
    # zoom, so it names a zoom below 1 and takes longer than the first paint.
    assert_true "settle names the zoom it settled at, below 1:1" "$(awk -v z="$(perf_val "$lines" settle zoom)" 'BEGIN { print (z > 0 && z < 0.99) }')" = 1
    assert_true "and the settle comes after the first paint" "$(perf_val "$lines" settle ms)" -ge "$(perf_val "$lines" first-paint ms)"
    assert_eq "settle is logged once per open" "$(grep -ac '^settle ' <<<"$lines")" 1
    v=$(perf_val "$lines" ticks n)
    assert_true "the close wrote the tick summary" -n "$v"
    assert_true "the p50 tick spacing is a frame or so" "$(perf_val "$lines" ticks p50)" -ge 1
    assert_true "and max is no less than p95" "$(perf_val "$lines" ticks max)" -ge "$(perf_val "$lines" ticks p95)"
    # A quiet slide is not an open of the canvas, but it is a slide.
    mark=$(wc -l <"$LOG")
    cmd "slide 600 0" >/dev/null 2>&1; sleep 1.8
    lines=$(perf_lines "$mark")
    v=$(perf_val "$lines" slide ms)
    assert_true "the slide line carries its time" -n "$v"
    assert_true "and the time is under 5 s" "${v:-99999}" -lt 5000
    assert_near "and its distance" "$(perf_val "$lines" slide dist)" 600 2
    cmd "slide -600 0" >/dev/null 2>&1; sleep 1.8
    # Off: the same open writes none of it.
    setcfg Perf false
    c cancel; sleep 0.6
    mark=$(wc -l <"$LOG")
    c open; sleep 2.0
    c cancel; sleep 0.8
    assert_eq "with Perf off no perf line is written" "$(perf_lines "$mark" | wc -l)" 0
    setcfg BorderZoom 0.8
    setcfg OpenZoom 1
}
