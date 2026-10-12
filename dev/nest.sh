#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Nested KWin harness for kwin-canvas.
#
# Runs a second kwin_wayland as a window inside the live session, on its own
# D-Bus session bus and with its own XDG_CONFIG_HOME, so the effect can be
# enabled, driven and screenshotted without touching the real desktop. The
# pass-through plugin is picked up from build/plugin/bin when it is built.
#
#   dev/nest.sh up            start nested KWin with the effect enabled
#   dev/nest.sh down          stop it
#   dev/nest.sh run CMD...    launch a client into the nested session
#   dev/nest.sh cmd "pan 100 0"   send a debug command to the effect
#   dev/nest.sh toggle        press Meta+Space inside the nested session
#   dev/nest.sh shot [file]   screenshot the nested session
#   dev/nest.sh log           tail the nested KWin log
#   dev/nest.sh state         print effect state from the log
#   dev/nest.sh reload        reinstall, restart the nest, relaunch clients
#   dev/nest.sh clients       launch the default test clients (NEST_CLIENTS)
#   dev/nest.sh fixtures      launch the fixture set of KDE apps on fixture files
#   dev/nest.sh input CMDS    inject pointer/keyboard events (see tools/fakeinput.c)
#   dev/nest.sh clean         kill leftovers of nests whose state is gone
#   dev/nest.sh shell         start plasmashell in the nest (up does this; NEST_SHELL=0 skips)
#   dev/nest.sh js 'CODE'     run a KWin script in the nest; its out() lines come back
#   dev/nest.sh probe NAME    launch a probe window titled "Probe NAME" that logs
#                             presses, releases and keys to $STATE/probe.log
#
# NEST_NAME=foo runs a second, independent nest (own socket, bus, config, log).
# NEST_WALLPAPER=0 keeps the plain grid instead of tiling the fixture wallpaper.
# NEST_OUTPUTS=2 gives the nest two side-by-side outputs (one frame each).
# NEST_VIRTUAL=1 renders to KWin's virtual framebuffer instead of a window on
# the live desktop: nothing to look at, but frames keep coming at full rate
# when the nest would be hidden or covered. The tests use it.
# NEST_PRELOAD=SHIM.so NEST_KWIN=BINARY runs BINARY (a capability-free copy of
# kwin_wayland) with the plane-input shim of dev/spike/preload preloaded, and
# leaves the pass-through plugin off the plugin path.
# NEST_BORDERS=0,1,2,3,4,5,6,7 seeds every screen border into the effect's
# BorderActivate; the default is 7, the top-left corner.
# The nest has its own activity manager with two seeded activities, so the
# frame groups and the send-to menu have something to show.
# The file is sourceable: `source dev/nest.sh` exposes every function without
# running a command, which is how tests/lib.sh reuses it.
#
# Debug commands: open commit cancel toggle home extents state
#                 pan DX DY | zoom Z [X Y] | shift DX DY | slide DX DY
#                 panstep DX DY | swipe DX DY PROGRESS|end|cancel | enter

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NEST_NAME=${NEST_NAME:-kwincanvas}
STATE=${XDG_RUNTIME_DIR:-/tmp}/kwin-canvas-nest-$NEST_NAME
CONF=$STATE/config
SOCKET=wayland-$NEST_NAME
WIDTH=${NEST_WIDTH:-1920}
HEIGHT=${NEST_HEIGHT:-1080}
OUTPUTS=${NEST_OUTPUTS:-1}
VIRTUAL=${NEST_VIRTUAL:-0}
LOG=$STATE/kwin.log
FIXTURES=$HERE/tests/fixtures
# Fixed ids for the two seeded activities, so tests can name them.
ACT1=11111111-1111-4111-8111-111111111111
ACT2=22222222-2222-4222-8222-222222222222

