#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Check (and optionally install) the tools kwin-canvas needs.
#   dev/deps.sh            report, print the pacman line for anything missing
#   dev/deps.sh --install  install what is missing with pacman (sudo)
set -uo pipefail

# command:archpackage, grouped by what needs them. An entry that starts with a slash is a file
# (a header, a cmake module) and is checked for existence rather than on the PATH.
CORE="kpackagetool6:kpackage qdbus6:qt6-tools kwriteconfig6:kconfig kwin_wayland:kwin dbus-run-session:dbus"
# The CLI: diffutils for doctor's install comparison, libnotify for the login check's notification.
CLI="diff:diffutils notify-send:libnotify busctl:systemd"
# qmllint is asked for by absolute path: the Qt5 build in /usr/bin answers to
# the same name and lints QML differently. reuse is only needed to run the same
# lint the CI job runs; node runs the unit tests.
TESTS="spectacle:spectacle magick:imagemagick python3:python /usr/lib/qt6/bin/qmllint:qt6-declarative reuse:reuse shellcheck:shellcheck glslangValidator:shaderc node:nodejs"
TOOLS="gcc:gcc wayland-scanner:wayland pkg-config:pkgconf vulture:vulture"
# The pass-through plugin (make plugin, kwin-canvas fix-plugin, the pacman hook): KWin's headers
# come with the kwin package itself.
PLUGIN="cmake:cmake /usr/share/ECM/cmake/ECMConfig.cmake:extra-cmake-modules /usr/include/kwin/effect/effect.h:kwin g++:gcc"
DEMO="ffmpeg:ffmpeg"
APPS="kcalc:kcalc kwrite:kwrite konsole:konsole dolphin:dolphin gwenview:gwenview"
PYMODS="PIL:python-pillow"

missing=""
present() {   # cmd-or-path
    case "$1" in
        /*) [ -e "$1" ] ;;
        *) command -v "$1" >/dev/null 2>&1 ;;
    esac
}
report() {   # label "cmd:pkg ..."
    echo "$1:"
    for d in $2; do
        cmd=${d%%:*}; pkg=${d##*:}
        if present "$cmd"; then printf "  ok       %s\n" "$cmd"
        else printf "  MISSING  %-16s (pacman: %s)\n" "$cmd" "$pkg"; case " $missing " in *" $pkg "*) ;; *) missing="$missing $pkg" ;; esac; fi
    done
}
report core "$CORE"
report cli "$CLI"
report tests "$TESTS"
report tools "$TOOLS"
report plugin "$PLUGIN"
report demo "$DEMO"
report apps "$APPS"
echo "python:"
for d in $PYMODS; do
    mod=${d%%:*}; pkg=${d##*:}
    if python3 -c "import $mod" 2>/dev/null; then printf "  ok       %s\n" "$mod"
    else printf "  MISSING  %-16s (pacman: %s)\n" "$mod" "$pkg"; missing="$missing $pkg"; fi
done
echo
if [ -z "$missing" ]; then echo "all present"; exit 0; fi
echo "install with:  sudo pacman -S --needed$missing"
if [ "${1:-}" = "--install" ]; then
    sudo pacman -S --needed $missing
else
    echo "or:            make deps-install"
    exit 1
fi
