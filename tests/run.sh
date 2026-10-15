#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Run the kwin-canvas scenarios against a dedicated nested KWin.
#
#   tests/run.sh [--update-golden] [--keep] [PATTERN]
#
# --update-golden  store this run's screenshots as the golden references
# --keep           leave the test nest running afterwards
# PATTERN          only scenarios whose file name matches
# SCENARIOS=DIR    run DIR/*.sh instead of tests/scenarios (tests/run-shim.sh)
# SCENARIO_LIST="a b c"  run exactly these scenario names, in this order, in one
#                  nest (for bisecting an order effect between scenarios)
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KEEP=0; PATTERN=""
for a in "$@"; do
    case $a in
        --update-golden) export UPDATE_GOLDEN=1 ;;
        --keep) KEEP=1 ;;
        *) PATTERN=$a ;;
    esac
done
# shellcheck source=lib.sh
source "$HERE/tests/lib.sh"

echo "== kwin-canvas tests (nest: $NEST_NAME, out: $OUT)"
# The goldens are recorded against one 1920x1080 output, and 91-two-outputs is
# the scenario written for an arrangement: on a two-output nest the other
# scenarios would be comparing two different desktops. Ask for the shape by
# name, or run them by pattern.
if [ "${NEST_OUTPUTS:-1}" != 1 ] && [ -z "$PATTERN" ]; then
    PATTERN=91
    echo "   $NEST_OUTPUTS outputs: running the 91 scenarios (pass a pattern to widen)"
fi
(cd "$HERE" && make -s nest-install >/dev/null) || { echo "make nest-install failed"; exit 1; }
down >/dev/null 2>&1 || true
up
fixtures
arrange >/dev/null
echo "   fixtures arranged: $(sget entries) windows"

# The effect's settings as the nest seeded them. A scenario that changes one
# and does not put it back would hand it to every scenario after it (two once
# left WindowPhysics on, and thirty checks downstream failed on screenshots
# and stacking), so after each scenario every setting it changed is put back.
# The debug channel's own keys and the effect's persisted state are left alone.
effect_settings() {
    awk '/^\[Effect-kwin-canvas\]/{f=1;next} /^\[/{f=0} f && /=/' "$CONF/kwinrc" \
        | grep -vE '^(DebugCommand|DebugSeq|ViewX|ViewY|HotRev|ClusterHomes|ClusterNames|Bookmarks|HiddenFrames|PinnedWindows)='
}
BASELINE=$(effect_settings)
restore_settings() {
    local now line key changed=0
    now=$(effect_settings)
    [ "$now" = "$BASELINE" ] && return
    while IFS= read -r line; do
        key=${line%%=*}
        grep -qxF "$line" <<<"$BASELINE" && continue
        if grep -q "^$key=" <<<"$BASELINE"; then
            kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key "$key" -- "$(grep "^$key=" <<<"$BASELINE" | head -1 | cut -d= -f2-)"
        else
            kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key "$key" --delete
        fi
        changed=1
    done <<<"$now"
    [ "$changed" = 1 ] && c state >/dev/null 2>&1
}
# What the effect remembers between runs about the windows: the spots the
# clusters were left at, their names, saved views. A tour in one scenario
# stores a spot for a cluster, and the next scenario's tour found it and flew
# to a place the first one had left (102 then 103). Cleared with the settings,
# and the effect reloads them on the next reconfigure.
# Whether the desk is off the arranged one: a window off its LAYOUT spot, or
# something other than KCalc on top.
layout_moved() {
    local cap spec x y
    c state >/dev/null 2>&1
    for cap in "${!LAYOUT[@]}"; do
        spec=(${LAYOUT[$cap]})
        x=$(eget "$cap" x); y=$(eget "$cap" y)
        [ "$x" = "${spec[0]}" ] && [ "$y" = "${spec[1]}" ] || return 0
    done
    # The stacking too: KCalc on top, the arranged chain, so a hover raise
    # (110) that moved nothing still counts.
    [ "$(awk '/^  \[/{e=$0} END{print e}' <<<"$LAST_STATE" | grep -c KCalc)" = 1 ] || return 0
    return 1
}
restore_memory() {
    local key had=0
    for key in ClusterHomes ClusterNames Bookmarks; do
        if [ -n "$(kreadconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key $key)" ]; then
            kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key $key --delete
            had=1
        fi
    done
    [ "$had" = 1 ] && cmd "reloadstate" >/dev/null 2>&1
}

matched=0
if [ -n "${SCENARIO_LIST:-}" ]; then
    files=()
    for n in $SCENARIO_LIST; do files+=("$HERE/${SCENARIOS:-tests/scenarios}/$n.sh"); done
else
    files=("$HERE"/${SCENARIOS:-tests/scenarios}/*.sh)
fi
for f in "${files[@]}"; do
    [ -f "$f" ] || { fail "no such scenario: $(basename "$f" .sh)"; continue; }
    name=$(basename "$f" .sh)
    [ -n "$PATTERN" ] && [[ "$name" != *$PATTERN* ]] && continue
    matched=$((matched + 1))
    unset -f run_scenario; scenario_desc=""
    # shellcheck source=/dev/null
    source "$f"
    echo "-- $name: $scenario_desc"
    if ! declare -F run_scenario >/dev/null; then
        fail "$name: scenario did not load (no run_scenario)"
        continue
    fi
    run_scenario
    c cancel >/dev/null 2>&1 || true
    restore_settings
    restore_memory
    # The pointer is state too: one left resting where the next scenario
    # puts a window lights that window as a hover (it once changed 93's
    # goldens after 90). Bare ground of the arranged desk, away from every
    # screen border.
    have_input && input move 1700 900 >/dev/null 2>&1
    # And so is the layout, the stacking order and the active window: a
    # scenario that moves windows with placeby and commits (111, 113), or
    # raises one by hover (110), and does not arrange again, left the next
    # one's screenshots a different desk. Cheap to check, so only a layout
    # that has moved is arranged again.
    layout_moved && arrange >/dev/null 2>&1
done

if [ "$matched" = 0 ]; then
    echo "== no scenario matches '${PATTERN}'"
    [ "$KEEP" = 1 ] || down >/dev/null || echo "warning: nest-down failed" >&2
    exit 1
fi

echo "== pass $PASS  fail $FAIL  skip $SKIP"
[ "$KEEP" = 1 ] || down >/dev/null || echo "warning: nest-down failed" >&2
[ "$FAIL" = 0 ]