bus() { cat "$STATE/bus" 2>/dev/null; }
# Everything a nest runs (compositor, bus, daemons, shell, clients) runs
# niced and at idle I/O priority, so it never contends with the live
# session's compositor on equal terms.
LOW=(nice -n 10 ionice -c3)
# The nest's XDG homes: config, state and cache live under $STATE for the
# compositor, its bus and every client, so none of them writes session
# state or caches (shader, sycoca, QML) into the real home. The data home
# is the nest's for the compositor, its bus and every client alike: the
# fixture apps' window state (Dolphin's view properties, Gwenview's
# history) must be the nest's own, or one golden run inherits whatever the
# user's real apps saved last - the look itself is pinned by the config,
# not borrowed. ~/.local/share stays first on the data search path for the
# installed packages.
nest_env() {
    # XDG_CURRENT_DESKTOP=KDE: the portal broker the bus activates inherits
    # this, so it picks the KDE backend instead of the GTK one, whose
    # ScreenCast impl hangs on a compositor interface KWin does not speak.
    printf '%s\n' "XDG_CONFIG_HOME=$CONF" "XDG_STATE_HOME=$STATE/state" "XDG_CACHE_HOME=$STATE/cache" \
        "XDG_DATA_HOME=$STATE/data" "XDG_CURRENT_DESKTOP=KDE" \
        "XDG_DATA_DIRS=$HOME/.local/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
}
# The nest's bus address, or a loud failure: an empty DBUS_SESSION_BUS_ADDRESS
# makes D-Bus fall back to the live session's bus.
nestbus() {
    local b; b=$(bus) || true
    [ -n "$b" ] || { echo "nest $NEST_NAME has no bus ($STATE/bus); not falling back to the session bus" >&2; return 1; }
    echo "$b"
}
nq() { local b; b=$(nestbus) || return 1; DBUS_SESSION_BUS_ADDRESS=$b qdbus6 "$@"; }
alive() { [ -f "$STATE/pid" ] && kill -0 "$(cat "$STATE/pid")" 2>/dev/null; }

# The fixture wallpaper for a space (1-based). NEST_WALLPAPER=0 disables
# image wallpapers and leaves the Canvas Ground grid at 1:1.
wallpaper_file() {
    [ "${NEST_WALLPAPER:-1}" = 1 ] || { echo ""; return; }
    [ -f "$FIXTURES/wallpaper-${1:-1}.png" ] || python3 "$FIXTURES/gen.py" >/dev/null
    echo "file://$FIXTURES/wallpaper-${1:-1}.png"
}

