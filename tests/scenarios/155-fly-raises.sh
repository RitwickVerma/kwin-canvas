# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the window a fly lands on ends on top and active, whichever focus policy the desktop uses (a guard: the nest raises on activation itself, so this cannot show the stuck-below case that focus-follows-mouse without click-raise caused)"
top() { # -> the caption KWin has on top of its stacking order
    kwinjs 'var top = null; workspace.stackingOrder.forEach(function (x) { if (x.normalWindow && !x.minimized) top = x; }); print("TOP " + top.caption);' 0.6
    grep -a "TOP " "$STATE/kwin.log" | tail -1 | sed 's/.*TOP //'
}
run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    # The user's setup: raise on hover only. In the nest nothing raises on
    # activation by itself either way, which is the point.
    set_focus_policy() { # key value
        kwriteconfig6 --file "$CONF/kwinrc" --group Windows --key "$1" -- "$2"
    }
    set_focus_policy FocusPolicy FocusFollowsMouse
    set_focus_policy DelayFocusInterval 150
    set_focus_policy ClickRaise false
    set_focus_policy AutoRaise true
    set_focus_policy AutoRaiseInterval 300
    nq org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1
    sleep 0.5
    c "activate Dolphin"
    sleep 0.3
    c "shift 3000 0"
    c "activate KCalc"
    local fx i
    for i in $(seq 1 20); do
        c state; fx=$(eget KCalc fx)
        [ "$fx" -ge 0 ] && [ "$fx" -lt 1920 ] && break
        sleep 0.15
    done
    sleep 0.6
    assert_true "the fly brought KCalc on screen" "$([ "$fx" -ge 0 ] && [ "$fx" -lt 1920 ] && echo 1 || echo 0)" = 1
    assert_eq "and KCalc is on top of the stack" "$(top)" "KCalc"
    for k in FocusPolicy DelayFocusInterval ClickRaise AutoRaise AutoRaiseInterval; do
        kwriteconfig6 --file "$CONF/kwinrc" --group Windows --key $k --delete
    done
    nq org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1
    arrange >/dev/null
}
