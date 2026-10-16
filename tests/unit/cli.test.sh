#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Tests for the CLI's two read-only commands, `kwin-canvas doctor` and
# `kwin-canvas perf`, against a fixture home, a fake qdbus6 and a fake journal:
# no session, no nest and nothing outside a temp directory is touched. Run
# with `make unit`; a failing check prints its name and the output it saw.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
CLI="$HERE/tools/kwin-canvas"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0
fail=0
out=""
rc=0

check() { # NAME CONDITION-EXIT-STATUS
    if [ "$2" -eq 0 ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL %s\n%s\n' "$1" "$out" >&2
    fi
}
has() { # NAME TEXT: the last output contains TEXT
    printf '%s\n' "$out" | grep -qF -- "$2"
    check "$1" $?
}
lacks() { # NAME TEXT
    ! printf '%s\n' "$out" | grep -qF -- "$2"
    check "$1" $?
}
exit_is() { # NAME CODE
    [ "$rc" -eq "$2" ]
    check "$1 (exit $rc, wanted $2)" $?
}

# ---- the fixture: what `make install` leaves, a quiet KWin, a clean config ----
H="$T/home"
DATA="$H/.local/share"
CFG="$H/.config"
PLUG="$T/plugins"
mkdir -p "$DATA/kwin/effects" "$DATA/kwin/decorations" "$DATA/plasma/plasmoids" "$DATA/plasma/wallpapers" "$H/.local/bin" "$CFG" "$PLUG" "$T/bin"

install_fixture() {
    rm -rf "$DATA" "$H/.local/bin/kwin-canvas"
    mkdir -p "$DATA/kwin/effects" "$DATA/kwin/decorations" "$DATA/plasma/plasmoids" "$DATA/plasma/wallpapers" "$H/.local/bin"
    cp -r "$HERE/effect" "$DATA/kwin/effects/kwin-canvas"
    cp "$HERE/shared/Ground.qml" "$DATA/kwin/effects/kwin-canvas/contents/ui/Ground.qml"
    cp -r "$HERE/wallpaper" "$DATA/plasma/wallpapers/kwin-canvas-ground"
    cp "$HERE/shared/Ground.qml" "$DATA/plasma/wallpapers/kwin-canvas-ground/contents/ui/Ground.qml"
    cp -r "$HERE/applet" "$DATA/plasma/plasmoids/org.kde.kwin.canvas.toggle"
    cp -r "$HERE/applet-decor" "$DATA/plasma/plasmoids/org.kde.kwin.canvas.decor"
    cp -r "$HERE/decoration" "$DATA/kwin/decorations/kwin-canvas-decoration"
    cp "$CLI" "$H/.local/bin/kwin-canvas"
}
write_kwinrc() { # extra lines for the [Effect-kwin-canvas] group
    {
        printf '[Effect-kwin-canvas]\nHotRev=0\n%s\n\n' "${1:-}"
        printf '[Plugins]\nkwin-canvasEnabled=%s\n%s\n\n' "${2:-true}" "${3:-}"
        printf '[org.kde.kdecoration2]\nButtonsOnLeft=%s\nButtonsOnRight=%s\nlibrary=org.kde.kwin.aurorae\ntheme=kwin-canvas-decoration\n' "${4:-XSFAI}" "${5:-}"
    } > "$CFG/kwinrc"
}
write_shortcuts() {
    cat > "$CFG/kglobalshortcutsrc" <<'EOF'
[kwin]
Canvas Home=Meta+Ctrl+Space,none,Canvas: return home\\, to the origin
Canvas Fit=none,none,Canvas: zoom to fit
Canvas Switcher=Meta+Tab,none,Canvas: the switcher
Window Close=Alt+F4\tCtrl+Alt+Q,Alt+F4,Close Window
Dup A=Alt+X,none,Foo A
Dup B=Alt+X,none,Foo B

[services][mousetiler.desktop]
_k_friendly_name=Meta+Ctrl+Space
Mouse Tiler: Change Mode=Ctrl+Meta+Space,none,Mouse Tiler: Change Mode
Mouse Tiler: Other=Ctrl+Meta+Z,none,Mouse Tiler: Other
EOF
}
write_clean_shortcuts() {
    grep -v 'Mouse Tiler: Change Mode' "$CFG/kglobalshortcutsrc" > "$T/rc" && mv "$T/rc" "$CFG/kglobalshortcutsrc"
}

# A qdbus6 that answers from FAKE_* variables; FAKE_LOAD unset means the plugin is silent.
cat > "$T/bin/qdbus6" <<'EOF'
#!/bin/sh
case "$*" in
    *isEffectLoaded\ zoom) [ -n "${FAKE_ZOOM:-}" ] && echo "$FAKE_ZOOM" || exit 1 ;;
    *isEffectLoaded\ kwin-canvas) echo "${FAKE_LOADED:-true}" ;;
    *Passthrough.load) [ -n "${FAKE_LOAD:-}" ] && echo "$FAKE_LOAD" || exit 1 ;;
    *) exit 1 ;;