seed_config() {
    mkdir -p "$CONF" "$CONF/xdg-desktop-portal"
    # The preferred portal backend, in case anything reads the broker's
    # config before the bus env: KDE, whose screencast KWin serves.
    printf '%s\n' '[preferred]' 'default=kde' > "$CONF/xdg-desktop-portal/portals.conf"
    cat > "$CONF/kwinrc" <<CFG
[Plugins]
kwin-canvasEnabled=true
zoomEnabled=false
overviewEnabled=false
blurEnabled=false
contrastEnabled=false

[Effect-kwin-canvas]
PublishGround=true
BorderActivate=${NEST_BORDERS:-7}
# The motion knobs are off in the nest, so a scenario measures the canvas and
# not the spring: every drag lands exactly where it was put and every camera
# move arrives at once. 94-physics turns them on and measures them, and the
# layout glides (MovesGlide) are the same story: a placed window is found at
# its landing, not on its way there.
PanInertia=false
SmoothZoom=false
WindowPhysics=false
MovesGlide=false
# The fidelity ladder reads the machine's real load, and the machine that
# runs the suite IS busy with the suite: the thresholds are pinned at 100 so
# a scenario's golden never depends on how hard the host is breathing.
# 116-quality overrides them and deletes them itself.
CpuReduced=100
CpuMinimal=100
CpuBare=100
GpuReduced=100
GpuMinimal=100
GpuBare=100
MemReduced=100
MemMinimal=100
MemBare=100
DebugSeq=0
ToggleShortcut=Ctrl+Alt+Space
HomeShortcut=Ctrl+Alt+Home
PanLeftShortcut=Ctrl+Alt+Left
PanRightShortcut=Ctrl+Alt+Right
PanUpShortcut=Ctrl+Alt+Up
PanDownShortcut=Ctrl+Alt+Down

[Compositing]
Backend=OpenGL

[org.kde.kdecoration2]
NoPlugin=false
library=org.kde.breeze
theme=Breeze

[Desktops]
Number=2
Rows=1
CFG
    # The canvas decoration is a QML theme: the aurorae engine must be
    # asked for it by name (the library + the theme), and the nest only
    # wears it when 135 asks (NEST_DECOR=canvas) - every other scenario
    # keeps Breeze so no golden's frame pixels move.
    if [ "${NEST_DECOR:-}" = canvas ]; then
        kwriteconfig6 --file "$CONF/kwinrc" --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
        kwriteconfig6 --file "$CONF/kwinrc" --group org.kde.kdecoration2 --key theme kwin-canvas-decoration
        kwriteconfig6 --file "$CONF/kwinrc" --group org.kde.kwin.aurorae --key theme kwin-canvas-decoration
        # The nest's XDG_DATA_HOME is its own, so the decoration must be
        # copied into it: the nest's kwin scans $STATE/data/kwin/decorations,
        # never the user's ~/.local/share.
        if [ -d "$HOME/.local/share/kwin/decorations/kwin-canvas-decoration" ]; then
            mkdir -p "$STATE/data/kwin/decorations"
            cp -r "$HOME/.local/share/kwin/decorations/kwin-canvas-decoration" "$STATE/data/kwin/decorations/"
        fi
    fi
    # kded's GTK module writes $HOME/.gtkrc-2.0 whatever XDG_CONFIG_HOME
    # says, and the live session's kded reloads its xsettings on that.
    cat > "$CONF/kded5rc" <<CFG
[Module-gtkconfig]
autoload=false
CFG
    # The fixture apps' look is pinned, not inherited: whatever the host's
    # default colour scheme happens to be today, the nest draws Breeze Dark
    # with the dark icon theme, so a golden screenshot means the same pixels
    # on every machine and every day.
    cat > "$CONF/kdeglobals" <<CFG
[General]
ColorScheme=BreezeDark

[Icons]
Theme=breeze-dark

[KDE]
widgetStyle=Breeze
CFG
    # The nest's activity manager reads these; the state file (XDG_STATE_HOME)
    # names the current one. Rewritten on every up, so an added activity
    # never lingers.
    cat > "$CONF/kactivitymanagerdrc" <<CFG
[activities]
$ACT1=Activity 1
$ACT2=Activity 2
CFG
    mkdir -p "$STATE/state" "$STATE/data" "$STATE/cache"
    cat > "$STATE/state/kactivitymanagerdstaterc" <<CFG
[main]
currentActivity=$ACT1
CFG
}

# plasmashell inside the nest, shaped through its scripting interface after it
# starts: no panels, the Canvas Ground wallpaper, and a folder view on an
# empty directory. This is the same evaluateScript path the effect uses to
# publish the ground offset, so the handoff is exercised on every nest.
shell() {
    [ "${NEST_SHELL:-1}" = 1 ] || return 0
    mkdir -p "$STATE/desktop"
    RUN_LOG="$STATE/plasmashell.log" run plasmashell --no-respawn
    local ok=0
    for _ in $(seq 1 60); do
        nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "1" >/dev/null 2>&1 && { ok=1; break; }
        sleep 0.25
    done
    [ "$ok" = 1 ] || { echo "plasmashell did not come up; see: dev/nest.sh log"; return 1; }
    local wp; wp=$(wallpaper_file 1)
    if [ -n "$wp" ]; then
        # Stock image wallpaper, one per activity in name order: the frame
        # interior is a real picture, and 1:1 is that picture. The ground
        # grid lives in the effect only.
        nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
            for (const p of panels()) p.remove();
            const ids = activities().slice().sort(function (a, b) { return activityName(a) < activityName(b) ? -1 : 1; });
            for (let i = 0; i < ids.length; ++i) {
                for (const d of desktopsForActivity(ids[i])) {
                    d.currentConfigGroup = ['General'];
                    d.writeConfig('url', 'file://$STATE/desktop');
                    d.wallpaperPlugin = 'org.kde.image';
                    d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
                    d.writeConfig('Image', 'file://$FIXTURES/wallpaper-' + ((i % 4) + 1) + '.png');
                    d.writeConfig('FillMode', 2);
                    d.reloadConfig();
                }
            }" >/dev/null
    else
        nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
            for (const p of panels()) p.remove();
            for (const d of desktops()) {
                d.currentConfigGroup = ['General'];
                d.writeConfig('url', 'file://$STATE/desktop');
                d.wallpaperPlugin = 'kwin-canvas-ground';
                d.currentConfigGroup = ['Wallpaper', 'kwin-canvas-ground', 'General'];
                d.writeConfig('OffsetX', 0);
                d.writeConfig('OffsetY', 0);
            }" >/dev/null
    fi
    if [ "${NEST_PANEL:-0}" = 1 ]; then
        # The default Plasma layout carries a panel with the clock: the dock
        # scenarios need one (86, 117). Everything else keeps the panel-free
        # nest, so a panel never sits under a golden's pixels.
        nq org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.loadLookAndFeelDefaultLayout "org.kde.plasma.desktop" >/dev/null
    fi
    echo "plasmashell up"
}

