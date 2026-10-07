# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="clusters are rooms: a jump returns to the spot the room was left at, a name sticks to its badge, and the digits land straight on the asked cluster"

run_scenario() {
    source tests/lib.sh
    arrange >/dev/null
    # A far pair makes the second cluster; the near three stay the first.
    open_1to1
    c "placeby Dolphin 4000 800 700 360"
    c "placeby wallpaper.png 4000 300 460 420"
    c commit
    sleep 0.3
    c state
    assert_eq "the plane holds two clusters" "$(sget clusters)" 2

    # The state's numbering is the recluster's own - find which component
    # holds the far pair, and call the other the near one.
    di=$(eget Dolphin index)
    gi=$(eget "wallpaper.png" index)
    far=$(awk -v a="$di" -v b="$gi" '/^  c[0-9]+:/ { hasa=0; hasb=0; for (i=2; i<=NF; i++) { if ($i==a) hasa=1; if ($i==b) hasb=1 } if (hasa && hasb) { idx=$1; sub("^c", "", idx); sub(":", "", idx); print idx; exit } }' <<<"$LAST_STATE")
    near=$((1 - far))
    assert_true "the far pair is its own cluster" -n "$far"

    # Name the far room and check the badge wears it.
    c "clustername $((far + 1)) studio"
    c state
    assert_eq "the name sticks" "$(grep -c "c${far}: .*\"studio\"" <<<"$LAST_STATE")" 1

    # The first visit: no home yet, so the smart pan lands the cluster's
    # last-focused window wholly on screen (Gwenview, the later activation).
    c "clusterjump $((far + 1))"
    sleep 0.6
    c state
    assert_eq "the first jump lands on the far room" "$(sget cluster)" "$((far + 1))"
    assert_near "smart-placed" "$(sget viewx)" 2564.0 60

    # Leave the far room somewhere else, then jump to the near room: the
    # near one remembers the seam's origin it was left at.
    c "pan 300 140"
    sleep 0.3
    c state
    far_x=$(sget viewx)
    far_y=$(sget viewy)
    c "clusterjump $((near + 1))"
    sleep 0.6
    c state
    assert_eq "the jump returns to the near room" "$(sget cluster)" "$((near + 1))"
    assert_near "at the remembered spot" "$(sget viewx)" 0.0 2
    assert_near "and its y" "$(sget viewy)" 0.0 2

    # And the far room remembers where it was left: jump away and back.
    c "pan 900 300"
    sleep 0.3
    c "clusterjump $((far + 1))"
    sleep 0.6
    c state
    assert_near "the far room kept its spot" "$(sget viewx)" "$far_x" 2
    assert_near "and its y" "$(sget viewy)" "$far_y" 2

    c cancel
    arrange
}