esac
EOF
chmod 755 "$T/bin/qdbus6"
: > "$PLUG/kwin_canvas_passthrough.so"

NOW=$(date +%s)
doctor() { # runs the repo's CLI over the fixture; session started in the future, so nothing is stale
    out=$(env PATH="$T/bin:$PATH" DOCTOR_REPO="${REPO:-$HERE}" DOCTOR_HOME="$H" DOCTOR_PLUGIN_DIR="$PLUG" \
        DOCTOR_KWIN_START="${KSTART:-$((NOW + 1000))}" DOCTOR_PLASMA_START="${PSTART:-$((NOW + 1000))}" DOCTOR_LOAD_WAIT=0 \
        FAKE_LOAD="${FAKE_LOAD-cpu=10 load=0.50 mem=40 gpu=5}" FAKE_ZOOM="${FAKE_ZOOM-false}" FAKE_LOADED="${FAKE_LOADED-true}" \
        bash "$CLI" doctor 2>&1)
    rc=$?
}

install_fixture; write_kwinrc; write_shortcuts; write_clean_shortcuts
unset REPO KSTART PSTART

# ---- doctor: a clean machine ----
doctor
exit_is "clean: exit 0" 0
has "clean: effect matches" "OK    installed  effect matches the repo"
has "clean: CLI matches" "OK    installed  the CLI matches the repo"
has "clean: plugin installed, no build to compare" "no build in the repo to compare it with"
has "clean: nothing stale" "OK    session    main.qml is older than the session"
has "clean: no shortcut conflict" "OK    shortcuts  no key sequence is active"
has "clean: zoom off" "OK    shortcuts  KDE's Zoom effect is not on"
has "clean: ladder full" "OK    ladder     Auto mode, full fidelity now: cpu 10"
has "clean: summary" "0 fail"
lacks "clean: no FAIL line" "FAIL "

# ---- doctor: installed against the repo ----
echo "// drift" >> "$DATA/kwin/effects/kwin-canvas/contents/ui/main.qml"
doctor
exit_is "drift: still exit 0" 0
has "drift: effect warns" "WARN  installed  effect differs from the repo in 1 file(s) (contents/ui/main.qml)"
install_fixture
echo "// drift" >> "$DATA/plasma/wallpapers/kwin-canvas-ground/contents/ui/Ground.qml"
doctor
has "drift: shared Ground.qml compared" "WARN  installed  wallpaper differs from the repo in 1 file(s) (contents/ui/Ground.qml)"
install_fixture
echo "# drift" >> "$H/.local/bin/kwin-canvas"
doctor
has "drift: CLI warns" "WARN  installed  the CLI differs from the repo"
install_fixture
rm -rf "$DATA/plasma/plasmoids/org.kde.kwin.canvas.decor"
doctor
exit_is "missing package: exit 1" 1
has "missing package: FAIL names it" "FAIL  installed  decor applet is not installed"
install_fixture
echo x > "$DATA/kwin/decorations/kwin-canvas-decoration/stray"
doctor
has "stale file in the installed copy" "WARN  installed  decoration differs from the repo in 1 file(s)"
install_fixture