up_once() {
    if alive; then echo "already up (pid $(cat "$STATE/pid"))"; return 0; fi
    mkdir -p "$STATE"; rm -f "$STATE/bus" "$STATE/clients" "$STATE/pid"
    seed_config
    # setsid: the nest gets its own session so nothing that happens to the
    # shell or make that started it can reap it. The pid recorded is
    # dbus-run-session's, written from inside as its child's $PPID. The
    # environment goes on dbus-run-session itself, so the daemons the bus
    # activates (the activity manager above all) read the nest's config.
    # The XDG homes are the nest's (nest_env), so the activity manager's
    # database is not the live session's.
    # With a shim, LD_PRELOAD goes on kwin_wayland alone: dbus-run-session and
    # bash stay clean, and the shim unsets it so KWin's children do not
    # inherit it.
    # The bus and every daemon it activates (portals, the activity manager,
    # the secret service) see the nest's Wayland socket and no X display, so
    # none of them connects to the live session's compositor or Xwayland;
    # kwin_wayland alone gets the caller's displays back, which a windowed
    # nest needs.
    local kwin=kwin_wayland plugins="$HERE/build/plugin/bin${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}:/usr/lib/qt6/plugins"
    if [ -n "${NEST_PRELOAD:-}" ]; then
        kwin=${NEST_KWIN:?NEST_PRELOAD needs NEST_KWIN, a capability-free kwin_wayland}
        plugins=${QT_PLUGIN_PATH:-}
    fi
    (
        cd "$STATE"
        setsid -f "${LOW[@]}" env -u DISPLAY WAYLAND_DISPLAY="$SOCKET" \
            NEST_HOST_WAYLAND="${WAYLAND_DISPLAY:-}" NEST_HOST_DISPLAY="${DISPLAY:-}" \
            $(nest_env) \
            QT_LOGGING_TO_CONSOLE=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
            QT_PLUGIN_PATH="$plugins" NEST_KWIN_BIN="$kwin" NEST_KWIN_PRELOAD="${NEST_PRELOAD:-}" \
            dbus-run-session -- bash -c '
            echo "$PPID" > "$0/pid"
            echo "$DBUS_SESSION_BUS_ADDRESS" > "$0/bus"
            export WAYLAND_DISPLAY="$NEST_HOST_WAYLAND"
            [ -n "$NEST_HOST_DISPLAY" ] && export DISPLAY="$NEST_HOST_DISPLAY"
            unset NEST_HOST_WAYLAND NEST_HOST_DISPLAY
            exec stdbuf -oL -eL env ${NEST_KWIN_PRELOAD:+LD_PRELOAD="$NEST_KWIN_PRELOAD"} "$NEST_KWIN_BIN" '"$([ "$VIRTUAL" = 1 ] && echo --virtual)"' --width '"$WIDTH"' --height '"$HEIGHT"' --output-count '"$OUTPUTS"' --xwayland --no-lockscreen --socket '"$SOCKET"'
        ' "$STATE" > "$LOG" 2>&1
    )
    for _ in $(seq 1 50); do
        [ -f "$STATE/bus" ] && nq org.kde.KWin /KWin org.kde.KWin.supportInformation >/dev/null 2>&1 && break
        sleep 0.2
    done
    for _ in $(seq 1 50); do
        nq org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded kwin-canvas 2>/dev/null | grep -q true && break
        sleep 0.2
    done
    if nq org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded kwin-canvas 2>/dev/null | grep -q true; then
        echo "nested KWin up, effect loaded (socket $SOCKET)"
    else
        echo "nested KWin up but effect NOT loaded; see: dev/nest.sh log"
    fi
    # The effect's QML completes asynchronously after isEffectLoaded turns
    # true, and a debug command sent before it completes is lost (the
    # reconfigure never fires onConfigurationChanged). Wait until a command
    # answers, so the first scenario command is never swallowed. A nest whose
    # effect never answers is broken - restart it, up to three tries.
    local ready=0
    for attempt in 1 2 3; do
        for _ in $(seq 1 40); do
            cmd state >/dev/null 2>&1 || true
            [ -n "$(state)" ] && break
            sleep 0.25
        done
        if [ -n "$(state)" ]; then ready=1; break; fi
        echo "nested KWin's effect did not answer; restarting (attempt $attempt)" >&2
        down >/dev/null 2>&1
        up_once
    done
    if [ "$ready" = 0 ]; then
        echo "nested KWin's effect never answered; see: dev/nest.sh log" >&2
        return 1
    fi
    unrealtime
    shell
}

