# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a floated window steps aside for the focused window: once the focus settles on a window the float overlaps, the float glides to the nearest spot on the screen that clears it, and goes back when the focus moves to a window that leaves its spot free; a focus on a window that is not free (maximized) moves it nowhere and its undo brings it back, a hand move makes its new place its home, and with FloatDodge off it stays; with no room beside the focused window it takes the spot that hides the least of both, and goes back after; a focused float makes the other floats step aside too"

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

    # No room beside the focused window: sample.txt made 1500x850 at (200,100) leaves 200 px on
    # its left, 220 on its right and about a hundred above and below, and the 460x420 float fits
    # in none. It takes the spot that leaves the most of both on show (Logic.dodgeSpot's partial
    # step, worked out here from the nest's own work area), not where it was, wholly under.
    activate KCalc; sleep 1.2
    put sample.txt 200 100 1500 850
    put wallpaper 700 300 460 420
    local area want
    seq_=$((seq_ + 1))
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"wallpaper\") >= 0) { const a = workspace.clientArea(KWin.MaximizeArea, x); print(\"FDG_q$seq_ \" + [a.x, a.y, a.width, a.height].map(Math.round).join(\" \")); } });" 0.3
    area=$(grep -a "FDG_q$seq_ " "$LOG" | tail -1 | sed "s/.*FDG_q$seq_ //")
    want=$(node -e '
        const src = require("fs").readFileSync("effect/contents/ui/logic.js", "utf8");
        const L = new Function(src + "\nreturn { dodgeSpot };")();
        const [ax, ay, aw, ah] = process.argv[1].split(" ").map(Number);
        const r = (x, y, w, h) => ({ x: x, y: y, width: w, height: h });
        const s = L.dodgeSpot(r(700, 300, 460, 420), r(200, 100, 1500, 850), r(ax, ay, aw, ah), [], 12);
        console.log(s ? (s.partial ? "partial " : "clear ") + s.x + " " + s.y + " 460 420" : "none");' "$area")
    assert_eq "the premise: no spot clears the focused window on this work area ($area)" "${want%% *}" partial
    activate sample.txt; sleep 1.4
    assert_eq "no room to clear it: the float takes the spot that hides the least" "$(frame wallpaper)" "${want#partial }"
    assert_eq "and sample.txt itself did not move" "$(frame sample.txt)" "200 100 1500 850"
    activate KCalc; sleep 1.4
    assert_eq "the focus gone to a window clear of its home, the float goes back" "$(frame wallpaper)" "700 300 460 420"

    # A focused float is the focus like any other window: KCalc floated and focused, the other
    # float over it steps aside (it moved nothing until 2026-11-16), and KCalc stays put. The
    # un-maximize is the trigger (the focused window's new shape, no focus change).
    arrange >/dev/null
    activate KCalc; sleep 1.2
    float KCalc true
    put wallpaper 400 300 460 420
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) x.setMaximize(true, true); });' 0.6
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KCalc") >= 0) x.setMaximize(false, false); });' 0.6
    sleep 1.4
    local kc
    kc=$(frame KCalc)
    want=$(node -e '
        const src = require("fs").readFileSync("effect/contents/ui/logic.js", "utf8");
        const L = new Function(src + "\nreturn { dodgeSpot };")();
        const [ax, ay, aw, ah] = process.argv[1].split(" ").map(Number);
        const [kx, ky, kw, kh] = process.argv[2].split(" ").map(Number);
        const r = (x, y, w, h) => ({ x: x, y: y, width: w, height: h });
        const s = L.dodgeSpot(r(400, 300, 460, 420), r(kx, ky, kw, kh), r(ax, ay, aw, ah), [], 12);
        console.log(s ? s.x + " " + s.y + " 460 420" : "none");' "$area" "$kc")
    assert_eq "a focused float: the other float steps aside for it" "$(frame wallpaper)" "$want"
    assert_eq "and the focused float itself stays where it is" "$kc" "100 120 480 420"
    float KCalc false
    float wallpaper false
    arrange >/dev/null
}
