#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# PreToolUse(Bash) guard for kwin-canvas. AGENTS.md rule 1: never test in the live session.
# Reads the hook JSON on stdin, exits 2 (stderr goes to Claude) when a command would drive,
# install into, reload or capture the user's live KWin/Plasma session.
# Allowed: everything that stays in the nested KWin (make test/play/demo/golden/nest-*, or a
# command carrying NEST_*= / DBUS_SESSION_BUS_ADDRESS= / WAYLAND_DISPLAY= for the nest).
# Escape hatch for the user, not the agent: start Claude with KWIN_CANVAS_ALLOW_LIVE=1.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-cmd.sh
source "$HERE/lib-cmd.sh"

command -v jq >/dev/null 2>&1 || { echo "guard-bash: jq is missing, command not checked" >&2; exit 1; }
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0
[ "${KWIN_CANVAS_ALLOW_LIVE:-}" = 1 ] && exit 0

block() {
    {
        echo "BLOCKED (kwin-canvas AGENTS.md rule 1, never test in the live session): $1"
        echo "  command segment: $2"
        echo "  Use the nested KWin instead: make play | make nest-cmd CMD=state | make nest-shot | NEST_VIRTUAL=1 make test ARGS=NAME | make nest-reload."
        echo "  If the user asked for the live session in this message, they can start Claude with KWIN_CANVAS_ALLOW_LIVE=1."
    } >&2
    exit 2
}

# The whole command mentions the nest harness: treat its kwin-canvas/qdbus calls as nested.
whole_nested=0
printf '%s' "$cmd" | grep -qE 'dev/nest\.sh|(^|[^A-Za-z_])nest_(up|cmd|shot|run|input)\b' && whole_nested=1
[ -n "${NEST_NAME:-}${NEST_DBUS:-}" ] && whole_nested=1

live_make='install|install-system|uninstall|uninstall-system|reload|hot|enable|disable|status|try'

while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    parse_seg "$seg"
    [ -n "$PROG" ] || continue
    nested=$whole_nested
    for e in "${SEG_ENV[@]+"${SEG_ENV[@]}"}"; do
        case "$e" in NEST_*=* | DBUS_SESSION_BUS_ADDRESS=* | WAYLAND_DISPLAY=*) nested=1 ;; esac
    done
    case "$PROG" in
    make | just)
        for a in "${ARGS[@]+"${ARGS[@]}"}"; do
            [[ $a =~ ^($live_make)$ ]] && block "make $a touches the live session" "$seg"
        done
        ;;
    configure.sh)
        has_arg install uninstall enable disable status try && block "configure.sh touches the live session" "$seg"
        ;;
    kwin-canvas)
        [ "$nested" = 1 ] || has_arg --help -h help --version || block "the kwin-canvas CLI drives the live session's debug channel" "$seg"
        ;;
    spectacle | grim | grimshot | slurp | wf-recorder | gpu-screen-recorder | kooha | obs | scrot | maim | flameshot)
        [ "$nested" = 1 ] || block "$PROG captures the live desktop" "$seg"
        ;;
    ffmpeg | gst-launch-1.0 | gst-launch)
        if printf '%s' "$seg" | grep -qE 'x11grab|kmsgrab|pipewire|wayland|gdigrab'; then
            [ "$nested" = 1 ] || block "$PROG is recording the live desktop" "$seg"
        fi
        ;;
    qdbus | qdbus6 | qdbus-qt6 | qdbus-qt5 | gdbus | dbus-send | busctl)
        if printf '%s' "$seg" | grep -qE 'org\.kde\.(KWin|plasmashell)'; then
            [ "$nested" = 1 ] || block "$PROG talks to the live KWin/plasmashell bus" "$seg"
        fi
        ;;
    kwriteconfig5 | kwriteconfig6)
        if printf '%s' "$seg" | grep -qE 'kwinrc|plasma-org\.kde'; then
            [ "$nested" = 1 ] || block "$PROG edits the live KWin/Plasma configuration" "$seg"
        fi
        ;;
    kpackagetool5 | kpackagetool6)
        has_arg --install -i --upgrade -u --remove -r && block "kpackagetool changes the live user packages" "$seg"
        ;;
    kwin_wayland | kwin_x11 | plasmashell)
        has_arg --replace && block "$PROG --replace restarts the live session shell" "$seg"
        ;;
    kquitapp5 | kquitapp6)
        block "kquitapp stops a live session process" "$seg"
        ;;
    systemctl)
        if has_arg restart stop start reload kill && printf '%s' "$seg" | grep -qE 'plasma|kwin'; then
            block "systemctl would restart the live Plasma/KWin session" "$seg"
        fi
        ;;
    esac
done < <(printf '%s\n' "$cmd" | all_segments)
exit 0