up() {
    up_once
}

# /usr/bin/kwin_wayland carries cap_sys_nice and gives its threads
# SCHED_RR, the live compositor's own class. A nest's compositor drops back
# to the normal class, which an unprivileged process may always do.
unrealtime() {
    local pid t
    pid=$(pgrep -P "$(cat "$STATE/pid" 2>/dev/null)" 2>/dev/null | head -1) || return 0
    [ -n "$pid" ] || return 0
    for t in /proc/"$pid"/task/*; do
        chrt -p "${t##*/}" 2>/dev/null | grep -q SCHED_OTHER || chrt -o -p 0 "${t##*/}" 2>/dev/null || true
    done
}

# Every process attached to the nest's private bus: the compositor, the
# clients launched into it, and the daemons D-Bus activated there (portals,
# kactivitymanagerd, kglobalacceld). Those daemons outlive the bus otherwise.
# The environment is read whole before it is matched: under pipefail a
# grep -q that stops at the match fails the pipeline once tr is still
# writing, and the daemons' environments are large enough for that.
pids_on_bus() {   # pids_on_bus BUS_ADDRESS
    local addr=$1 p env
    for p in /proc/[0-9]*; do
        env=$({ tr '\0' '\n' < "$p/environ"; } 2>/dev/null) || continue
        if grep -qxF "DBUS_SESSION_BUS_ADDRESS=$addr" <<<"$env"; then
            echo "${p#/proc/}"
        fi
    done
}

down() {
    local addr; addr=$(bus) || true
    if [ -f "$STATE/pid" ]; then
        pkill -P "$(cat "$STATE/pid")" 2>/dev/null || true
        kill "$(cat "$STATE/pid")" 2>/dev/null || true
    fi
    if [ -n "$addr" ]; then
        local pids; pids=$(pids_on_bus "$addr")
        # A pid already gone fails kill, which must not end down under set -e.
        [ -n "$pids" ] && { kill $pids 2>/dev/null || true; }
        sleep 0.3
        pids=$(pids_on_bus "$addr")
        [ -n "$pids" ] && { kill -9 $pids 2>/dev/null || true; }
    fi
    rm -f "$STATE/pid" "$STATE/bus" "$STATE/clients"
    echo "down"
}

# Kill leftovers from nests whose state is gone. A process belongs to a nest
# only by the nest's own marker: XDG_CONFIG_HOME under
# $XDG_RUNTIME_DIR/kwin-canvas-nest-NAME/, which the compositor, the daemons
# its bus activates and every client run() or probe() starts carry. Running
# nests are kept, and so is any compositor serving the caller's
# WAYLAND_DISPLAY, so a live session can never match.
clean() {
    local rt=${XDG_RUNTIME_DIR:-/tmp} p conf name sock n=0
    for p in /proc/[0-9]*; do
        conf=$({ cat "$p/environ" 2>/dev/null || true; } | tr '\0' '\n' | sed -n 's/^XDG_CONFIG_HOME=//p')
        case "$conf" in "$rt"/kwin-canvas-nest-*/config) ;; *) continue ;; esac
        name=${conf#"$rt"/kwin-canvas-nest-}; name=${name%/config}
        if [ -f "$rt/kwin-canvas-nest-$name/pid" ] && kill -0 "$(cat "$rt/kwin-canvas-nest-$name/pid")" 2>/dev/null; then
            continue
        fi
        sock=$({ cat "$p/cmdline" 2>/dev/null || true; } | tr '\0' '\n' | { grep -A1 -x -- --socket || true; } | tail -1)
        if [ -n "$sock" ] && [ "$sock" = "${WAYLAND_DISPLAY:-}" ]; then
            continue
        fi
        if kill "${p#/proc/}" 2>/dev/null; then n=$((n + 1)); fi
    done
    local d
    for d in "$rt"/kwin-canvas-nest-*; do
        if [ -f "$d/pid" ] && ! kill -0 "$(cat "$d/pid")" 2>/dev/null; then
            rm -f "$d/pid" "$d/bus"
        fi
    done
    echo "cleaned $n orphaned processes"
}

