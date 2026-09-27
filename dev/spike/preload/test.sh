#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Spike gate: real fake-input events against the preload nest, with the shim's
# transform s=0.5 o=(100,50) (plane = (screen - o) / s) and then cleared.
# Probe A sits inside the output, Probe B at plane (2400,1400), outside it.
# The kwin-canvas effect is unloaded first: at 1:1 it pans the view to bring
# an activated off-output window into the frame, which moves every window
# (observed: clicking B at plane (2400,1400) shifted all windows by
# (-1640,-1024)). The shim's transform is independent of the effect here.
# Brings the nest up and always tears it down.

set -uo pipefail
SPIKE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
N="$SPIKE/nest-preload.sh"
STATE=${XDG_RUNTIME_DIR:-/tmp}/kwin-canvas-nest-preload
PLOG=$STATE/probe.log
PASS=0; FAIL=0
trap '"$N" down >/dev/null 2>&1' EXIT

ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1 = $3"; else bad "$1: expected '$3', got '$2'"; fi; }

input() { "$N" input >/dev/null; sleep 0.4; }
# lastp EVENT -> "Probe X ARGS" of the newest probe line with that event
lastp() { grep -a "PROBE .* $1" "$PLOG" | tail -1 | sed 's/.*PROBE //'; }
mark()  { : > "$PLOG"; }
jsq()   { "$N" js "$1"; }
cursor() { jsq 'out(Math.round(workspace.cursorPos.x) + " " + Math.round(workspace.cursorPos.y))'; }
active() { jsq 'out(workspace.activeWindow ? workspace.activeWindow.caption : "none")'; }
frame()  { jsq 'for (const w of workspace.windowList()) if (w.caption == "'"$1"'") out(Math.round(w.frameGeometry.x) + " " + Math.round(w.frameGeometry.y))'; }

"$N" down >/dev/null 2>&1
"$N" build >/dev/null
"$N" up || exit 1
rm -f "$PLOG"
nq() { "$N" nq "$@"; }
nq org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect kwin-canvas
check "effect unloaded" "$(nq org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded kwin-canvas)" "false"
"$N" probe A; "$N" probe B; sleep 3
jsq 'for (const w of workspace.windowList()) {
  if (w.caption == "Probe A") w.frameGeometry = {x: 100, y: 100, width: 400, height: 328};
  if (w.caption == "Probe B") w.frameGeometry = {x: 2400, y: 1400, width: 400, height: 328}; }'
echo "windows: $(jsq 'for (const w of workspace.windowList()) out(w.caption + " client=" + w.clientGeometry.x + "," + w.clientGeometry.y)' | tr '\n' ';')"

echo "stock (no transform file)"
"$N" tf off >/dev/null
mark; printf 'move 300 250\nsleep 50\nclick\nsleep 50\nkey a\n' | input
check "click screen (300,250)" "$(lastp press)" "Probe A press 200.0 122.0"
check "key after click" "$(lastp key)" "Probe A key a 65"
check "cursor" "$(cursor)" "300 250"

echo "transform s=0.5 o=(100,50)"
"$N" tf 0.5 100 50 >/dev/null
# A-local (200,122) = plane (300,250) = screen (250,175)
mark; printf 'move 250 175\nsleep 50\nclick\n' | input
check "click screen (250,175) -> A" "$(lastp press)" "Probe A press 200.0 122.0"
check "cursor is plane" "$(cursor)" "300 250"
# relative motion is divided by s: screen +10,+10 = plane +20,+20
printf 'rel 10 10\n' | input
check "rel 10 10 in plane" "$(cursor)" "320 270"
# B-local (150,100) = plane (2550,1528) = screen (1375,814): outside the output in the plane
mark; printf 'move 1375 814\nsleep 50\nclick\nsleep 50\nkey b\n' | input
check "click screen (1375,814) -> B outside output" "$(lastp press)" "Probe B press 150.0 100.0"
check "focus follows click" "$(active)" "Probe B"
check "typing reaches B" "$(lastp key)" "Probe B key b 66"
printf 'move 1919 1079\n' | input
check "cursor at drawn corner" "$(cursor)" "3638 2058"
printf 'move 3000 2000\n' | input
check "cursor clamped to output image" "$(cursor)" "3639 2059"
# A's title bar: plane (300,114) = screen (250,107); drag screen +100,+50 = plane +200,+100
printf 'drag 250 107 350 157 20 10\n' | input
check "title-bar drag moves A in plane" "$(frame "Probe A")" "300 200"

echo "cleared"
"$N" tf off >/dev/null
# A is now at client (300,228); screen (400,300) is A-local (100,72) with no transform
mark; printf 'move 400 300\nsleep 50\nclick\n' | input
check "click screen (400,300) stock" "$(lastp press)" "Probe A press 100.0 72.0"
check "cursor is screen" "$(cursor)" "400 300"

check "shim armed" "$(grep -ac "kwin-canvas-preload: armed" "$STATE/kwin.log")" "1"
echo "shim log:"
grep -a "kwin-canvas-preload" "$STATE/kwin.log" | head -4 | sed 's/^/  /'
echo "pass $PASS fail $FAIL"
[ "$FAIL" = 0 ]
