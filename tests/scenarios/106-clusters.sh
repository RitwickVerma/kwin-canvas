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
    # KCalc cluster the next stop is the lone KWrite, then the far cluster's
    # last-focused window (the arrange's chain touched Gwenview after
    # Dolphin, so the far stop is Gwenview). Each landing is the smart pan:
    # the least the camera must move to bring the window wholly on screen.
    printf 'key bracketright\n' | input
    sleep 0.5; c state
    assert_near "the next cluster is the lone window's" "$(sget viewx)" "$(awk 'BEGIN{print 6840-1896}')" 2
    printf 'key bracketright\n' | input
    sleep 0.5; c state
    assert_near "and the next is the far cluster's window" "$(sget viewx)" 2976 2
    printf 'key bracketleft\n' | input
    sleep 0.5; c state
    assert_near "the previous key steps back" "$(sget viewx)" "$(awk 'BEGIN{print 6840-1896}')" 2
    # A hand on the cluster drags it whole: the pair moves together, their
    # geometry kept. The pair's cluster is whichever the state's cluster
    # lines name both KCalc and Konsole.
    local kx ks pair
    kx=$(eget KCalc index)
    ks=$(eget Konsole index)
    pair=$(awk -v kx="$kx" -v ks="$ks" '
        $1 ~ /^c[0-9]+:$/ {
            hask = 0; hass = 0;
            for (i = 2; i <= NF; i++) { if ($i == kx) hask = 1; if ($i == ks) hass = 1; }
            if (hask && hass) { sub(/^c/, "", $1); sub(/:$/, "", $1); print $1; exit }
        }' <<<"$LAST_STATE")
    c "cdrag $pair 200 100"
    sleep 0.4; c state
    assert_eq "the cluster drag moves KCalc" "$(eget KCalc x)" 500
    assert_eq "and Konsole with it, the gap kept" "$(eget Konsole x)" 1100
    c "cdrag $pair -200 -100"
    sleep 0.3
    # A window dragged out of range breaks the cluster it left.
    c "placeby KCalc 2600 -800"
    sleep 0.5; c state
    assert_eq "dragging a window away breaks its cluster" "$(sget clusters)" 4
    c cancel
    arrange >/dev/null
}