run() {
    alive || { echo "not up"; exit 1; }
    local b; b=$(nestbus) || exit 1
    # The session exports QT_WAYLAND_RECONNECT=1 (startplasma sets it for the
    # whole desktop), and Qt treats the variable's PRESENCE - not its value -
    # as the reconnect switch. When the nest's compositor goes away at
    # down/reload, the fixture apps walk Qt's reconnect path and die in
    # QWaylandShmBuffer's null deref. The nest's clients are disposable by
    # design: genuinely unset the variable for them (never =0 - the presence
    # check ignores the value), and keep a teardown from dropping cores into
    # the session's journal.
    ( export WAYLAND_DISPLAY=$SOCKET DBUS_SESSION_BUS_ADDRESS=$b $(nest_env client); unset DISPLAY QT_WAYLAND_RECONNECT; ulimit -c 0; "${LOW[@]}" "$@" >"${RUN_LOG:-/dev/null}" 2>&1 & echo $! >> "$STATE/clients" )
    echo "launched: $*"
}

cmd() {
    alive || { echo "not up"; exit 1; }
    local seq
    seq=$(kreadconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key DebugSeq --default 0)
    seq=$((seq + 1))
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key DebugCommand "$1"
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key DebugSeq "$seq"
    nq org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect kwin-canvas
    sleep 0.3
    state
}

toggle() {
    nq org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Toggle Canvas"
}

shot() {
    alive || { echo "not up"; exit 1; }
    local out=${1:-$STATE/shot-$(date +%H%M%S).png}
    local b; b=$(nestbus) || return 1
    env -u DISPLAY DBUS_SESSION_BUS_ADDRESS="$b" WAYLAND_DISPLAY=$SOCKET QT_QPA_PLATFORM=wayland $(nest_env client) \
        spectacle -b -n -f -o "$out" >/dev/null 2>&1 || true
    [ -s "$out" ] && echo "$out" || echo "screenshot failed"
}

