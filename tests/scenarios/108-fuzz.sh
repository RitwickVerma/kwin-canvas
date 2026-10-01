# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck source=../tests/lib.sh
scenario_desc="a seeded random drive leaves the canvas consistent: a finite camera, a sane zoom, and no exceptions"
run_scenario() {
    if ! have_input; then skip "fakeinput not built (make tools)"; return; fi
    local start_lines
    start_lines=$(wc -l < "$STATE/kwin.log")
    # A tiny deterministic LCG: the same run drives the same walk every time.
    local r i act ok_steps
    r=42
    ok_steps=0
    for i in $(seq 1 60); do
        r=$(( (r * 1103515245 + 12345) % 100000 ))
        act=$(( r % 12 ))
        case $act in
            0) c open ;;
            1) c "zoom 0.4 480 270" ;;
            2) c "pan $(( (r % 400) - 200 )) $(( (r / 3 % 300) - 150 ))" ;;
            3) c enter ;;
            4) c cancel ;;
            5) c "slide $(( (r % 600) - 300 )) $(( (r / 5 % 400) - 200 ))" ;;
            6) input move $(( 40 + r % 1800 )) $(( 40 + (r / 7) % 1000 )) ;;
            7) c "bracketright" ;;
            8) c "pin $(( r % 5 ))" ;;
            9) c "unpin $(( r % 5 ))" ;;
            10) input key tab ;;
            11) printf 'wheel %d\n' $(( (r % 3) - 1 )) | input ;;
        esac
        sleep 0.15
        c state
        if [ "$(sget zoom)" = "nan" ] || [ "$(sget zoom)" = "inf" ] || [ -z "$(sget zoom)" ]; then
            fail "the zoom went non-finite on step $i"
            break
        fi
        if [ "$(sget viewx)" = "nan" ] || [ "$(sget viewx)" = "inf" ]; then
            fail "the view went non-finite on step $i"
            break
        fi
        if [ "$(sget entries)" != "5" ]; then
            fail "a window went missing on step $i (entries $(sget entries))"
            break
        fi
        ok_steps=$((ok_steps + 1))
    done
    assert_true "every step kept the canvas consistent" "$([ "$ok_steps" -eq 60 ] && echo 1 || echo 0)" = 1
    # No exception may have fired in the effect since this scenario began:
    # plasmashell's own Menu.qml noise lives in the same log, so only the
    # effect's file counts.
    local errs
    errs=$(tail -n +"$start_lines" "$STATE/kwin.log" | grep -a "TypeError\|ReferenceError" | grep -ac "main.qml" || true)
    assert_true "no exception fired during the drive" "$([ "$errs" -eq 0 ] && echo 1 || echo 0)" = 1
    c cancel
    c "unpinall"
    arrange >/dev/null
}
