# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="mouse gestures: double-click a window centres it and focuses it (or keeps the point clicked), double-click a frame goes there, shift+double-click makes an activity over a window"
screen_of() {
    awk -v cx="$1" -v cy="$2" -v vx="$(sget viewx)" -v vy="$(sget viewy)" -v z="$(sget zoom)" \
        'BEGIN{printf "%d %d", (cx-vx)*z, (cy-vy)*z}'
}
dblclick() { printf "move $1 $2\nclick\nsleep 60\nclick\n" | input; }
# Where the centre of a w×h frame lands on the nest's 1920×1080 screen.
centre_x() { awk -v w="$1" 'BEGIN{print 960 - w / 2}'; }
centre_y() { awk -v h="$1" 'BEGIN{print 540 - h / 2}'; }
# Gestures land on title bars: with pass-through live a click inside a
# window's client area goes to the app. The nest's KDE apps have server-side
# title bars about 30 px tall, so canvas y = window top + 12.
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    # FocusTarget's default, "smart": a window far outside every frame with
    # nothing else near it, then double-click it. The current activity's frames
    # come to it and the window comes to the centre of the screen, focused, at
    # 1:1 - with no other window in view the placements all tie and the centred
    # one wins, which is where "centre" has always put it.
    open_1to1
    c "placeby KCalc 6000 4000"
    c extents
    local w h; w=$(eget KCalc w); h=$(eget KCalc h)
    read -r sx sy <<<"$(screen_of 6240 4012)"
    dblclick "$sx" "$sy"
    sleep 0.6; c state
    assert_eq "double-click applied" "$(sget visible)" false
    assert_eq "still on Activity 1" "$(eget KCalc activity)" "Activity 1"
    assert_near "KCalc centred on the screen" "$(eget KCalc fx)" "$(centre_x "$w")" 2
    assert_near "KCalc centred on the screen, y" "$(eget KCalc fy)" "$(centre_y "$h")" 2

    # The smart part: the window wholly in view, and of the offsets that keep it
    # so the one that leaves the most of the desk in view. Gwenview sits a
    # screen and a half to KCalc's right, so centring KCalc would push it right
    # off the screen: the placement slides the desk the other way instead, to
    # the least that keeps KCalc wholly in view - its left edge on the screen's
    # margin - and Gwenview stays in view with it. Nothing competes on y, so
    # that axis stays centred.
    c cancel; open_1to1
    c "placeby KCalc 6000 4000"
    c "placeby Gwenview 7500 4000"
    c extents
    read -r sx sy <<<"$(screen_of 6240 4012)"
    dblclick "$sx" "$sy"
    sleep 0.8; c state
    assert_eq "the smart placement applied" "$(sget visible)" false
    assert_near "the window is wholly on screen" "$(eget KCalc fx)" 8 2
    assert_near "and centred where nothing competes" "$(eget KCalc fy)" "$(centre_y "$h")" 2
    assert_true "and the neighbour is still in view" \
        "$(awk -v x="$(eget Gwenview fx)" 'BEGIN{print (x > 0 && x < 1920)}')" = 1

    # The same gesture with FocusTarget=centre shoves that neighbour off the
    # screen, which is the difference the mode is for.
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key FocusTarget centre
    c cancel; open_1to1
    c extents
    read -r sx sy <<<"$(screen_of 6240 4012)"
    dblclick "$sx" "$sy"
    sleep 0.8; c state
    assert_near "centre puts the window in the middle instead" "$(eget KCalc fx)" "$(centre_x "$w")" 2
    assert_true "and the neighbour is off the screen there" \
        "$(awk -v x="$(eget Gwenview fx)" 'BEGIN{print (x >= 1920)}')" = 1
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key FocusTarget smart
    c "placeby Gwenview 1400 120"

    # FocusTarget=window: the same gesture keeps the point clicked under the
    # pointer at 1:1 and the frames move to make that so. Click 60 px off the
    # window's centre, into its title bar.
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key FocusTarget window
    open_1to1
    c "placeby KCalc 6000 4000"
    c extents
    read -r sx sy <<<"$(screen_of 6060 4012)"
    dblclick "$sx" "$sy"
    sleep 0.6; c state
    assert_eq "window target applied" "$(sget visible)" false
    assert_true "KCalc on screen after focus" "$(awk -v x="$(eget KCalc fx)" 'BEGIN{print (x>=0 && x+480<=1920)}')" = 1
    # The helper truncates the screen position, so allow one screen pixel at
    # the fitted zoom.
    assert_near "clicked point under the pointer" "$(eget KCalc fx)" $((sx - 60)) 6

    # Default target: a window sitting in Activity 2's frame takes you there,
    # comes to the centre of the screen, and is focused.
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key FocusTarget centre
    open_1to1
    c state
    local t2x t2y; t2x=$(tget 1 x); t2y=$(tget 1 y)
    c "placeby KCalc $((t2x + 300)) $((t2y + 300))"
    c extents
    read -r sx sy <<<"$(screen_of $((t2x + 540)) $((t2y + 312)))"
    dblclick "$sx" "$sy"
    sleep 1.2; c state
    assert_eq "entered Activity 2" "$(sget activity)" "Activity 2"
    assert_eq "KCalc on Activity 2" "$(eget KCalc activity)" "Activity 2"
    assert_near "KCalc centred on the screen there" "$(eget KCalc fx)" "$(centre_x "$w")" 2
    assert_near "KCalc centred on the screen there, y" "$(eget KCalc fy)" "$(centre_y "$h")" 2
    c "activity 0"
    sleep 0.8
    open_1to1
    c state
    c "placeby KCalc $(($(tget 0 x) + 100)) $(($(tget 0 y) + 120))"
    c commit
    assert_eq "KCalc back on Activity 1" "$(eget KCalc activity)" "Activity 1"

    # FocusTarget=desktop: a window inside its frame leaves the frame alone.
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key FocusTarget desktop
    open_1to1
    c extents
    local t1x t1y kx ky; t1x=$(tget 0 x); t1y=$(tget 0 y); kx=$(eget KCalc fx); ky=$(eget KCalc fy)
    read -r sx sy <<<"$(screen_of $((t1x + kx + 240)) $((t1y + ky + 12)))"
    dblclick "$sx" "$sy"
    sleep 0.6; c state
    assert_eq "desktop target applied" "$(sget visible)" false
    assert_eq "frame stayed put" "$(tget 0 x),$(tget 0 y)" "$t1x,$t1y"
    assert_eq "KCalc did not move on screen" "$(eget KCalc fx),$(eget KCalc fy)" "$kx,$ky"
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key FocusTarget centre

    # Shift+double-click on a window outside every frame: a new activity centred on it.
    open_1to1
    c "placeby Gwenview 9000 -3000"
    c extents
    read -r sx sy <<<"$(screen_of 9230 -2988)"
    printf "move $sx $sy\nkey shift down\nclick\nsleep 60\nclick\nkey shift up\n" | input
    sleep 1.5; c state
    assert_eq "three activities now" "$(sget nactivities)" 3
    assert_eq "Gwenview moved to the new activity" "$(eget Gwenview activity)" "Activity 3"
    assert_eq "new activity is current" "$(sget activity)" "Activity 3"

    # Double-click Activity 1's frame area: apply with that activity current.
    open_1to1
    c extents
    local tx ty; tx=$(tget 0 x); ty=$(tget 0 y)
    read -r sx sy <<<"$(screen_of $((tx + 1900)) $((ty + 1060)))"
    dblclick "$sx" "$sy"
    sleep 1.0; c state
    assert_eq "frame double-click applied" "$(sget visible)" false
    assert_eq "Activity 1 is current" "$(sget activity)" "Activity 1"
    # Ctrl+double-click: the camera zooms to that activity, canvas stays open.
    open_1to1
    c extents
    read -r sx sy <<<"$(screen_of $((tx + 1900)) $((ty + 1060)))"
    printf "move $sx $sy\nkey ctrl down\nclick\nsleep 60\nclick\nkey ctrl up\n" | input
    sleep 0.6; c state
    assert_eq "ctrl double-click keeps the canvas open" "$(sget visible)" true
    assert_near "camera fitted to the frame" "$(sget zoom)" 0.8889 0.01
    c cancel

    # Restore: FocusTarget back to its default, Gwenview back, extra activity gone.
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key FocusTarget --delete
    open_1to1
    c "placeby Gwenview 1400 120"
    c commit
    c "rmactivity 2"
    sleep 1.2
    arrange >/dev/null
}
