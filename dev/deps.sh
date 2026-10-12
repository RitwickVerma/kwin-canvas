#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Check (and optionally install) the tools kwin-canvas needs.
#   dev/deps.sh            report, print the pacman line for anything missing
#   dev/deps.sh --install  install what is missing with pacman (sudo)
set -uo pipefail

# command:archpackage, grouped by what needs them.
CORE="kpackagetool6:kpackage qdbus6:qt6-tools kwriteconfig6:kconfig kwin_wayland:kwin dbus-run-session:dbus"
# qmllint is asked for by absolute path: the Qt5 build in /usr/bin answers to
# the same name and lints QML differently. reuse is only needed to run the same
# lint the CI job runs.
TESTS="spectacle:spectacle magick:imagemagick python3:python /usr/lib/qt6/bin/qmllint:qt6-declarative /usr/lib/qt6/bin/qsb:qt6-shadertools reuse:reuse shellcheck:shellcheck glslangValidator:shaderc"
TOOLS="gcc:gcc wayland-scanner:wayland pkg-config:pkgconf vulture:vulture"
DEMO="ffmpeg:ffmpeg"
APPS="kcalc:kcalc kwrite:kwrite konsole:konsole dolphin:dolphin gwenview:gwenview"
PYMODS="PIL:python-pillow"

missing=""
report() {   # label "cmd:pkg ..."
    echo "$1:"
    for d in $2; do
        cmd=${d%%:*}; pkg=${d##*:}
        if command -v "$cmd" >/dev/null 2>&1; then printf "  ok       %s\n" "$cmd"
        else printf "  MISSING  %-16s (pacman: %s)\n" "$cmd" "$pkg"; missing="$missing $pkg"; fi
    done
}
report core "$CORE"
report tests "$TESTS"
report tools "$TOOLS"
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
