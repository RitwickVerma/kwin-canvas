#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Run the tests/shim scenarios in a virtual nest (NEST_NAME=shim) whose
# kwin_wayland runs with the plane-input shim of dev/spike/preload.
#
#   tests/run-shim.sh [--keep] [PATTERN]
#
# Exits 0 with a skip line when the shim cannot be built here (no KWin
# headers, Qt or g++) or was written for another libkwin build.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PRE=$HERE/dev/spike/preload

want=$(sed -n 's/.*EXPECTED_BUILD_ID = "\([0-9a-f]*\)".*/\1/p' "$PRE/shim.cpp")
have=$(readelf -n /usr/lib/libkwin.so.6 2>/dev/null | sed -n 's/.*Build ID: *//p' | head -1)
if [ "$want" != "$have" ]; then
    echo "== shim scenarios skipped: the shim expects libkwin build-id $want, this one is ${have:-unknown}"
    exit 0
fi
if ! out=$("$PRE/nest-preload.sh" build 2>&1); then
    echo "== shim scenarios skipped: the shim does not build here"
    sed 's/^/   /' <<<"$out" | tail -5
    exit 0
fi

export NEST_NAME=shim NEST_PRELOAD=$PRE/build/shim.so NEST_KWIN=$PRE/build/kwin_wayland SCENARIOS=tests/shim
exec "$HERE/tests/run.sh" "$@"
