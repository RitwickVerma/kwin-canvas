#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Compile every shaders/*.frag exactly the way the shader wallpaper's engine
# would: the engine's own header (tests/shaders/engine-header.inc), the shader,
# and the mainImage wrapper. The engine concatenates header + shader + footer,
# so a uniform declared twice - once in a fork's header and once in the shader -
# is a compile error; this catches that class and any GLSL break before it
# reaches a user's desktop.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GLSLANG="${GLSLANG:-glslangValidator}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
fails=0

for frag in "$HERE"/shaders/*.frag; do
    name="$(basename "$frag")"
    {
        cat "$HERE/tests/shaders/engine-header.inc"
        grep -v '^// @channels' "$frag"
        echo 'void main() { mainImage(fragColor, fragCoord); }'
    } > "$OUT/$name"
    if ! "$GLSLANG" -l "$OUT/$name" >/dev/null 2>&1; then
        echo "shader $name failed to compile:"
        "$GLSLANG" -l "$OUT/$name" 2>&1 | tail -5
        fails=$((fails + 1))
    fi
done

# The effect's precompiled plane shader is a committed build of
# shared/GroundBarrel.frag; a stale pair would ship the wrong bend, so the
# regeneration must be byte-identical (`make barrel` rebuilds it).
QSB="${QSB:-/usr/lib/qt6/bin/qsb}"
if [ -x "$QSB" ]; then
    if "$QSB" --glsl "320 es,330,440" "$HERE/shared/GroundBarrel.frag" -o "$OUT/GroundBarrel.frag.qsb" >/dev/null 2>&1 \
       && cmp -s "$OUT/GroundBarrel.frag.qsb" "$HERE/shared/GroundBarrel.frag.qsb"; then
        :
    else
        echo "shared/GroundBarrel.frag.qsb is not this qsb's build of shared/GroundBarrel.frag (run: make barrel, and inspect the diff)"
        fails=$((fails + 1))
    fi
else
    echo "lint-shader: $QSB not found; skipping the plane shader's regen check"
fi

if [ "$fails" -ne 0 ]; then
    echo "lint-shader: $fails shader(s) failed"
    exit 1
fi
echo "lint-shader: all shaders compile in the engine's context"
