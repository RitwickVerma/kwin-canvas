# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="a quiet slide never shows black where its frame has left: the wallpaper is drawn under the plane, so the landing is not a flash"
black() { # file -> fraction of near-black pixels
    magick "$1" -colorspace Gray -threshold 1% -negate -format '%[fx:mean]' info:
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg PanDuration 6000
    c state >/dev/null
    cmd "slide 1200 300" >/dev/null 2>&1
    sleep 4.5
    shot "$OUT/slide-late.png" >/dev/null 2>&1
    local late; late=$(black "$OUT/slide-late.png")
    echo "# black fraction late in the slide: $late"
    assert_eq "no black where the frame has left" "$(awk -v b="$late" 'BEGIN{print (b < 0.02)}')" 1
    sleep 3
    setcfg PanDuration 220
    c state
    arrange >/dev/null
}
