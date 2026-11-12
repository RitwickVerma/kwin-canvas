# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the window graph: Meta+Alt+arrows walk the focus to the next window that way inside its cluster and past the cluster's edge into the next cluster, the camera bringing it in; in the open canvas they step the selection; Meta+Alt+Shift+arrows carry the focused window into the next cluster, beside it on the side it arrives from, and carried straight back it lands on its exact spot; the threads are the walk's steps (a 2x2 cluster has four, not six) and the lit cluster's bridges out"

# plane(): every window's plane coordinate while the canvas is closed: its real frame plus the camera.
plane_of() {
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) print(\"GRPOS \" + x.frameGeometry.x + \" \" + x.frameGeometry.y); });" 0.4
    c state >/dev/null
    local vx vy; vx=$(sget viewx); vy=$(sget viewy)
    grep -a "GRPOS " "$STATE/kwin.log" | tail -1 | sed 's/.*GRPOS //' | awk -v vx="$vx" -v vy="$vy" '{printf "%.0f,%.0f", $1 + vx, $2 + vy}'
}
# appname: the application from a caption ("wallpaper.png - ... — Gwenview" is Gwenview).
appname() { sed 's/ canvas=.*//; s/.* — //'; }
focused() {
    kwinjs 'var a = workspace.activeWindow; print("GRACT " + (a ? String(a.caption) : "-"));' 0.3
    grep -a "GRACT " "$STATE/kwin.log" | tail -1 | sed 's/.*GRACT //' | appname
}
inside() {
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf(\"$1\") >= 0) { var g = x.frameGeometry; print(\"GRIN \" + (g.x >= 0 && g.y >= 0 && g.x + g.width <= workspace.virtualScreenSize.width && g.y + g.height <= workspace.virtualScreenSize.height ? \"yes\" : \"no \" + g.x + \",\" + g.y)); } });" 0.4
    grep -a "GRIN " "$STATE/kwin.log" | tail -1 | sed 's/.*GRIN //'
}
walkkey()  { printf 'key leftmeta down\nkey leftalt down\nkey %s\nkey leftalt up\nkey leftmeta up\n' "$1" | input; sleep 1.6; }
carrykey() { printf 'key leftmeta down\nkey leftalt down\nkey leftshift down\nkey %s\nkey leftshift up\nkey leftalt up\nkey leftmeta up\n' "$1" | input; sleep 1.8; }
selected() { c state >/dev/null; grep '^  \[[0-9][0-9]*\] \*' <<<"$LAST_STATE" | head -1 | sed 's/^  \[[0-9]*\] \*//' | appname; }

run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null
    # Two clusters: KCalc, sample.txt, Konsole and Dolphin as a 2x2 near the origin, and Gwenview
    # alone far to the right, past the nest's second activity frame (x 2160 to 4080), so it and
    # whatever is carried beside it stay on this activity.
    open_1to1
    c "placeby Gwenview 5000 300 460 420"
    c commit; sleep 0.5
    c state >/dev/null
    assert_eq "the plane holds two clusters" "$(sget clusters)" 2
    c "activate KCalc"; sleep 0.8

    # The walk, closed, with the real chords.
    walkkey right
    assert_eq "right from KCalc is sample.txt, in its cluster" "$(focused)" KWrite
    walkkey right
    assert_eq "right again leaves the cluster for the next one: Gwenview" "$(focused)" Gwenview
    assert_eq "and the camera brought it in" "$(inside Gwenview)" yes
    walkkey left
    assert_eq "left from Gwenview comes back to the window facing it" "$(focused)" KWrite
    walkkey down
    assert_eq "down from sample.txt is Dolphin" "$(focused)" Dolphin
    walkkey left
    assert_eq "left from Dolphin is Konsole" "$(focused)" Konsole

    # The threads, in the open canvas lit on that cluster: the 2x2's four sides (not its six
    # pairs), and the bridges from sample.txt and Dolphin to Gwenview.
    open_1to1; sleep 0.4
    c state >/dev/null
    assert_eq "the threads are the walk's steps: 4 in the cluster, 2 bridges out" "$(sget graph)" "4/2"
    # The walk in the open canvas steps the selection, and Enter would enter it.
    walkkey up
    assert_eq "open: up from Konsole selects KCalc" "$(selected)" KCalc
    assert_eq "and the canvas stays open" "$(sget visible)" true
    c cancel; sleep 0.8

    # The carry, closed: sample.txt into Gwenview's cluster, on its near (left) side, in its row.
    c "activate sample.txt"; sleep 0.8
    local before; before=$(plane_of sample.txt)
    assert_eq "sample.txt starts at its spot" "$before" "640,120"
    carrykey right
    assert_eq "carried right, sample.txt lands left of Gwenview, 24 px off, at its own height" "$(plane_of sample.txt)" "4276,120"
    assert_eq "and keeps the focus" "$(focused)" KWrite
    assert_eq "and the camera followed it" "$(inside sample.txt)" yes
    open_1to1; sleep 0.3; c state >/dev/null
    assert_eq "still two clusters: it joined Gwenview's" "$(sget clusters)" 2
    c cancel; sleep 0.8
    carrykey left
    assert_eq "carried straight back, it lands on its exact spot" "$(plane_of sample.txt)" "640,120"

    # A maximized window is not carried.
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Konsole") >= 0) { x.setMaximize(true, true); workspace.activeWindow = x; } });' 0.6
    carrykey right
    kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Konsole") >= 0) x.setMaximize(false, false); });' 0.6
    assert_eq "a maximized window stays where it is" "$(plane_of Konsole)" "100,600"

    c cancel >/dev/null 2>&1
    arrange >/dev/null
}