# the plugin: a build that is not what is installed
mkdir -p "$T/repo"
for d in effect wallpaper applet applet-decor decoration shared tools VERSION; do
    ln -sfn "$HERE/$d" "$T/repo/$d"
done
mkdir -p "$T/repo/build/plugin/bin/kwin/plugins"
echo different > "$T/repo/build/plugin/bin/kwin/plugins/kwin_canvas_passthrough.so"
REPO="$T/repo" doctor
has "plugin: differs from the build" "WARN  installed  the plugin differs from the repo's build"
cp "$PLUG/kwin_canvas_passthrough.so" "$T/repo/build/plugin/bin/kwin/plugins/kwin_canvas_passthrough.so"
REPO="$T/repo" doctor
has "plugin: matches the build" "OK    installed  the plugin matches the repo's build"
rm -f "$PLUG/kwin_canvas_passthrough.so"
doctor
has "plugin: absent is a warning" "WARN  installed  the pass-through plugin is not installed"
: > "$PLUG/kwin_canvas_passthrough.so"

# a CLI run from outside a checkout has nothing to compare with
mkdir -p "$T/loose"
cp "$CLI" "$T/loose/kwin-canvas"
out=$(env PATH="$T/bin:$PATH" DOCTOR_HOME="$H" DOCTOR_PLUGIN_DIR="$PLUG" DOCTOR_KWIN_START=$((NOW + 1000)) DOCTOR_PLASMA_START=$((NOW + 1000)) DOCTOR_LOAD_WAIT=0 FAKE_LOAD="cpu=1 load=0 mem=1 gpu=-1" bash "$T/loose/kwin-canvas" doctor 2>&1)
rc=$?
has "no checkout: says so" "no source tree to compare with"
exit_is "no checkout: not a failure" 0

# ---- doctor: the session is older than the files ----
KSTART=$((NOW - 5000)) PSTART=$((NOW - 5000)) doctor
has "stale: main.qml" "WARN  session    main.qml is newer than the session: relogin to load it"
has "stale: ui.qml with no hot reload after it" "WARN  session    ui.qml is newer than the session and no hot reload followed it"
has "stale: applets" "WARN  session    an applet or the ground wallpaper is newer than plasmashell"
exit_is "stale: warnings are not failures" 0
write_kwinrc "HotRev=7"
KSTART=$((NOW - 5000)) doctor
has "stale: ui.qml hot-loaded" "OK    session    ui.qml is newer than the session but kwinrc was written after it (HotRev 7)"
write_kwinrc

# ---- doctor: shortcuts ----
write_shortcuts
doctor
exit_is "conflict: exit 1" 1
has "conflict: FAIL names the canvas action, commas unescaped" 'FAIL  shortcuts  Meta+Ctrl+Space is bound to "Canvas: return home, to the origin" | "Mouse Tiler: Change Mode"'
lacks "conflict: no Foo (not a Canvas action)" "Foo A"
lacks "conflict: _k_friendly_name is not a binding" "Meta+Z"
lacks "conflict: a tab-separated second key is not a clash" "Alt+F4"
write_clean_shortcuts
FAKE_ZOOM=true doctor
has "zoom: loaded warns" "WARN  shortcuts  KDE's Zoom effect is on"
exit_is "zoom: only a warning" 0
FAKE_ZOOM="" write_kwinrc "" true "zoomEnabled=true"
FAKE_ZOOM="" doctor
has "zoom: kwinrc fallback when KWin does not answer" "WARN  shortcuts  KDE's Zoom effect is on"
write_kwinrc

