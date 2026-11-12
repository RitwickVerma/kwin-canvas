# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
scenario_desc="the fidelity ladder: the canvas sheds its eye candy as the machine gets busy, down to plain rectangles, and puts it back when the machine breathes"

region_rmse() {   # before after region
    magick "$1" -crop "$3" +repage "$OUT/qa-a.png"
    magick "$2" -crop "$3" +repage "$OUT/qa-b.png"
    { magick compare -metric RMSE "$OUT/qa-a.png" "$OUT/qa-b.png" null: 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p'
}

changed() { awk -v m="$1" 'BEGIN{print (m>0.005)}'; }

# The ladder's own ladder: the thresholds sit at 0, so every reading is
# "busy enough" - the plugin's load() reports the host's real CPU, but with
# the thresholds at zero the host does not matter. The nest seeds the
# thresholds at 100 (a busy host must never move a golden); this scenario
# overrides them and deletes them afterwards.
step_thresholds() {   # bare minimal reduced
    setcfg CpuBare "$1"
    setcfg CpuMinimal "$2"
    setcfg CpuReduced "$3"
}

wait_ql() {   # want [tries]
    local want=$1 tries=${2:-40}
    local got=-1
    for _ in $(seq 1 "$tries"); do
        c state
        got=$(sget ql)
        [ "$got" = "$want" ] && return 0
        sleep 0.3
    done
    return 1
}

# Every early exit must put the knobs back: a leaked threshold follows the
# suite into the next scenario's readings.
restore_quality_knobs() {
    setcfg QualityMode Auto
    for k in QualityMode CpuBare CpuMinimal CpuReduced GpuBare GpuMinimal GpuReduced MemBare MemMinimal MemReduced VramBare VramMinimal VramReduced; do
        kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key "$k" --delete >/dev/null
    done
    c cancel
    arrange >/dev/null
}

run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    if ! nq org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.probe >/dev/null 2>&1; then
        skip "pass-through plugin not loaded (make plugin)"; return
    fi
    arrange >/dev/null

    # The seed pins the thresholds at 100, so the host's real load never
    # trips the ladder mid-scenario. At 100 the overworld wears everything.
    open_1to1
    c state
    assert_eq "an idle machine wears everything" "$(sget ql)" 0
    local held entries; held=$(( $(sget offscreen) - $(sget popups) )); entries=$(sget entries)
    assert_true "the gpu channel reports" -n "$(sget gpu)"
    assert_true "the mem channel reports" -n "$(sget mem)"
    assert_true "the vram channel reports" -n "$(sget vram)"
    c "zoom 0.5 960 540"
    sleep 0.2
    c state
    # The thread's screen spot at zoom 0.5, view (-960,-540): the lit web
    # between KCalc's centre and Konsole's centre crosses open ground at
    # (667,555); KCalc's interior is at (340+960)*0.5, (330+540)*0.5.
    local tx ty kx ky
    tx=667
    ty=555
    kx=650
    ky=435
    shot "$OUT/qa-full.png" >/dev/null

    # Bare: the thresholds at 0 mean every reading is busy. The web, the
    # shadows and the live pictures all go; the windows stay as rectangles.
    step_thresholds 0 0 0
    if ! wait_ql 3; then fail "the ladder stepped to bare (ql=$(sget ql))"; restore_quality_knobs; return; fi
    sleep 0.3
    c state
    assert_eq "the ladder holds bare" "$(sget ql)" 3
    # Bare gives the pictures' cost back, not just their pixels: no window is copied for them
    # (a popup the canvas draws is, so popups are left out of both counts).
    local bare; bare=$(( $(sget offscreen) - $(sget popups) ))
    assert_true "bare lets go of every window's picture (offscreen ${held} -> ${bare} besides popups, ${entries} windows)" "$(( held - bare ))" -ge "${entries:-1}"
    shot "$OUT/qa-bare.png" >/dev/null
    assert_eq "the web is gone at bare" "$(changed "$(region_rmse "$OUT/qa-full.png" "$OUT/qa-bare.png" "12x12+$((tx-6))+$((ty-6))")")" 1
    assert_eq "the live pictures are gone at bare" "$(changed "$(region_rmse "$OUT/qa-full.png" "$OUT/qa-bare.png" "16x16+$((kx-8))+$((ky-8))")")" 1

    # The machine breathes: the thresholds back at their defaults step the
    # ladder up again - two calm readings, so it never flutters.
    step_thresholds 95 80 60
    if ! wait_ql 0 60; then fail "the ladder stepped back to full (ql=$(sget ql))"; restore_quality_knobs; return; fi
    sleep 0.3
    c state
    assert_eq "a calm machine wears everything again" "$(sget ql)" 0
    shot "$OUT/qa-back.png" >/dev/null
    assert_eq "the web came back" "$(changed "$(region_rmse "$OUT/qa-bare.png" "$OUT/qa-back.png" "12x12+$((tx-6))+$((ty-6))")")" 1

    # The middle rungs: minimal drops the web but keeps the pictures.
    step_thresholds 100 0 0
    if ! wait_ql 2; then fail "the ladder stepped to minimal (ql=$(sget ql))"; restore_quality_knobs; return; fi
    sleep 0.3
    c state
    assert_eq "the ladder holds minimal" "$(sget ql)" 2
    shot "$OUT/qa-min.png" >/dev/null
    assert_eq "minimal drops the web" "$(changed "$(region_rmse "$OUT/qa-back.png" "$OUT/qa-min.png" "12x12+$((tx-6))+$((ty-6))")")" 1
    # The live pictures survive minimal - only bare trades them for washes.
    # (The windows shift a hair as the z-depth flattens, so the proof is
    # minimal against bare, not against full.)
    assert_eq "the pictures survive minimal" "$(changed "$(region_rmse "$OUT/qa-min.png" "$OUT/qa-bare.png" "16x16+$((kx-8))+$((ky-8))")")" 1

    # The GPU's memory is a channel of its own: with every other channel calm, a full card
    # alone steps the ladder down (any reading, the host's real one included, is past 0).
    step_thresholds 100 100 100
    if ! wait_ql 0 60; then fail "the ladder stepped back up for the vram check (ql=$(sget ql))"; restore_quality_knobs; return; fi
    setcfg VramBare 100; setcfg VramMinimal 0; setcfg VramReduced 0
    if ! wait_ql 2; then fail "a full GPU memory alone steps to minimal (ql=$(sget ql))"; restore_quality_knobs; return; fi
    c state
    assert_eq "a full GPU memory alone steps the ladder to minimal" "$(sget ql)" 2
    # Back to the nest's pin, so the host's real card cannot move the checks below.
    setcfg VramBare 100; setcfg VramMinimal 100; setcfg VramReduced 100

    # A fixed mode overrides the ladder: Full holds everything even with the
    # thresholds at zero.
    step_thresholds 0 0 0
    setcfg QualityMode Full
    if ! wait_ql 0 20; then fail "Full holds everything (ql=$(sget ql))"; restore_quality_knobs; return; fi
    c state
    assert_eq "Full holds everything under load" "$(sget ql)" 0

    # Bare rectangles at 1:1: the live picture is the canvas's dearest cost,
    # so it is the last thing to go - the window becomes a named wash.
    setcfg QualityMode Bare
    if ! wait_ql 3 20; then fail "Bare holds rectangles (ql=$(sget ql))"; restore_quality_knobs; return; fi
    setcfg QualityMode Full
    if ! wait_ql 0 20; then fail "Full again for the reference (ql=$(sget ql))"; restore_quality_knobs; return; fi
    c cancel
    sleep 0.4
    open_1to1
    sleep 0.6
    shot "$OUT/qa-11-full.png" >/dev/null
    setcfg QualityMode Bare
    if ! wait_ql 3 20; then fail "Bare at 1:1 (ql=$(sget ql))"; restore_quality_knobs; return; fi
    sleep 0.3
    shot "$OUT/qa-11-bare.png" >/dev/null
    assert_eq "the 1:1 picture goes at bare" "$(changed "$(region_rmse "$OUT/qa-11-full.png" "$OUT/qa-11-bare.png" "16x16+324+322")")" 1

    # A quiet slide starts at the mode's rung, not at the step a full open left behind: the
    # ladder samples only the full overworld, so a step a game forced would otherwise greet
    # every later slide with plain rectangles. The thresholds stay at zero (every reading
    # busy), so only the open's own reset can bring the slide back to full.
    c cancel
    sleep 0.4
    setcfg QualityMode Auto
    step_thresholds 0 0 0
    open_1to1
    if ! wait_ql 3; then fail "the ladder stepped to bare before the slide (ql=$(sget ql))"; restore_quality_knobs; return; fi
    c cancel
    sleep 0.4
    c "slide 600 0"
    sleep 1.2
    c state
    assert_eq "a quiet slide after a bare overworld wears everything" "$(sget ql)" 0
    c "slide -600 0"
    sleep 1.2

    # Leave the knobs as found.
    restore_quality_knobs
}