# The effect logs one message with newlines in it, so the state is the line
# that names it plus every indented line that follows: the outputs first, then
# each activity's target, then each entry. The indented lines are matched by
# shape ("  {" / "  [" / "  screen[") because awk's bracket expressions read
# "[\[{]" as one character class and would silently stop at the first screen
# line, leaving sget() the summary and eget()/tget() nothing.
state() {
    awk '/kwin-canvas state/{buf=$0; sub(/.*kwin-canvas state/, "state", buf); buf=buf "\n"; on=1; next}
         on && /^  (\[|\{|screen\[|c[0-9])/{buf=buf $0 "\n"; next}
         {on=0}
         END{printf "%s", buf}' "$LOG"
    grep -a -A30 "kwin-canvas windows:" "$LOG" | tail -n +2 | grep -a "^  [* ] " | tail -20 || true
}

log() { tail -n "${1:-60}" "$LOG"; }

# KWin's QML engine caches components by URL, so a changed main.qml never
# reloads in place. Restart the nested compositor and relaunch the clients.
reload() {
    (cd "$HERE" && make -s install >/dev/null)
    down >/dev/null
    up
    clients
}

clients() {
    local n; n=$(nwindows)
    for c in ${NEST_CLIENTS:-kcalc konsole kwrite}; do run "$c" >/dev/null; n=$((n + 1)); mapped "$n" || echo "fixtures: $c did not map in time" >&2; done
    sleep 1
    echo "clients: ${NEST_CLIENTS:-kcalc konsole kwrite}"
}

# A typical set of KDE apps opened on fixture files, so their content is the
# same on every run. Captions: KCalc, sample.txt — KWrite, Konsole,
# fixtures — Dolphin, wallpaper.png – Gwenview.
fixtures() {
    [ -f "$FIXTURES/wallpaper.png" ] || python3 "$FIXTURES/gen.py" >/dev/null
    rm -f "$FIXTURES"/.*.kate-swp "$FIXTURES"/*.swp 2>/dev/null
    # The fixture apps write their window state back into the nest's config
    # (the Dolphin sidebar, the Konsole size, the menus), so one run would
    # drift the next run's goldens. Every run starts from the apps' own
    # defaults.
    rm -f "$CONF"/dolphinrc "$CONF"/gwenviewrc "$CONF"/konsolerc "$CONF"/katevirc "$CONF"/kwriterc "$CONF"/kcalcrc
    # One at a time: each launch waits for its window before the next.
    local n; n=$(nwindows)
    run kcalc >/dev/null; mapped $((n + 1)) || echo "fixtures: kcalc did not map in time" >&2
    run kwrite "$FIXTURES/sample.txt" >/dev/null; mapped $((n + 2)) || echo "fixtures: kwrite did not map in time" >&2
    run konsole -e sh -c "cat '$FIXTURES/konsole.txt'; exec sleep 1d" >/dev/null; mapped $((n + 3)) || echo "fixtures: konsole did not map in time" >&2
    run dolphin "$FIXTURES" >/dev/null; mapped $((n + 4)) || echo "fixtures: dolphin did not map in time" >&2
    run gwenview "$FIXTURES/wallpaper.png" >/dev/null; mapped $((n + 5)) || echo "fixtures: gwenview did not map in time" >&2
    sleep 1
    echo "fixtures: kcalc kwrite konsole dolphin gwenview"
}

# The number of normal windows mapped; mapped N waits up to 10 s for N.
nwindows() { js 'let n = 0; for (const w of workspace.windowList()) if (w.normalWindow && !w.deleted) ++n; out(n)'; }
mapped() {
    for _ in $(seq 1 20); do
        [ "$(nwindows)" -ge "$1" ] 2>/dev/null && return 0
        sleep 0.5
    done
    return 1
}

# A KWin script run through org.kde.kwin.Scripting; its out() lines land in
# the nest log tagged with a fresh marker, which is echoed back.
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

# A probe client (dev/spike/preload/probe.qml): logs every press, release and
# key it receives with surface-local coordinates, as "PROBE Probe NAME ...".
probe() {
    alive || { echo "not up"; return 1; }
    local b; b=$(nestbus) || return 1
    ( export WAYLAND_DISPLAY=$SOCKET DBUS_SESSION_BUS_ADDRESS=$b $(nest_env client) QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1; unset DISPLAY
      "${LOW[@]}" qml6 "$HERE/dev/spike/preload/probe.qml" -- "$1" >> "$STATE/probe.log" 2>&1 & echo $! >> "$STATE/clients" )
}

# Inject input through KWin's fake-input protocol. Commands on stdin, or as
# arguments for a single command: move X Y | drag X1 Y1 X2 Y2 | wheel N |
# click | key NAME | sleep MS. Built by `make tools`.
input() {
    local bin=$HERE/build/tools/fakeinput
    [ -x "$bin" ] || { echo "fakeinput not built: make tools" >&2; return 1; }
    if [ $# -gt 0 ]; then
        WAYLAND_DISPLAY=$SOCKET "$bin" "$@"
    else
        WAYLAND_DISPLAY=$SOCKET "$bin"
    fi
}

# Only dispatch when executed, so the file can be sourced for its functions.
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0 2>/dev/null

case "${1:-}" in
    up) up ;;
    down) down ;;
    run) shift; run "$@" ;;
    cmd) cmd "$2" ;;
    toggle) toggle ;;
    shot) shot "${2:-}" ;;
    log) log "${2:-60}" ;;
    state) state ;;
    reload) reload ;;
    clients) clients ;;
    fixtures) fixtures ;;
    clean) clean ;;
    shell) shell ;;
    input) shift; input "$@" ;;
    js) js "$2" ;;
    probe) probe "$2" ;;
    bus) bus ;;
    *) sed -n '2,20p' "$0"; exit 1 ;;
esac
