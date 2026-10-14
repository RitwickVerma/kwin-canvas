# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the end of a slide shows no stale frame: a screenshot taken across the landing, many times, never catches the scene at its last position with black where the frame left"
black() { magick "$1" -colorspace Gray -threshold 1% -negate -format '%[fx:mean]' info:; }
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg PanDuration 400
    local i off b hits=0 n=40
    for i in $(seq 1 "$n"); do
        off=$((330 + (i % 8) * 25))
        cmd "slide 0 0" >/dev/null 2>&1; sleep 0.5
        ( sleep "0.$(printf '%03d' "$off")"; shot "$OUT/landing.png" >/dev/null 2>&1 ) &
        cmd "slide 300 100" >/dev/null 2>&1; sleep 1.4
        cmd "slide -300 -100" >/dev/null 2>&1; sleep 1.1
        wait
        b=$(black "$OUT/landing.png")
        if awk -v b="$b" 'BEGIN{exit !(b > 0.03)}'; then hits=$((hits + 1)); fi
    done
    echo "# stale frames across the landing: $hits of $n"
    assert_eq "no slide landing showed a stale frame" "$hits" 0
    setcfg PanDuration 220
    c state
    arrange >/dev/null
}
