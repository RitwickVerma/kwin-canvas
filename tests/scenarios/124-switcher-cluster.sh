# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the cluster switcher scopes its fit and its steps to the cluster the eye is on: Alt+Tab fits the near cluster at 1:1, steps stay inside it, and Meta+Tab keeps sweeping the whole plane"

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    open_1to1
    # Split the plane into two clusters: the near three stay together, the
    # far pair goes to x 4000, adjacent so it clusters (gap 80 < the
    # dynamic half-of-the-smaller-side gap). The far placeby crosses
    # Activity 2's frame, so the commit keeps them on the plane but far.
    c "placeby Dolphin 4000 800 700 360"
    c "placeby Gwenview 4000 300 460 420"
    c commit
    sleep 0.3
    c state
    assert_eq "the plane holds two clusters" "$(sget clusters)" 2

    # The cluster switcher from the closed location: it opens fitted to the
    # active window's cluster (the near three, bounds (100,120,1240,900)),
    # which fits the screen at the canvas's 1:1 cap - far tighter than the
    # world's ~0.36.
    c "switchcluster"
    sleep 0.6
    c state
    assert_eq "the cluster switcher fits the near cluster at the cap" "$(sget zoom)" "1.0000"
    assert_near "centred on it" "$(sget viewx)" -240.0 3
    assert_near "vertically too" "$(sget viewy)" 30.0 3

    # A repeat steps the selection, and the step stays inside the cluster.
    c "switchcluster"
    sleep 0.6
    c state
    assert_eq "the step picks a window" "$(grep -c '^  \[[0-9][0-9]*\] \*' <<<"$LAST_STATE")" 1
    sel=$(grep '^  \[[0-9][0-9]*\] \*' <<<"$LAST_STATE" | head -1)
    if echo "$sel" | grep -q 'Gwenview\|Dolphin'; then
        fail "and it never steps outside the cluster"
    else
        ok "and it never steps outside the cluster"
    fi

    # Enter lands the pick.
    c enter
    sleep 0.6
    c state
    assert_eq "and enter lands it" "$(sget visible)" false

    # The world switcher still sweeps everything: the fit is the whole
    # plane, well under the cluster's 1:1.
    c "switch"
    sleep 0.6
    c state
    assert_eq "the world switcher still opens" "$(sget visible)" true
    fitzoom=$(sget zoom)
    if awk -v z="$fitzoom" 'BEGIN { exit !(z + 0 < 0.4) }'; then
        ok "and fits the whole plane, not the cluster"
    else
        fail "and fits the whole plane, not the cluster"
    fi
    c cancel
    arrange >/dev/null
}
