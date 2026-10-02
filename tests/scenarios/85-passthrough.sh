# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="pass-through plugin: while the canvas is open, clicks, drags, the wheel and keys reach the real windows; the ground still pans; the chord enters"
# The plugin's own state line: active, camera, grab, hover.
pt_state() { nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state; }
aget() { sed -n 's/.*active="\(.*\)".*/\1/p' <<<"$(head -1 <<<"$LAST_STATE")"; }
# rmse between two crops of two screenshots; the region is WxH+X+Y.
region_rmse() {   # before after region
    magick "$1" -crop "$3" +repage "$OUT/pt-a.png"
    magick "$2" -crop "$3" +repage "$OUT/pt-b.png"
    { magick compare -metric RMSE "$OUT/pt-a.png" "$OUT/pt-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}
changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }
# The chord, as real keys in one fake-input session.
chord() { printf 'key leftctrl down\nkey leftalt down\nkey space\nkey leftalt up\nkey leftctrl up\n' | input; }
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "pass-through plugin not loaded (make plugin)"; return
    fi
    # The scenario's rests assume the tightest hover delay; pin it so the
    # suite's pace does not depend on the knob.
    setcfg HoverDelay 260
    c "activate Dolphin"
    c state; echo "STATE-early: $(head -1 <<<"$LAST_STATE")"
    shot "$OUT/pt-before.png" >/dev/null
    open_1to1; sleep 0.5; c state
    assert_eq "open with pass-through" "$(head -1 <<<"$LAST_STATE" | grep -c ' passthrough')" 1
    assert_eq "plugin switched on" "$(pt_state | grep -c 'active=true')" 1
    # Warm the input pipeline with a harmless move, so the first real rest
    # never lands on a pointer the nest has not connected yet.
    input move 960 540; sleep 0.3
    # Hover follows the window under the pointer and clears over the ground.
    input move 900 400; sleep 0.5
    assert_eq "hover reaches KWrite" "$(pt_state | grep -c 'hover=sample.txt')" 1
    input move 1700 1000; sleep 0.3
    assert_eq "ground clears the hover" "$(pt_state | grep -c 'hover=-')" 1
    # A click raises and focuses; the thumbnails restack. The pointer rests
    # first - the hover's delay is what hands the click over.
    printf 'move 900 400\nsleep 300\nclick\n' | input; sleep 0.8; c state
    assert_eq "click focuses KWrite" "$(aget)" "sample.txt — KWrite"
    assert_eq "KWrite on top" "$(grep '^  \[' <<<"$LAST_STATE" | tail -1 | grep -c KWrite)" 1
    shot "$OUT/pt-clicked.png" >/dev/null
    # A drag inside KWrite selects text; the wheel over Konsole scrolls it.
    # The rest before the wheel is the hover's delay: without it the wheel
    # would race the hand-over and zoom the canvas instead of scrolling.
    printf 'move 760 392\nsleep 300\ndrag 760 392 1000 424\n' | input; sleep 0.5
    printf 'move 400 900\nsleep 300\nwheel 3\n' | input; sleep 0.5; c state
    assert_eq "the wheel stayed a scroll" "$(sget zoom)" "1.0000"
    shot "$OUT/pt-after.png" >/dev/null
    assert_eq "drag selected text in KWrite" "$(changed "$(region_rmse "$OUT/pt-clicked.png" "$OUT/pt-after.png" 600x260+690+380)")" 1
    assert_eq "wheel scrolled Konsole" "$(changed "$(region_rmse "$OUT/pt-before.png" "$OUT/pt-after.png" 500x300+110+680)")" 1
    # Keys go to the focused window: a click drops the selection, then a typed
    # letter lands in KWrite's text.
    printf 'move 900 400\nsleep 300\nclick\nkey x\n' | input; sleep 0.6
    shot "$OUT/pt-typed.png" >/dev/null
    assert_eq "typing reached KWrite" "$(changed "$(region_rmse "$OUT/pt-clicked.png" "$OUT/pt-typed.png" 600x260+690+380)")" 1
    # The ground still pans.
    printf 'drag 1700 1000 1500 900\n' | input; sleep 0.4; c state
    assert_near "ground drag pans x" "$(sget viewx)" 200 2
    assert_near "ground drag pans y" "$(sget viewy)" 100 2
    # The chord enters the location in view: the viewport lands where the
    # camera was, the windows are written relative to it, the plugin is off.
    chord; sleep 0.6; c state
    assert_eq "the chord entered the location" "$(sget visible)" false
    assert_eq "plugin switched off" "$(pt_state | grep -c 'active=false')" 1
    assert_near "viewport where the camera was x" "$(sget viewx)" 200 2
    assert_near "viewport where the camera was y" "$(sget viewy)" 100 2
    assert_near "KCalc written relative to it" "$(eget KCalc fx)" -100 2
    c "slide -200 -100"
    # Leave the fixtures as found: undo the typed letter, scroll Konsole
    # back, drop the selection, then the usual arrange, so the scenarios
    # that follow (and their goldens) see the same desk this one found.
    open_1to1; sleep 0.5
    printf 'move 900 400\nsleep 300\nclick\nkey leftctrl down\nkey z\nkey leftctrl up\nmove 400 900\nsleep 300\nwheel -3\n' | input; sleep 0.5
    # The knob's default is a deliberate pause: half a second on a window is
    # a look, a full second is a hover. The undo's reopen above was a quiet
    # slide, and quiet opens never re-activate the pass-through, so step out
    # and in once more to run this part in the live overworld.
    c cancel; open_1to1; sleep 0.5; c state
    assert_eq "the fresh open re-activates the pass-through" "$(pt_state | grep -c 'active=true')" 1
    setcfg HoverDelay 900
    printf 'move 1700 1000\nsleep 200\nmove 900 400\n' | input; sleep 0.6
    assert_eq "half a second is a look, not a hover" "$(pt_state | grep -c 'hover=sample.txt')" 0
    sleep 0.8
    assert_eq "a full second is a hover" "$(pt_state | grep -c 'hover=sample.txt')" 1
    c cancel
    c state
    assert_eq "layout kept" "$(eget KCalc fx)" 100
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key HoverDelay --delete
    arrange >/dev/null
}
