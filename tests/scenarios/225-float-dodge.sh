# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a floated window steps aside for the focused window: once the focus settles on a window the float overlaps, the float glides to the nearest spot on the screen that clears it, and goes back when the focus moves to a window that leaves its spot free; with FloatDodge off it stays"

# frame CAPTION: "x y w h" of the window whose caption holds CAPTION.
seq_=0
frame() {
    seq_=$((seq_ + 1))
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) print(\"FDG_q$seq_ \" + [x.frameGeometry.x, x.frameGeometry.y, x.frameGeometry.width, x.frameGeometry.height].map(Math.round).join(\" \")); });" 0.3
    grep -a "FDG_q$seq_ " "$LOG" | tail -1 | sed "s/.*FDG_q$seq_ //"
}
activate() { kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) workspace.activeWindow = x; });" 0.3; }
float() { kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) x.onAllDesktops = $2; });" 0.4; }
put() { kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) x.frameGeometry = {x: $2, y: $3, width: $4, height: $5}; });" 0.5; }

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    # The arrange: KCalc (100,120 480x420), sample.txt (640,120 700x520). Gwenview floats at
    # (1000,250 460x420), over sample.txt's right half and clear of KCalc.
    float wallpaper true
    put wallpaper 1000 250 460 420
    activate KCalc; sleep 1.2
    assert_eq "the focus on a window the float does not overlap moves nothing" "$(frame wallpaper)" "1000 250 460 420"
    activate sample.txt; sleep 1.4
    # Nearest way out: right of sample.txt, 12 px past its edge (1340 + 12), the height held.
    assert_eq "the focus settled on sample.txt: the float stepped right, clear of it" "$(frame wallpaper)" "1352 250 460 420"
    assert_eq "and sample.txt itself did not move" "$(frame sample.txt)" "640 120 700 520"
    activate KCalc; sleep 1.4
    assert_eq "the focus moved to a window clear of its spot: the float went back" "$(frame wallpaper)" "1000 250 460 420"
    setcfg FloatDodge false
    activate sample.txt; sleep 1.4
    assert_eq "FloatDodge off: the float stays over the focused window" "$(frame wallpaper)" "1000 250 460 420"
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key FloatDodge --delete
    c state >/dev/null
    float wallpaper false
    arrange >/dev/null
}
