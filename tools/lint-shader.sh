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

if [ "$fails" -ne 0 ]; then
    echo "lint-shader: $fails shader(s) failed"
    exit 1
fi
echo "lint-shader: all shaders compile in the engine's context"
