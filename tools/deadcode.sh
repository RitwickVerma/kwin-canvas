#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# The dead-code census: every function, property, signal and id the tree
# declares is counted against its uses, and anything referenced only at its
# own declaration is printed and the exit is non-zero. A name that appears
# once is dead by definition; two or more means at least one reader. (A
# write without a read is still a use; write-only state is not this check's
# business.) QML has no graph tool, so this is the graph, by hand; graphify
# covers the bash surface and agrees, but cannot parse QML.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$HERE" || exit 1

DEAD=()

# usage: census "name" "description"
census() {
    local n=$1 desc=$2
    local uses
    # The references may live in either side of the hot-reload split: the
    # logic declares in main.qml, the scene tree in ui.qml.
    uses=$(grep -c "\b${n}\b" effect/contents/ui/main.qml)
    uses=$((uses + $(grep -c "\b${n}\b" effect/contents/ui/ui.qml)))
    if [ "$uses" -le 1 ]; then
        DEAD+=("$desc: $n (declared, never referenced)")
    fi
}

# The effect: functions (skipping signal handlers, which ARE a signal's
# use), properties, signals and ids.
while IFS= read -r n; do
    case "$n" in on[A-Z]*) continue ;; esac
    census "$n" "main.qml function"
done < <(grep -oE "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*\(" effect/contents/ui/main.qml \
    | sed -E 's/^[[:space:]]*function ([a-zA-Z_][a-zA-Z0-9_]*)\(/\1/')
while IFS= read -r n; do
    census "$n" "main.qml property"
done < <(grep -oE "^[[:space:]]*(readonly[[:space:]]+)?property[[:space:]]+[a-zA-Z]+[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*" effect/contents/ui/main.qml \
    | awk '{print $NF}')
while IFS= read -r n; do
    census "$n" "main.qml signal"
done < <(grep -oE "^[[:space:]]*signal[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*" effect/contents/ui/main.qml \
    | awk '{print $NF}')
while IFS= read -r n; do
    census "$n" "main.qml id"
done < <(grep -oE "^[[:space:]]*id:[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*" effect/contents/ui/main.qml \
    | sed -E 's/.*id:[[:space:]]*//')
while IFS= read -r n; do
    census "$n" "ui.qml id"
done < <(grep -oE "^[[:space:]]*id:[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*" effect/contents/ui/ui.qml \
    | sed -E 's/.*id:[[:space:]]*//')

# The pure logic: each function needs a use in its own file, the effect or
# the unit tests.
while IFS= read -r n; do
    uses=$(( $(grep -c "\b${n}\b" effect/contents/ui/logic.js) \
        + $(grep -c "\b${n}\b" effect/contents/ui/main.qml) \
        + $(grep -c "\b${n}\b" tests/unit/logic.test.js) ))
    [ "$uses" -le 1 ] && DEAD+=("logic.js: $n (declared, never referenced)")
done < <(grep -oE "^function [a-zA-Z]+" effect/contents/ui/logic.js | awk '{print $2}')

# The scenarios' own helpers; run_scenario is the runner's entry point.
while IFS= read -r f; do
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        [ "$n" = "run_scenario" ] && continue
        if [ "$(grep -c "\b${n}\b" "$f")" -le 1 ]; then
            DEAD+=("scenario $f: $n (declared, never referenced)")
        fi
    done < <(grep -oE "^[a-z_]+\(\) \{" "$f" | sed 's/() {//')
done < <(find tests/scenarios -name '*.sh' | sort)

# The plugin's file-local helpers.
while IFS= read -r n; do
    if [ "$(grep -c "\b${n}\b" plugin/passthrough.cpp)" -le 1 ]; then
        DEAD+=("plugin/passthrough.cpp: $n (declared, never referenced)")
    fi
done < <(sed -nE 's/^static[^(]*\b([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(.*/\1/p' plugin/passthrough.cpp)

if [ "${#DEAD[@]}" -gt 0 ]; then
    printf '%s\n' "${DEAD[@]}"
    echo "deadcode: ${#DEAD[@]} finding(s)"
    exit 1
fi
echo "deadcode: clean"
