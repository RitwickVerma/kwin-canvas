# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the canvas remembers where windows were on the plane: a starting app's window goes back to its spot, off the screen too, when the app is closed and opened again (the desk slides to it) and after the effect loads afresh as at a login (the camera stays); a running app's second window opens where KDE puts it, and RestoreSpots off leaves every window to KDE"
run_scenario() {
    source tests/lib.sh
    local ksel=KCharSelect key=org.kde.kcharselect
    # The window's real frame, "x y w h" (the first of its windows).
    geom() { js "for (const w of workspace.windowList()) if (w.normalWindow && String(w.caption).indexOf('$ksel') >= 0) out(Math.round(w.frameGeometry.x) + ' ' + Math.round(w.frameGeometry.y) + ' ' + Math.round(w.frameGeometry.width) + ' ' + Math.round(w.frameGeometry.height))" | head -1; }
    # Move it, at its own size, as a script would.
    place() { kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf('$ksel') >= 0) x.frameGeometry = {x: $1, y: $2, width: x.frameGeometry.width, height: x.frameGeometry.height}; });" 0.5; }
    closeall() {
        kwinjs "workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf('$ksel') >= 0) x.closeWindow(); });" 0.5
        local i; for i in $(seq 1 20); do [ -z "$(geom)" ] && break; sleep 0.3; done
    }
    # The book's record of the window, "x y": what the canvas wrote to the config.
    record() {
        kreadconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key WindowSpots | python3 -I -c '
import json, sys
try: b = json.load(sys.stdin)
except Exception: b = {}
r = [x for x in b.get(sys.argv[1], []) if sys.argv[2] in x.get("c", "")]
print("%d %d" % (r[0]["x"], r[0]["y"]) if r else "")' "$key" "$ksel"
    }
    launch() {
        local n; n=$(nwindows)
        run kcharselect >/dev/null 2>&1
        mapped $((n + 1)) || echo "231: kcharselect did not map in time" >&2
        # The restore runs 900 ms after the window appears; a fly lands at once (the nest's motion
        # knobs are off).
        sleep 2.5
    }
    view() { c state; vx=$(sget viewx); vx=${vx%.*}; vy=$(sget viewy); vy=${vy%.*}; }
    local vx vy g gx gy r

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

    # A reopened app slides the desk to its window, once the login's minute is past.
    local since; since=$(( $(date +%s) - $(stat -c %Y "$STATE/pid") ))
    [ "$since" -lt 65 ] && sleep $((65 - since))
    closeall
    assert_eq "a closed window's spot stays in the book" "$(record)" "$r"
    launch
    view
    assert_eq "the reopened app's window was put back" "$(sget restored)" 1
    read -r gx gy _ _ <<<"$(geom)"
    assert_eq "at its plane spot" "$((gx + vx)) $((gy + vy))" "$r"
    assert_true "and the desk slid to it: it is on the screen" "$gx" -ge 0 -a "$gx" -lt "$WIDTH" -a "$gy" -ge 0 -a "$gy" -lt "$HEIGHT"

    # A login: the window parked again, closed, the effect loaded afresh, the app started.
    place -2600 $((HEIGHT + 400))
    sleep 4
    r=$(record)
    view
    local bvx=$vx bvy=$vy
    closeall
    # The closed desk's camera is written a moment after its last landing (the fly above).
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
    launch
    view
    assert_eq "after the reload the starting app's window was put back" "$(sget restored)" 1
    read -r gx gy _ _ <<<"$(geom)"
    assert_eq "at its plane spot" "$((gx + vx)) $((gy + vy))" "$r"
    assert_eq "and the camera did not fly to it (x)" "$vx" "$lvx"
    assert_eq "and (y)" "$vy" "$lvy"
    assert_true "so the window waits off the screen" "$gy" -ge "$HEIGHT"

    # A running app's next window is a new one.
    launch
    view
    assert_eq "a second window of a running app is not put back" "$(sget restored)" 1

    # RestoreSpots off: KDE's placement, the book untouched.
    closeall
    setcfg RestoreSpots false
    launch
    view
    assert_eq "with RestoreSpots off nothing is put back" "$(sget restored)" 1
    read -r gx gy _ _ <<<"$(geom)"
    assert_true "and the window opens on the screen" "$gx" -ge 0 -a "$gx" -lt "$WIDTH" -a "$gy" -ge 0 -a "$gy" -lt "$HEIGHT"

    closeall
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key WindowSpots --delete
    rm -f "$CONF"/kcharselectrc
    arrange >/dev/null
}
