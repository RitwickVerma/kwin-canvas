# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="desktops are islands on the one plane: every desktop's windows are live entries at the island's offset, a zone names each island and a tap switches there, a cluster promotes into its own desktop, and the quiet seam shows only its own"

run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    arrange >/dev/null

    # A new desktop is an island: the zone's name chip rides the skin at
    # the island's top-left corner and a tap switches the desktop - the
    # handler flies the camera to the island's place. The step is the
    # screen's height plus the ActivityGap (1080 + 240 = 1320), so
    # desktop 2 lives at y 1320.
    open_1to1
    c "newdesktop Two"
    sleep 0.5
    c state
    assert_eq "the plane has two desktops" "$(sget desktops)" 2
    assert_eq "and stays on the first" "$(sget desktop)" 1

    c "zoom 0.5 960 540"
    sleep 0.5
    c state
    assert_near "the zoom settled" "$(sget viewx)" "-960.0" 3
    assert_near "vertically too" "$(sget viewy)" "-540.0" 3

    # Desktop 2's zone chip: canvas (16, 1320+16) at zoom 0.5 from
    # (-960,-540) -> screen (488, 938); the click lands inside the chip.
    printf 'move 500 944\nsleep 400\nclick\nsleep 400\n' | input
    local i
    for i in $(seq 1 20); do
        c state
        [ "$(sget desktop)" = 2 ] && break
        sleep 0.2
    done
    sleep 0.4
    c state
    assert_eq "the zone switched the desktop" "$(sget desktop)" 2
    assert_near "and the camera flew to its island" "$(sget viewy)" "1320.0" 3
    # Every desktop's windows are entries on the one plane: the count
    # holds, and each entry names its own desktop.
    assert_eq "the plane keeps every window" "$(sget entries)" 5
    assert_eq "all of them on the first island" "$(grep -c '^  \[[0-9][0-9]*\] .* desktop=1' <<<"$LAST_STATE")" 5

    # Back to desktop 1: the camera comes home, the windows stay put.
    c "desktop 0"
    sleep 0.5
    c state
    assert_eq "stepping back lands on the first desktop" "$(sget desktop)" 1
    assert_eq "with its windows again" "$(sget entries)" 5

    # A cluster promotes into its own desktop: KCalc and Konsole are the
    # adjacent pair (a gap of 20 links them under the dynamic gap); KWrite
    # sits near enough to stay on Activity 1 but far enough to stay out of
    # the pair's cluster, and the far two live on Activity 2's frame.
    open_1to1
    c "placeby KCalc 100 120 480 420"
    c "placeby Konsole 100 560 620 420"
    c "placeby sample.txt 1700 120 700 520"
    c "placeby Dolphin 4000 800 700 360"
    c "placeby Gwenview 4000 120 460 420"
    c commit
    sleep 0.5
    c state
    local ki wi ci
    ki=$(eget KCalc index)
    wi=$(eget Konsole index)
    ci=$(awk -v k="$ki" -v w="$wi" '
        /^  c[0-9]+:/ {
            hask = 0; hasw = 0
            for (i = 2; i <= NF; i++) { if ($i == k) hask = 1; if ($i == w) hasw = 1 }
            if (hask && hasw) { idx = $1; sub("^c", "", idx); sub(":", "", idx); print idx; exit }
        }' <<<"$LAST_STATE")
    assert_true "the near pair forms its own cluster" -n "$ci"

    c "desktopof $ci"
    # The promote now slides the camera (DesktopSlide is on by default):
    # poll for the landing instead of racing the glide.
    for i in $(seq 1 30); do
        c state
        [ "$(sget desktop)" = 3 ] && [ "$(sget visible)" = false ] && break
        sleep 0.3
    done
    sleep 0.3
    c state
    assert_eq "the cluster made a desktop" "$(sget desktops)" 3
    assert_eq "and stepped onto it" "$(sget desktop)" 3
    assert_near "the camera flew to the fresh island" "$(sget viewy)" "2640.0" 3

    # The promote ran with the canvas closed, so the plane still lists the
    # old five windows; opening on the new island lets the resync count.
    open_1to1
    sleep 0.5
    c state
    assert_eq "the plane keeps every window here too" "$(sget entries)" 5
    assert_eq "the pair now lives on the new island" "$(grep -c '^  \[[0-9][0-9]*\] .* desktop=3' <<<"$LAST_STATE")" 2

    # Desktop 1 keeps its other three windows.
    c "desktop 0"
    sleep 0.5
    c state
    assert_eq "the first desktop kept the rest" "$(sget desktop)" 1
    assert_eq "three of them" "$(grep -c '^  \[[0-9][0-9]*\] .* desktop=1' <<<"$LAST_STATE")" 3

    # The switcher's fit takes the islands into the frame, so the fitted
    # world shows every desktop at once. The canvas must be closed for the
    # switch verb to open it fitted.
    c cancel
    sleep 0.3
    c switch
    sleep 0.3
    c state
    assert_eq "the switcher opened over the world" "$(sget visible)" true
    fitzoom=$(sget zoom)
    if awk -v z="$fitzoom" 'BEGIN { exit !(z + 0 < 0.35) }'; then
        ok "and its fit covers the islands"
    else
        fail "and its fit covers the islands"
    fi
    c cancel
    sleep 0.3

    # Leave the nest as found: the pair comes home, the extra desktops go.
    # The canvas must be open for the moves to resync the plane before the
    # final count.
    open_1to1
    sleep 0.3
    c "movetodesktop 2 0"
    sleep 0.3
    c "rmdesktop 2"
    sleep 0.3
    c "rmdesktop 1"
    sleep 0.5
    c state
    assert_eq "one desktop again" "$(sget desktops)" 1
    assert_eq "and all five windows back" "$(sget entries)" 5
    arrange >/dev/null
}