# ---- doctor: the fidelity ladder ----
FAKE_LOAD="cpu=85 load=1.00 mem=50 gpu=-1" doctor
has "ladder: cpu 85 is minimal" "WARN  ladder     Auto mode, the machine is busy: the overworld would run at rung 2 (minimal)"
has "ladder: gpu absent said so" "gpu not readable"
FAKE_LOAD="cpu=10 load=0.1 mem=98 gpu=5" doctor
has "ladder: memory 98 is bare" "rung 3 (bare)"
FAKE_LOAD="cpu=10 load=0.1 mem=40 gpu=62" doctor
has "ladder: gpu 62 is reduced" "rung 1 (reduced)"
write_kwinrc "GpuReduced=70"
FAKE_LOAD="cpu=10 load=0.1 mem=40 gpu=62" doctor
has "ladder: a tuned threshold is honoured" "OK    ladder     Auto mode, full fidelity now"
write_kwinrc "QualityMode=Full"
FAKE_LOAD="cpu=99 load=9 mem=40 gpu=5" doctor
has "ladder: a held mode says so" "OK    ladder     mode Full holds its rung"
write_kwinrc
FAKE_LOAD="" doctor
has "ladder: a silent plugin is a warning" "WARN  ladder     the pass-through plugin does not answer"
exit_is "ladder: silent plugin is not a failure" 0

# ---- doctor: enabled state and the pill's letters ----
write_kwinrc "" false
FAKE_LOADED=false doctor
has "enabled: off warns" "WARN  enabled    the effect is not enabled"
doctor
has "enabled: loaded but not enabled warns" "WARN  enabled    the effect is loaded now but kwinrc does not enable it"
write_kwinrc "" true
FAKE_LOADED=false doctor
exit_is "enabled but not loaded: exit 1" 1
has "enabled but not loaded: FAIL" "FAIL  enabled    the effect is enabled in kwinrc but KWin has not loaded it"
write_kwinrc "" true "" "MSL" "HIAXE_"
doctor
has "buttons: pill-only letters" "only the pill draws: M H"
has "buttons: applet-only letter" "only the applet draws: E"
has "buttons: letters neither draws" "neither draws: L"
has "buttons: both sides read" "buttons left 'MSL' right 'HIAXE_'"
write_kwinrc

# ---- perf ----
cat > "$T/journal" <<'EOF'
Oct 16 12:00:00 host kwin_wayland[1]: qml: kwin-canvas perf: open
kwin-canvas perf: open
kwin-canvas perf: open
kwin-canvas perf: first-paint ms=10
kwin-canvas perf: first-paint ms=20
kwin-canvas perf: first-paint ms=30
kwin-canvas perf: first-paint ms=40
kwin-canvas perf: settle ms=100 zoom=0.5
kwin-canvas perf: settle ms=300 zoom=0.4
kwin-canvas perf: settle ms=200 zoom=0.45
kwin-canvas perf: slide dist=1200 ms=380
kwin-canvas perf: ticks n=120 p50=16.6 p95=21.1 max=48.2
kwin-canvas perf: hover-fetch ms=7
something unrelated
EOF
out=$(bash "$CLI" perf --from "$T/journal" 2>&1)
rc=$?
exit_is "perf: exit 0" 0
has "perf: line count" "13 lines"
has "perf: open counted" "open         -          3"
has "perf: first-paint stats" "first-paint  ms         4        10        25        40        40"
has "perf: settle ms sorted before stats" "settle       ms         3       100       200       300       300"
has "perf: a decimal key" "settle       zoom       3       0.4      0.45       0.5       0.5"
has "perf: ticks p50 is a float" "ticks        p50        1      16.6      16.6      16.6      16.6"
has "perf: slide dist" "slide        dist       1      1200      1200      1200      1200"
has "perf: hover-fetch" "hover-fetch  ms         1         7         7         7         7"
: > "$T/empty"
out=$(bash "$CLI" perf --from "$T/empty" 2>&1)
rc=$?
exit_is "perf: nothing to read is not an error" 0
has "perf: says plainly nothing was found" "no perf lines since"
out=$(bash "$CLI" perf --bogus 2>&1)
rc=$?
exit_is "perf: an unknown option fails" 1
out=$(bash "$CLI" perf --from "$T/does-not-exist" 2>&1)
rc=$?
exit_is "perf: an unreadable file fails" 1

echo "cli: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
