#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Spike harness: a virtual-backend nest whose kwin_wayland runs with the
# preload shim. Reuses dev/nest.sh for config, bus, clients, input and
# teardown; only the launch differs, because LD_PRELOAD has to reach
# kwin_wayland alone (dbus-run-session and bash stay clean, and the shim
# unsets it at load so KWin's children do not inherit it). The pass-through
# plugin is left off QT_PLUGIN_PATH so it cannot confound routing.
#
# /usr/bin/kwin_wayland carries the file capability cap_sys_nice=ep, which
# puts ld.so in secure-execution mode (AT_SECURE): LD_PRELOAD paths with a
# slash are dropped silently. The nest therefore runs a plain copy of the
# binary (cp drops file capabilities) from build/, which only costs KWin its
# realtime scheduling.
#
#   dev/spike/preload/nest-preload.sh build     compile shim.so and the probe client deps
#   dev/spike/preload/nest-preload.sh up        start the nest (virtual, NEST_NAME=preload)
#   dev/spike/preload/nest-preload.sh down
#   dev/spike/preload/nest-preload.sh tf S OX OY   set the transform; "tf off" clears it
#   dev/spike/preload/nest-preload.sh probe NAME     launch probe.qml titled "Probe NAME"; log in $STATE/probe.log
#   dev/spike/preload/nest-preload.sh js 'CODE'      run a KWin script in the nest; print() lines come back
#   any other dev/nest.sh command passes through (run, input, log, cmd, shot)

set -euo pipefail
SPIKE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export NEST_NAME=preload NEST_VIRTUAL=1 NEST_SHELL=${NEST_SHELL:-0}
# shellcheck source=../../nest.sh
source "$SPIKE/../../nest.sh"
TF=${XDG_RUNTIME_DIR:-/tmp}/kwin-canvas-preload

build() {
    mkdir -p "$SPIKE/build"
    cp /usr/bin/kwin_wayland "$SPIKE/build/kwin_wayland"
    g++ -O2 -g -fPIC -shared -Wall -o "$SPIKE/build/shim.so" "$SPIKE/shim.cpp" -ldl
    echo "built $SPIKE/build/shim.so and a capability-free $SPIKE/build/kwin_wayland"
}

up_preload() {
    [ -f "$SPIKE/build/shim.so" ] || build
    if alive; then echo "already up (pid $(cat "$STATE/pid"))"; return; fi
    mkdir -p "$STATE"; rm -f "$STATE/bus" "$STATE/clients" "$STATE/pid"
    seed_config
    (
        cd "$STATE"
        setsid -f env XDG_CONFIG_HOME="$STATE/config" XDG_STATE_HOME="$STATE/state" \
            XDG_DATA_HOME="$STATE/data" XDG_DATA_DIRS="$HOME/.local/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" \
            QT_LOGGING_TO_CONSOLE=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
            SHIM="$SPIKE/build/shim.so" KWIN_BIN="$SPIKE/build/kwin_wayland" \
            dbus-run-session -- bash -c '
            echo "$PPID" > "$0/pid"
            echo "$DBUS_SESSION_BUS_ADDRESS" > "$0/bus"
            exec env LD_PRELOAD="$SHIM" "$KWIN_BIN" --virtual --width '"$WIDTH"' --height '"$HEIGHT"' --output-count 1 --xwayland --no-lockscreen --socket '"$SOCKET"'
        ' "$STATE" > "$LOG" 2>&1
    )
    for _ in $(seq 1 50); do
        [ -f "$STATE/bus" ] && nq org.kde.KWin /KWin org.kde.KWin.supportInformation >/dev/null 2>&1 && break
        sleep 0.2
    done
    alive && echo "nest up (pid $(cat "$STATE/pid"), socket $SOCKET)" || { echo "nest failed; see $LOG"; return 1; }
}

tf() {
    if [ "${1:-off}" = off ]; then rm -f "$TF"; echo "transform off"; else echo "$1 $2 $3" > "$TF"; echo "transform $1 $2 $3"; fi
}

probe() {
    alive || { echo "not up"; return 1; }
    ( export WAYLAND_DISPLAY=$SOCKET DBUS_SESSION_BUS_ADDRESS=$(bus) QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1; unset DISPLAY
      qml6 "$SPIKE/probe.qml" -- "$1" >> "$STATE/probe.log" 2>&1 & echo $! >> "$STATE/clients" )
}

# A KWin script run through org.kde.kwin.Scripting; its print() output lands
# in the nest log tagged with a fresh marker, which is echoed back.
js() {
    alive || { echo "not up"; return 1; }
    local tag="JS$RANDOM$RANDOM" f="$STATE/script-$RANDOM.js"
    printf 'function out(s) { print("%s " + s); }\n%s\n' "$tag" "$1" > "$f"
    local id; id=$(nq org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$f" "$tag")
    nq org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null
    sleep 0.3
    nq org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$tag" >/dev/null
    rm -f "$f"
    grep -a "$tag " "$LOG" | sed "s/.*$tag //"
}

case "${1:-}" in
    probe) probe "$2" ;;
    js) js "$2" ;;
    build) build ;;
    up) up_preload ;;
    down) rm -f "$TF"; down ;;
    tf) shift; tf "$@" ;;
    *) exec "$SPIKE/../../nest.sh" "$@" ;;
esac
