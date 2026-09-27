#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Spike harness: a virtual-backend nest whose kwin_wayland runs with the
# preload shim. dev/nest.sh does the launch (NEST_PRELOAD, NEST_KWIN), config,
# bus, clients, input and teardown. The pass-through plugin is left off
# QT_PLUGIN_PATH so it cannot confound routing.
#
# /usr/bin/kwin_wayland carries the file capability cap_sys_nice=ep, which
# puts ld.so in secure-execution mode (AT_SECURE): LD_PRELOAD paths with a
# slash are dropped silently. The nest therefore runs a plain copy of the
# binary (cp drops file capabilities) from build/, which only costs KWin its
# realtime scheduling.
#
# This nest sets KWIN_CANVAS_PRELOAD_FILE=1, so the transform file below
# applies whenever the kwin-canvas effect's own transform does not.
#
#   dev/spike/preload/nest-preload.sh build     compile shim.so and copy kwin_wayland
#   dev/spike/preload/nest-preload.sh up        start the nest (virtual, NEST_NAME=preload)
#   dev/spike/preload/nest-preload.sh down
#   dev/spike/preload/nest-preload.sh tf S OX OY   set the transform file; "tf off" removes it
#   dev/spike/preload/nest-preload.sh probe NAME     launch probe.qml titled "Probe NAME"; log in $STATE/probe.log
#   dev/spike/preload/nest-preload.sh js 'CODE'      run a KWin script in the nest; print() lines come back
#   dev/spike/preload/nest-preload.sh nq ARGS...     qdbus6 on the nest's bus, never the session's
#   any other dev/nest.sh command passes through (run, input, log, cmd, shot)

set -euo pipefail
SPIKE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export NEST_NAME=preload NEST_VIRTUAL=1 NEST_SHELL=${NEST_SHELL:-0}
# shellcheck source=../../nest.sh
source "$SPIKE/../../nest.sh"
TF=${XDG_RUNTIME_DIR:-/tmp}/kwin-canvas-preload

# A capability-free copy of kwin_wayland, refreshed whenever the installed
# one differs; renamed into place, so a nest still running the old copy keeps it.
copy_kwin() {
    mkdir -p "$SPIKE/build"
    cmp -s /usr/bin/kwin_wayland "$SPIKE/build/kwin_wayland" || {
        cp /usr/bin/kwin_wayland "$SPIKE/build/kwin_wayland.new" && mv "$SPIKE/build/kwin_wayland.new" "$SPIKE/build/kwin_wayland"
    }
}

# The shim uses KWin's headers for types only and links Qt Core alone: every
# libkwin symbol is resolved at run time, after the build-id check. The
# library is renamed into place, so a nest still running the old one keeps it.
build() {
    copy_kwin
    local inc=(-I/usr/include/kwin -I/usr/include/KF6/KCoreAddons -I/usr/include/KF6/KConfigCore
               -I/usr/include/KF6/KConfig -I/usr/include/KF6/KConfigGui -I/usr/include/KF6/KWindowSystem
               -I/usr/include/KDecoration3)
    # shellcheck disable=SC2046
    g++ -std=c++20 -O2 -g -fPIC -shared -Wall -o "$SPIKE/build/shim.so.new" "$SPIKE/shim.cpp" "${inc[@]}" \
        $(pkg-config --cflags Qt6Core Qt6Gui Qt6Widgets Qt6Quick Qt6DBus) $(pkg-config --libs Qt6Core) -ldl
    # No libkwin symbol may be left for ld.so to bind at load time.
    if nm -D --undefined-only "$SPIKE/build/shim.so.new" | grep -q '_ZN*K*4KWin'; then
        echo "shim.so imports libkwin symbols:" >&2
        nm -DC --undefined-only "$SPIKE/build/shim.so.new" | grep 'KWin::' >&2
        rm -f "$SPIKE/build/shim.so.new"
        return 1
    fi
    mv "$SPIKE/build/shim.so.new" "$SPIKE/build/shim.so"
    echo "built $SPIKE/build/shim.so and a capability-free $SPIKE/build/kwin_wayland"
}

up_preload() {
    [ -f "$SPIKE/build/shim.so" ] || build
    copy_kwin
    NEST_PRELOAD="$SPIKE/build/shim.so" NEST_KWIN="$SPIKE/build/kwin_wayland" KWIN_CANVAS_PRELOAD_FILE=1 up
}

tf() {
    if [ "${1:-off}" = off ]; then rm -f "$TF"; echo "transform off"; else echo "$1 $2 $3" > "$TF"; echo "transform $1 $2 $3"; fi
}

case "${1:-}" in
    build) build ;;
    up) up_preload ;;
    down) rm -f "$TF"; down ;;
    tf) shift; tf "$@" ;;
    nq) shift; nq "$@" ;;
    *) exec "$SPIKE/../../nest.sh" "$@" ;;
esac
