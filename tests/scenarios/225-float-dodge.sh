# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a floated window steps aside for the focused window: once the focus settles on a window the float overlaps, the float glides to the nearest spot on the screen that clears it, and goes back when the focus moves to a window that leaves its spot free; a focus on a window that is not free (maximized) moves it nowhere and its undo brings it back, a hand move makes its new place its home, and with FloatDodge off it stays"

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
    # A focus that is not a free window (a maximized one here; a launcher or a panel alike)
    # moves no float, not even home.
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) { x.setMaximize(true, true); workspace.activeWindow = x; } });' 0.4
    sleep 1.4
    assert_eq "the focus on a maximized window leaves the float where it stepped to" "$(frame wallpaper)" "1352 250 460 420"
    # KCalc keeps the focus and takes its own size back: no focus change, but the floats look
    # again, and its spot is clear of the float's home.
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) x.setMaximize(false, false); });' 0.6
    sleep 1.4
    assert_eq "the focused window un-maximized, clear of the float's spot: the float went back" "$(frame wallpaper)" "1000 250 460 420"
    # Moved by another hand after it stepped aside, the float's new place is its home.
    activate sample.txt; sleep 1.4
    put wallpaper 1100 700 460 300
    activate KCalc; sleep 1.4
    assert_eq "a float moved by the hand after stepping aside stays where the hand put it" "$(frame wallpaper)" "1100 700 460 300"
    put wallpaper 1000 250 460 420
    setcfg FloatDodge false
    activate sample.txt; sleep 1.4
    assert_eq "FloatDodge off: the float stays over the focused window" "$(frame wallpaper)" "1000 250 460 420"
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key FloatDodge --delete
    c state >/dev/null
    float wallpaper false
    arrange >/dev/null
}
