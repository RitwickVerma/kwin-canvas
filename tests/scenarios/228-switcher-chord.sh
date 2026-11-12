# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="Alt+Tab as a task switcher, with the real chord: a tap flips to the window used last and opens nothing, a second tap flips back; a hold shows the switcher on the window used last, Tab steps on in the order the windows were last used, Shift+Tab steps back without ending the chord, and letting Alt go enters the pick at once"

# appname: the application from a caption ("wallpaper.png - ... — Gwenview" is Gwenview).
appname() { sed 's/ canvas=.*//; s/.* — //'; }
focused() {
    kwinjs 'var a = workspace.activeWindow; print("SWACT " + (a ? String(a.caption) : "-"));' 0.3
    grep -a "SWACT " "$STATE/kwin.log" | tail -1 | sed 's/.*SWACT //' | appname
}
selected() { c state >/dev/null; grep '^  \[[0-9][0-9]*\] \*' <<<"$LAST_STATE" | head -1 | sed 's/^  \[[0-9]*\] \*//' | appname; }

run_scenario() {
    source tests/lib.sh
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # The tap and the release are seen through the plugin's key filter; without it the chord's
    # end cannot be seen while the canvas is closed (the beat enters instead), which 124 covers.
    c state >/dev/null
    if [ "$(sget mover)" != plugin ]; then skip "needs the pass-through plugin (make plugin)"; return; fi
    setcfg Perf true
    arrange >/dev/null
    # The arrange leaves the focus history sample.txt, Konsole, Dolphin, Gwenview, KCalc: KCalc
    # active, Gwenview used before it, then Dolphin.
    local mark; mark=$(wc -l < "$STATE/kwin.log")
    # A tap: Alt down, Tab, Alt up at once.
    printf 'key leftalt down\nkey tab\nkey leftalt up\n' | input; sleep 0.8
    assert_eq "a tap flips to the window used last" "$(focused)" Gwenview
    c state >/dev/null
    assert_eq "and the canvas is closed" "$(sget visible)" false
    assert_eq "and never opened for it" "$(tail -n +"$((mark + 1))" "$STATE/kwin.log" | grep -ac 'kwin-canvas perf: open')" 0
    printf 'key leftalt down\nkey tab\nkey leftalt up\n' | input; sleep 0.8
    assert_eq "a second tap flips back" "$(focused)" KCalc
    # A hold: one input stream holds Alt throughout (in the background, so the reads land while it
    # is down): Tab, a pause, Tab, a pause, Shift+Tab, a pause, then Alt up.
    printf 'key leftalt down\nkey tab\nsleep 2500\nkey tab\nsleep 2500\nkey leftshift down\nkey tab\nkey leftshift up\nsleep 2500\nkey leftalt up\n' | input &
    sleep 0.9
    c state >/dev/null
    assert_eq "held, the switcher shows" "$(sget switcher)" shown
    assert_eq "on the window used last" "$(selected)" Gwenview
    sleep 2.5
    assert_eq "Tab steps on, in the order the windows were last used" "$(selected)" Dolphin
    sleep 2.5
    assert_eq "Shift+Tab steps back" "$(selected)" Gwenview
    assert_eq "and letting Shift go does not end the chord" "$(sget switcher)" shown
    wait
    sleep 1.2
    assert_eq "letting Alt go enters the pick" "$(focused)" Gwenview
    c state >/dev/null
    assert_eq "and the canvas closed" "$(sget visible)" false
    # Meta+Tab, the world switcher, the same way.
    printf 'key leftmeta down\nkey tab\nsleep 1500\nkey leftmeta up\n' | input &
    sleep 0.9
    c state >/dev/null
    assert_eq "Meta+Tab held shows the world switcher" "$(sget switcher)" shown
    wait
    sleep 1.2
    assert_eq "and its release enters the window used last" "$(focused)" KCalc
    c cancel >/dev/null 2>&1
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key Perf --delete
    c state >/dev/null
    arrange >/dev/null
}
