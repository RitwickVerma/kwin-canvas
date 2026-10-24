# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="search: the shortcut opens the overview fitted with a search field, typing narrows the windows to those whose title or app holds every word, the camera brings the match to the middle, Tab steps the matches, Enter flies into the chosen one, Esc ends the search and leaves the overview up, and the keys go back to the windows"

search_state() { c state >/dev/null; grep -oE ' search=("[^"]*":[0-9]+|-)' <<<"$(head -1 <<<"$LAST_STATE")" | cut -d= -f2-; }
search_chord() { nq org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Canvas Search" >/dev/null 2>&1; }

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    setcfg SmoothZoom false
    # A far window, so the camera has to travel to it.
    open_1to1
    c "placeby Gwenview 6000 2400 460 420"
    c commit >/dev/null; sleep 1.0

    # The chord opens the overview with an empty search.
    search_chord; sleep 1.2
    c state
    assert_eq "the chord opens the overview" "$(sget visible)" true
    assert_eq "with an empty search" "$(search_state)" '"":0'

    # Typing narrows: by app class, by title, every word, in any order.
    c "search dolphin"; sleep 0.3
    assert_eq "a class finds its window" "$(search_state)" '"dolphin":1'
    c state
    assert_eq "the match is selected" "$(grep -c '^  \[[0-9]*\] \*.*Dolphin' <<<"$LAST_STATE")" 1
    c "search wallpaper gwen"; sleep 0.6
    assert_eq "every word, in any order" "$(search_state)" '"wallpaper gwen":1'
    c state
    local vx vy z gx gy
    vx=$(sget viewx); vy=$(sget viewy); z=$(sget zoom); gx=$(eget Gwenview x); gy=$(eget Gwenview y)
    assert_true "the camera brought the far match into view (view x $vx)" "${vx%.*}" -gt 4000
    c "search kwin-canvas zzzz"; sleep 0.3
    assert_eq "nothing found is zero" "$(search_state)" '"kwin-canvas zzzz":0'

    # Tab steps among several matches.
    c "search kde"; sleep 0.3
    local n; n=$(search_state); n=${n##*:}
    assert_true "a common word matches several windows ($n)" "${n:-0}" -ge 2
    c state; local first; first=$(grep '^  \[[0-9]*\] \*' <<<"$LAST_STATE" | head -1)
    c "searchkey Tab"; sleep 0.3; c state
    assert_true "Tab selects another match" "$(grep '^  \[[0-9]*\] \*' <<<"$LAST_STATE" | head -1)" != "$first"

    # Esc ends the search; the overview stays.
    c "searchkey Escape"; sleep 0.3
    c state
    assert_eq "Esc ends the search" "$(search_state)" "-"
    assert_eq "and the overview stays" "$(sget visible)" true

    # Enter flies into the match: the canvas closes with Gwenview on screen and active.
    c "search gwenview"; sleep 0.4
    c "searchkey Return"; sleep 2.0
    c state
    assert_eq "Enter leaves the overview" "$(sget visible)" false
    local gr; gr=$(kwinjs 'workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("Gwenview") >= 0) print("SRCH " + Math.round(x.frameGeometry.x) + " " + (workspace.activeWindow === x)); });' 0.3; grep -a "SRCH " "$STATE/kwin.log" | tail -1 | sed 's/.*SRCH //')
    local gxr act; read -r gxr act <<<"$gr"
    assert_true "the match landed on the screen (x=$gxr)" "$gxr" -ge 0
    assert_true "and inside it" "$gxr" -lt 1920
    assert_eq "and it has the focus" "$act" true
    # Real keys, with the plugin live when it is built: the chord, the letters, Enter. The
    # search takes the keyboard from the windows while it runs.
    if have_input; then
        search_chord; sleep 1.2
        printf 'key d\nsleep 40\nkey o\nsleep 40\nkey l\nsleep 40\nkey p\nsleep 300\n' | input
        assert_eq "typed keys reach the search, not a window" "$(search_state)" '"dolp":1'
        printf 'key esc\nsleep 300\n' | input
        assert_eq "the real Esc ends it" "$(search_state)" "-"
        printf 'key esc\nsleep 600\n' | input
        c state
        assert_eq "and a second Esc leaves the overview" "$(sget visible)" false
    fi
    arrange >/dev/null
}
