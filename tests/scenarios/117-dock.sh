# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="the dock and the applets own their pixels: no click, hover or rest on them may focus the window under them or fly the canvas"
# The clock is the only thing in the panel: its bright pixels locate it in
# whichever strip the panel lives in. Prints "top WxH+X+Y" or
# "bottom WxH+X+Y", or nothing. An empty bounding box prints as
# "0x0+1920+40" (the image's far corner), not "0x0+0+0", so the width and
# the height decide emptiness, not the offsets. The bottom crop's box is
# local to the crop, so the strip is carried as a word, not derived.
clock_box() {
    local top tw th bottom
    top=$(magick "$1" -crop 1920x40+0+0 +repage -colorspace gray -threshold 80% -format "%@" info: 2>/dev/null)
    tw=$(cut -dx -f1 <<<"$top"); th=$(cut -dx -f2 <<<"$top" | cut -d+ -f1)
    if [ -n "$tw" ] && [ "$tw" != 0 ] && [ "$th" != 0 ]; then
        printf 'top %s\n' "$top"
        return
    fi
    bottom=$(magick "$1" -crop 1920x32+0+1048 +repage -colorspace gray -threshold 80% -format "%@" info: 2>/dev/null)
    printf 'bottom %s\n' "$bottom"
}
pt_state() { nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # The script's print() output comes back through the nq reply; the poll
    # reads it. If the nest has no panel yet, seed Plasma's default layout
    # (which carries one) and keep polling.
    local i got=0 seeded=0
    for i in $(seq 1 40); do
        local c
        c=$(nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "print('PANELCOUNT:' + panels().length)" 2>/dev/null || true)
        case "$c" in
            *PANELCOUNT:[1-9]*) got=1; break ;;
        esac
        if [ "$seeded" = 0 ] && [ "$i" -ge 6 ]; then
            nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.loadLookAndFeelDefaultLayout "org.kde.plasma.desktop" >/dev/null 2>&1
            seeded=1
        fi
        sleep 0.5
    done
    if [ "$got" != 1 ]; then
        skip "no plasmashell panel (make test-panel)"; return
    fi
    arrange
    shot "$OUT/dock.png" >/dev/null
    local bx
    bx=$(clock_box "$OUT/dock.png")
    if [ -z "$bx" ] || [ "$bx" = "0x0+0+0" ]; then skip "no panel clock (make test-panel)"; return; fi
    local cw ch cx cy px py strip bbox
    strip=$(cut -d' ' -f1 <<<"$bx"); bbox=$(cut -d' ' -f2- <<<"$bx")
    cw=$(cut -dx -f1 <<<"$bbox"); ch=$(cut -dx -f2 <<<"$bbox" | cut -d+ -f1)
    cx=$(cut -d+ -f2 <<<"$bbox"); cy=$(cut -d+ -f3 <<<"$bbox")
    px=$((cx + cw / 2))
    if [ "$strip" = top ]; then py=$((cy + ch / 2)); else py=$((1048 + cy + ch / 2)); fi
    # A window that lives under the clock: the one the old build would have
    # flown to, focused and hovered through the panel. Its frame must
    # contain the clock's point (the strip's coordinates are screen
    # coordinates at the closed 1:1 view).
    open_1to1
    c "placeby KCalc $((cx - 240)) $((py - 340)) 480 420"
    c commit
    sleep 0.3
    c "activate Konsole"
    sleep 0.3
    c state
    assert_eq "the window is under the clock" "$(sget active | grep -c Konsole || true)" 1
    assert_eq "and Konsole is the active window" "$(sget active | grep -c KCalc || true)" 0

    # The closed canvas: a click on the clock must not fly to the window
    # drawn under it - the chrome owns the click.
    local vx0 vy0
    vx0=$(sget viewx); vy0=$(sget viewy)
    input move "$px" "$py"
    sleep 0.5
    input click
    sleep 0.8
    c state
    assert_eq "a click on the dock never flies the closed canvas" "$(sget viewx)" "$vx0"
    assert_eq "and its y stays put" "$(sget viewy)" "$vy0"
    assert_eq "and the canvas stays closed" "$(sget visible)" "false"

    # The open overworld: a rest on the clock hovers no window, and a click
    # on it neither activates the window under it nor moves the camera.
    open_1to1
    sleep 0.5
    c state
    vx0=$(sget viewx); vy0=$(sget viewy)
    input move "$px" "$py"
    sleep 1.2
    assert_eq "a rest on the dock hovers no window" "$(pt_state | grep -c 'hover=-' || true)" 1
    assert_eq "and grabs none" "$(pt_state | grep -c 'grab=-' || true)" 1
    c state
    assert_eq "and the camera did not pan to the window under it" "$(sget viewx)" "$vx0"
    assert_eq "nor up or down" "$(sget viewy)" "$vy0"
    input click
    sleep 0.6
    c state
    assert_eq "the click on the dock left the canvas open" "$(sget visible)" "true"
    assert_eq "and the camera unmoved" "$(sget viewx)" "$vx0"
    assert_eq "and the window under it was not hovered" "$(pt_state | grep -c 'hover=KCalc' || true)" 0
    assert_eq "and it was not activated" "$(sget active | grep -c KCalc || true)" 0

    # The quiet grasp: a click on the clock during the hold must not fly
    # the keyhole toward the window under it either - the grasp's own pick
    # stands back when the chrome owns the pixel.
    c cancel
    sleep 0.3
    open_1to1
    c commit
    sleep 0.3
    c state
    vx0=$(sget viewx); vy0=$(sget viewy)
    { printf 'move 1700 900\nsleep 60\ndown back\nsleep 12000\nup back\n'; } | input &
    local holdpid=$!
    sleep 1.2
    c "zoom 0.6 960 540"
    sleep 1.0
    c state
    local gvx0 gvy0
    gvx0=$(sget viewx); gvy0=$(sget viewy)
    input move "$px" "$py"
    sleep 0.6
    input click
    sleep 0.8
    c state
    assert_eq "a click on the dock during the grasp never flies the keyhole" "$(sget viewx)" "$gvx0"
    assert_eq "and its y neither" "$(sget viewy)" "$gvy0"
    kill "$holdpid" 2>/dev/null
    sleep 0.8
    c cancel
    arrange >/dev/null
}
