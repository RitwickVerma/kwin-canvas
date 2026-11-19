# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the canvas remembers where windows were on the plane: while a login brings the apps back (the effect loaded afresh), a starting app's window goes back to its spot, off the screen too, and the camera stays; a running app's second window, a dialog, and any app opened once the login is over open where KDE puts them, and RestoreSpots off leaves every window to KDE"
run_scenario() {
    source tests/lib.sh
    local ksel=KCharSelect key=org.kde.kcharselect dlg="kwin-canvas spot dialog"
    # The window's real frame, "x y w h" (the first of its windows).
    geom() { js "for (const w of workspace.windowList()) if (w.normalWindow && String(w.caption).indexOf('$ksel') >= 0) out(Math.round(w.frameGeometry.x) + ' ' + Math.round(w.frameGeometry.y) + ' ' + Math.round(w.frameGeometry.width) + ' ' + Math.round(w.frameGeometry.height))" | head -1; }
    # Move a window, at its own size, as a script would.
    place() { kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf('${3:-$ksel}') >= 0) x.frameGeometry = {x: $1, y: $2, width: x.frameGeometry.width, height: x.frameGeometry.height}; });" 0.5; }
    closeall() {
        kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf('$ksel') >= 0) x.closeWindow(); });" 0.5
        local i; for i in $(seq 1 20); do [ -z "$(geom)" ] && break; sleep 0.3; done
    }
    # The book's record of a window, "x y": what the canvas wrote to the config. The app key, or
    # "*" for any app's record with that caption.
    record() {
        kreadconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key WindowSpots | python3 -I -c '
import json, sys
try: b = json.load(sys.stdin)
except Exception: b = {}
lists = b.values() if sys.argv[1] == "*" else [b.get(sys.argv[1], [])]
r = [x for l in lists for x in l if sys.argv[2] in x.get("c", "")]
print("%d %d" % (r[0]["x"], r[0]["y"]) if r else "")' "${1:-$key}" "${2:-$ksel}"
    }
    # Whether any of the app's records is at "x y": 1 or 0.
    holds() {
        kreadconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key WindowSpots | python3 -I -c '
import json, sys
try: b = json.load(sys.stdin)
except Exception: b = {}
print(1 if any("%d %d" % (x["x"], x["y"]) == sys.argv[2] for x in b.get(sys.argv[1], [])) else 0)' "$key" "$1"
    }
    launch() {
        local n; n=$(nwindows)
        run kcharselect >/dev/null 2>&1
        mapped $((n + 1)) || echo "231: kcharselect did not map in time" >&2
        # The restore runs 900 ms after the window appears.
        sleep 2.5
    }
    view() { c state; vx=$(sget viewx); vx=${vx%.*}; vy=$(sget viewy); vy=${vy%.*}; }
    onscreen() { [ "$1" -ge 0 ] && [ "$1" -lt "$WIDTH" ] && [ "$2" -ge 0 ] && [ "$2" -lt "$HEIGHT" ] && echo 1 || echo 0; }
    local vx vy gx gy r

    arrange >/dev/null
    # A camera away from the origin, so a plane spot and a real frame differ.
    c "slide 2000 700" >/dev/null; sleep 1.5
    setcfg RestoreSpots true
    launch
    view
    assert_eq "an app the book does not know opens as KDE places it" "$(sget restored)" 0
    # Parked off the screen, as the canvas parks windows: its plane spot is real + camera.
    place $((WIDTH + 1500)) -900
    sleep 4
    r=$(record)
    assert_eq "the book has the window's plane spot a few seconds after it moved" "$r" "$((WIDTH + 1500 + vx)) $((-900 + vy))"

    # A login: the window closed, the effect loaded afresh, the app started.
    local bvx=$vx bvy=$vy
    closeall
    assert_eq "a closed window's spot stays in the book" "$(record)" "$r"
    # The closed desk's camera is written a moment after its last landing (the slide above).
    sleep 2.5
    nq org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect kwin-canvas >/dev/null 2>&1
    sleep 0.5
    nq org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect kwin-canvas >/dev/null 2>&1
    local i; for i in $(seq 1 40); do c state; [ -n "$(sget visible)" ] && break; sleep 0.25; done
    view
    local lvx=$vx lvy=$vy
    assert_eq "the effect comes back at the camera the closed desk was left at (x)" "$lvx" "$bvx"
    assert_eq "and (y)" "$lvy" "$bvy"
    assert_true "the book survives the effect's reload" "$(sget spots)" -ge 1
    assert_eq "a freshly loaded effect is bringing a login's windows back" "$(sget restoring)" 1
    launch
    view
    assert_eq "the login's starting app's window was put back" "$(sget restored)" 1
    read -r gx gy _ _ <<<"$(geom)"
    assert_eq "at its plane spot" "$((gx + vx)) $((gy + vy))" "$r"
    assert_eq "and the camera did not fly to it (x)" "$vx" "$lvx"
    assert_eq "and (y)" "$vy" "$lvy"
    assert_eq "so the window waits off the screen" "$(onscreen "$gx" "$gy")" 0

    # A running app's next window is a new one.
    launch
    view
    assert_eq "a second window of a running app is not put back" "$(sget restored)" 1

    # A dialog is not an app's own window: it has no spot, and is never put back.
    local n; n=$(nwindows)
    run kdialog --title "$dlg" --msgbox "$dlg" >/dev/null 2>&1
    mapped $((n + 1)) || echo "231: kdialog did not map in time" >&2
    sleep 1.5
    echo "   kdialog: $(js "for (const w of workspace.windowList()) if (String(w.caption).indexOf('$dlg') >= 0) out('normal=' + w.normalWindow + ' dialog=' + w.dialog + ' transient=' + w.transient + ' modal=' + w.modal + ' class=' + w.resourceClass)" | head -1)"
    place -1800 400 "$dlg"
    sleep 4
    assert_eq "a dialog gets no spot in the book" "$(record '*' "$dlg")" ""
    kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf('$dlg') >= 0) x.closeWindow(); });" 0.5

    # RestoreSpots off: KDE's placement, the book untouched.
    closeall
    setcfg RestoreSpots false
    launch
    view
    assert_eq "with RestoreSpots off nothing is put back" "$(sget restored)" 1
    read -r gx gy _ _ <<<"$(geom)"
    assert_eq "and the window opens on the screen" "$(onscreen "$gx" "$gy")" 1
    closeall
    setcfg RestoreSpots true

    # Once the login is over, an app opened again opens where KDE puts it, in front of the hand
    # that asked for it: not at its old spot, and the desk does not slide away after it.
    for i in $(seq 1 120); do c state; [ "$(sget restoring)" = 0 ] && break; sleep 1; done
    assert_eq "the login's restore ends" "$(sget restoring)" 0
    assert_eq "the book still has the window's spot" "$(holds "$r")" 1
    view
    local mvx=$vx mvy=$vy
    launch
    view
    assert_eq "an app opened after the login is not put back" "$(sget restored)" 1
    read -r gx gy _ _ <<<"$(geom)"
    assert_eq "it opens on the screen" "$(onscreen "$gx" "$gy")" 1
    assert_eq "and the desk stays where it was (x)" "$vx" "$mvx"
    assert_eq "and (y)" "$vy" "$mvy"

    closeall
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key WindowSpots --delete
    rm -f "$CONF"/kcharselectrc
    arrange >/dev/null
}
