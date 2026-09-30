# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="clusters: nearby windows form a cluster, the bracket keys fly the camera between them in reading order, and a window dragged away breaks its cluster"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # The canvas keys drive this one; with the pass-through plugin live they
    # go to the focused window (the plugin's own scenario is 85).
    setcfg Passthrough false
    open_1to1
    # Two clusters: KCalc and Konsole together, Gwenview and Dolphin together
    # far to the right, KWrite left alone.
    c "placeby KCalc 300 300 480 420"
    c "placeby Konsole 900 350 620 420"
    c "placeby Gwenview 3000 300 460 420"
    c "placeby Dolphin 3600 350 700 360"
    c "placeby sample 6200 400 640 508"
    c commit
    c open
    c home
    sleep 0.5; c state
    assert_eq "two clusters and a lone window" "$(sget clusters)" 3
    # Resting on KCalc makes its cluster the one the travel starts from.
    input move 500 500
    sleep 1.0; c state
    assert_true "the hovered window's cluster is current" \
        "$(grep -oE 'cluster=#[0-9]+' <<<"$LAST_STATE" | grep -oE '[0-9]+$' | awk '{print ($1 >= 1)}')" = 1
    # The bracket keys fly between the clusters in reading order: from the
    # KCalc cluster the next stop is the lone KWrite, then the far cluster.
    printf 'key bracketright\n' | input
    sleep 0.5; c state
    assert_near "the next cluster is the lone window's" "$(sget viewx)" "$(awk 'BEGIN{print 6520-960}')" 2
    printf 'key bracketright\n' | input
    sleep 0.5; c state
    assert_near "and the next is the far cluster" "$(sget viewx)" "$(awk 'BEGIN{print 3590-960}')" 2
    printf 'key bracketleft\n' | input
    sleep 0.5; c state
    assert_near "the previous key steps back" "$(sget viewx)" "$(awk 'BEGIN{print 6520-960}')" 2
    # A window dragged out of range breaks the cluster it left.
    c "placeby KCalc 1700 300"
    sleep 0.5; c state
    assert_eq "dragging a window away breaks its cluster" "$(sget clusters)" 4
    c cancel
    arrange >/dev/null
}
