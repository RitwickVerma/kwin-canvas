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
(cd "$HERE" && make -s install >/dev/null) || { echo "make install failed"; exit 1; }
down >/dev/null 2>&1 || true
up
fixtures
arrange >/dev/null
echo "   fixtures arranged: $(sget entries) windows"

matched=0
for f in "$HERE"/${SCENARIOS:-tests/scenarios}/*.sh; do
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
done

if [ "$matched" = 0 ]; then
    echo "== no scenario matches '${PATTERN}'"
    [ "$KEEP" = 1 ] || down >/dev/null || echo "warning: nest-down failed" >&2
    exit 1
fi

echo "== pass $PASS  fail $FAIL  skip $SKIP"
[ "$KEEP" = 1 ] || down >/dev/null || echo "warning: nest-down failed" >&2
[ "$FAIL" = 0 ]
