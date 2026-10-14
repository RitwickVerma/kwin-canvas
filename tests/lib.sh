#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Test library for kwin-canvas. Sourced by tests/run.sh; scenarios are sourced
# after it and define run_scenario(). Reuses dev/nest.sh for everything that
# talks to the nested compositor.

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export NEST_NAME=${NEST_NAME:-test}
# Offscreen: a nest that is a window on the live desktop slows to a crawl when
# that window is covered, and every timing in the scenarios goes with it.
export NEST_VIRTUAL=${NEST_VIRTUAL:-1}
# shellcheck source=../dev/nest.sh
source "$HERE/dev/nest.sh"
# nest.sh sets -e for its own use; a test runner must survive failing checks.
set +e

OUT=${TEST_OUT:-$HERE/build/test}
GOLDEN_DIR=$HERE/tests/golden
UPDATE_GOLDEN=${UPDATE_GOLDEN:-0}
TOLERANCE=${GOLDEN_TOLERANCE:-0.03}
PASS=0; FAIL=0; SKIP=0
LAST_STATE=""
mkdir -p "$OUT"

# ---- driving the effect -----------------------------------------------------
# c "command": send a debug command, keep the state it printed. Read the state
# in this shell: sget reads $LAST_STATE, so `v=$(c state; sget visible)` in a
# subshell sees the parent's stale value, not the one just printed.
c() {
    LAST_STATE=$(cmd "$1")
}

# setcfg KEY VALUE: write an effect config key and reconfigure the effect, the
# way the settings page does (the harness's reconfigure is what re-reads the
# file, so a scenario can flip one knob without restarting the nest). The `--`
# is kwriteconfig6's end of options: a value that starts with a dash is a value,
# not a flag it should complain about.
setcfg() {
    kwriteconfig6 --file "$CONF/kwinrc" --group Effect-kwin-canvas --key "$1" -- "$2"
    c state >/dev/null
}

# kwinjs CODE [SETTLE]: run a KWin script in the nest, as a user's script or a
# tiler would act on a window (maximize, tile), and give it SETTLE seconds
# (0.8). The script finds windows by caption: FIND_KWRITE sets w to KWrite's.
FIND_KWRITE='var w = null; workspace.stackingOrder.forEach(function (x) { if (String(x.caption).indexOf("KWrite") >= 0) w = x; });'
kwinjs() {
    local f id; f="$OUT/kwinjs.js"
    printf '%s\n' "$1" > "$f"
    id=$(nq org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$f" kwinjs | tail -1)
    nq org.kde.KWin /Scripting/Script"$id" org.kde.kwin.Script.run >/dev/null
    sleep "${2:-0.8}"
    nq org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript kwinjs >/dev/null
    rm -f "$f"
}

# sget zoom|viewx|viewy|visible|activity|entries|popups|nactivities  -> value from the last state line
sget() {
    local line; line=$(head -1 <<<"$LAST_STATE")
    case $1 in
        zoom)    sed -n 's/.*zoom=\([0-9.]*\).*/\1/p' <<<"$line" ;;
        viewx)   sed -n 's/.*view=(\([-0-9.]*\),.*/\1/p' <<<"$line" ;;
        viewy)   sed -n 's/.*view=([-0-9.]*,\([-0-9.]*\)).*/\1/p' <<<"$line" ;;
        visible) sed -n 's/.*visible=\([a-z]*\).*/\1/p' <<<"$line" ;;
        activity) sed -n 's/.*activity=\(.*\) entries=.*/\1/p' <<<"$line" ;;
        entries) sed -n 's/.*entries=\([0-9]*\).*/\1/p' <<<"$line" ;;
        popups)  sed -n 's/.* popups=\([0-9]*\).*/\1/p' <<<"$line" ;;
        menus)   sed -n 's/.* menus=\([0-9]*\).*/\1/p' <<<"$line" ;;
        nav)     sed -n 's/.* nav=\([a-z-]*\).*/\1/p' <<<"$line" ;;
        screens)  sed -n 's/.* screens=\([0-9]*\).*/\1/p' <<<"$line" ;;
        backdrop) sed -n 's/.* backdrop=\([0-9]*\).*/\1/p' <<<"$line" ;;
        cam)      sed -n 's/.* cam=\([a-z-]*\).*/\1/p' <<<"$line" ;;
        clusters) sed -n 's/.* clusters=\([0-9]*\).*/\1/p' <<<"$line" ;;
        cluster)  sed -n 's/.* cluster=#\([0-9]*\).*/\1/p' <<<"$line" ;;
        draglag)  sed -n 's/.* draglag=\([0-9]*\).*/\1/p' <<<"$line" ;;
        lean)     sed -n 's/.* lean=\([-0-9.]*\).*/\1/p' <<<"$line" ;;
        seam)     sed -n 's/.* seam=\([0-9]*\).*/\1/p' <<<"$line" ;;
        moves)    sed -n 's/.* moves=\([0-9]*\).*/\1/p' <<<"$line" ;;
        dragraw)  sed -n 's/.* dragraw=\([0-9]*\).*/\1/p' <<<"$line" ;;
        undo)     sed -n 's/.* undo=\([0-9]*\).*/\1/p' <<<"$line" ;;
        bookmarks) sed -n 's/.* bookmarks=\([0-9]*\).*/\1/p' <<<"$line" ;;
        deskwin)  sed -n 's/.* deskwin=\([0-9]*\).*/\1/p' <<<"$line" ;;
        map)      sed -n 's/.* map=\([a-z-]*\).*/\1/p' <<<"$line" ;;
        ql)       sed -n 's/.* ql=\([0-9]*\).*/\1/p' <<<"$line" ;;
        cpu)      sed -n 's/.* cpu=\([0-9]*\).*/\1/p' <<<"$line" ;;
        gpu)      sed -n 's/.* gpu=\(-\?[0-9]*\).*/\1/p' <<<"$line" ;;
        mem)      sed -n 's/.* mem=\([0-9]*\).*/\1/p' <<<"$line" ;;
        active)   sed -n 's/.* active=\(.*\)$/\1/p' <<<"$line" ;;
        nactivities) grep -c '^  {' <<<"$LAST_STATE" ;;
    esac
}

# screenrect INDEX -> "X Y W H" of an output, from the state's screen lines.
screenrect() {
    awk -v i="$1" '$1 == "screen[" i "]" { split($3, a, /[x+]/); printf "%d %d %d %d", a[3], a[4], a[1], a[2] }' <<<"$LAST_STATE"
}

# screenname INDEX -> that output's name, as KWin reports it (the name a hidden
# frame is recorded under).
screenname() {
    awk -v i="$1" '$1 == "screen[" i "]" { print $2 }' <<<"$LAST_STATE"
}

# eget CAPTION_SUBSTR x|y|w|h|fx|fy|activity|index  -> field of the matching entry
eget() {
    local line; line=$(grep -a "^  \[[0-9]*\] .*$1" <<<"$LAST_STATE" | head -1)
    [ -n "$line" ] || { echo ""; return; }
    case $2 in
        index)   sed -n 's/^  \[\([0-9]*\)\].*/\1/p' <<<"$line" ;;
        x)       sed -n 's/.*canvas=(\([-0-9.]*\),.*/\1/p' <<<"$line" ;;
        y)       sed -n 's/.*canvas=([-0-9.]*,\([-0-9.]*\) .*/\1/p' <<<"$line" ;;
        w)       sed -n 's/.*canvas=([-0-9.]*,[-0-9.]* \([0-9.]*\)x.*/\1/p' <<<"$line" ;;
        h)       sed -n 's/.*canvas=([-0-9.]*,[-0-9.]* [0-9.]*x\([0-9.]*\)).*/\1/p' <<<"$line" ;;
        fx)      sed -n 's/.*frame=(\([-0-9.]*\),.*/\1/p' <<<"$line" ;;
        fy)      sed -n 's/.*frame=([-0-9.]*,\([-0-9.]*\)).*/\1/p' <<<"$line" ;;
        z)       sed -n 's/.* z=\([0-9]*\).*/\1/p' <<<"$line" ;;
        activity) sed -n 's/.*activity=\(.*\)$/\1/p' <<<"$line" ;;
    esac
}

# tget INDEX x|y|name|hidden  -> an activity target from the last state block
tget() {
    local line; line=$(grep -a "^  {$1}" <<<"$LAST_STATE" | head -1)
    case $2 in
        x) sed -n 's/.*target=(\([-0-9.]*\),.*/\1/p' <<<"$line" ;;
        y) sed -n 's/.*target=([-0-9.]*,\([-0-9.]*\)).*/\1/p' <<<"$line" ;;
        name) sed -n 's/^  {[0-9]*} \(.*\) target=.*/\1/p' <<<"$line" ;;
        hidden) sed -n 's/.*hidden=\(.*\)$/\1/p' <<<"$line" ;;
    esac
}

# ---- assertions -------------------------------------------------------------
ok()   { PASS=$((PASS + 1)); echo "    ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "    FAIL $1"; }
skip() { SKIP=$((SKIP + 1)); echo "    skip $1"; }

assert_eq() {   # name actual expected
    if [ "$2" = "$3" ]; then ok "$1 = $3"; else fail "$1: expected '$3', got '$2'"; fi
}
assert_near() { # name actual expected [tolerance]
    local tol=${4:-1}
    if [ -z "$2" ]; then fail "$1: no value"; return; fi
    if awk -v a="$2" -v e="$3" -v t="$tol" 'BEGIN{d=a-e; if (d<0) d=-d; exit !(d<=t)}'; then
        ok "$1 = $2 (~$3)"
    else
        fail "$1: expected ~$3 (±$tol), got $2"
    fi
}
assert_true() { # name shell-test-args...
    local name=$1; shift
    if test "$@"; then ok "$name"; else fail "$name"; fi
}

# ---- screenshots ------------------------------------------------------------
# snap NAME: screenshot the nest; with UPDATE_GOLDEN=1 store it as the golden,
# otherwise compare against the golden (RMSE, normalized) within TOLERANCE.
snap() {
    local name=$1 file=$OUT/$1.png golden=$GOLDEN_DIR/$1.png
    sleep "${SNAP_SETTLE:-0.4}"
    shot "$file" >/dev/null
    [ -s "$file" ] || { fail "snap $name: screenshot failed"; return; }
    if [ "$UPDATE_GOLDEN" = 1 ]; then
        mkdir -p "$GOLDEN_DIR"; cp "$file" "$golden" || { fail "snap $name: cannot write $golden"; return; }; ok "golden $name updated"; return
    fi
    [ -f "$golden" ] || { skip "snap $name: no golden (make golden)"; return; }
    local metric
    # compare exits 1 whenever the images differ at all; the number is what matters.
    metric=$( { magick compare -metric RMSE "$golden" "$file" "$OUT/$name.diff.png" 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p')
    if [ -z "$metric" ]; then fail "snap $name: compare failed"; return; fi
    if awk -v m="$metric" -v t="$TOLERANCE" 'BEGIN{exit !(m<=t)}'; then
        ok "snap $name (rmse $metric)"; rm -f "$OUT/$name.diff.png"
    else
        fail "snap $name: rmse $metric > $TOLERANCE, diff at $OUT/$name.diff.png"
    fi
}

# assert_same NAME A B [MAX]: the two shots taken by snap differ by at most MAX
# (0.003) of normalized RMSE - for a setting that must change nothing on screen.
assert_same() {
    local name=$1 a=$OUT/$2.png b=$OUT/$3.png max=${4:-0.003}
    if [ ! -s "$a" ] || [ ! -s "$b" ]; then fail "$name: a shot is missing"; return; fi
    local metric
    metric=$( { magick compare -metric RMSE "$a" "$b" "$OUT/$name.diff.png" 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p')
    if [ -z "$metric" ]; then fail "$name: compare failed"; return; fi
    if awk -v m="$metric" -v t="$max" 'BEGIN{exit !(m <= t)}'; then
        ok "$name (rmse $metric)"; rm -f "$OUT/$name.diff.png"
    else
        fail "$name: rmse $metric > $max, the two shots differ"
    fi
}

# assert_differs NAME A B [MIN]: the two shots taken by snap differ by at least
# MIN (0.01) of normalized RMSE - for what a setting has to change on screen,
# where a golden would only pin one of the two.
assert_differs() {
    local name=$1 a=$OUT/$2.png b=$OUT/$3.png min=${4:-0.01}
    if [ ! -s "$a" ] || [ ! -s "$b" ]; then fail "$name: a shot is missing"; return; fi
    local metric
    metric=$( { magick compare -metric RMSE "$a" "$b" "$OUT/$name.diff.png" 2>&1 || true; } | sed -n 's/.*(\([0-9.e-]*\)).*/\1/p')
    if [ -z "$metric" ]; then fail "$name: compare failed"; return; fi
    if awk -v m="$metric" -v t="$min" 'BEGIN{exit !(m >= t)}'; then
        ok "$name (rmse $metric)"; rm -f "$OUT/$name.diff.png"
    else
        fail "$name: rmse $metric < $min, the two shots are the same"
    fi
}

# Open and put the camera at 1:1 on the current activity's frames, whatever OpenZoom is.
open_1to1() { c open; c home; c state >/dev/null; sleep 0.3; }
# The trailing c state is the drain: the debug channel replays through the
# config watcher, whose delivery can lag under load - the last command must
# be a harmless state read, so a late replay can never fire a stale "home"
# into the middle of a hold (the 103 class).

# ---- screen borders ---------------------------------------------------------
# Which borders the effect reserves, the key the Screen Edges settings page
# writes. The effect only re-reads it on a reconfigure, so a reload through c
# is what makes a new list take effect: the Instantiator then builds one
# ScreenEdgeHandler per number.
set_borders() {
    setcfg BorderActivate "$1"
}

# Push the pointer into border N of the screen rect X Y W H the way a hand
# does, and the way KWin wants it: the first event lands on the border's own
# pixel and the second one, ElectricBorderDelay (75 ms) later, lands on it
# again - which the outward move does, because KWin warps the pointer
# ElectricBorderPushbackPixels (1) inward after the first event, so the
# relative push clamps back onto the pixel. The window between the two events
# is that delay to ElectricBorderCooldown (350 ms): later than that and KWin
# takes the event for the start of a new attempt, which is why a smooth glide
# that stops on the pixel never fires (it leaves one event there), while a
# mouse that keeps pressing does. Border numbers are ElectricBorder: 0 top,
# clockwise, 7 top left, the same order as ScreenEdgeHandler.Edge.
#
# The rect matters on a multi-output desktop: KWin reserves an edge only on the
# outer sides of the arrangement, but puts the four corner zones on *every*
# screen (ElectricBorderAllScreenCorner), so a corner can be pushed on any
# output and an edge only on the side that ends the desktop.
push_border_on() {
    local b=$1 x0=$2 y0=$3 w=$4 h=$5
    local x y dx dy
    case $b in
        0) x=$((x0 + w / 2)); y=$y0;             dx=0;   dy=-20 ;;
        1) x=$((x0 + w - 1)); y=$y0;             dx=20;  dy=-20 ;;
        2) x=$((x0 + w - 1)); y=$((y0 + h / 2)); dx=20;  dy=0 ;;
        3) x=$((x0 + w - 1)); y=$((y0 + h - 1)); dx=20;  dy=20 ;;
        4) x=$((x0 + w / 2)); y=$((y0 + h - 1)); dx=0;   dy=20 ;;
        5) x=$x0;             y=$((y0 + h - 1)); dx=-20; dy=20 ;;
        6) x=$x0;             y=$((y0 + h / 2)); dx=-20; dy=0 ;;
        7) x=$x0;             y=$y0;             dx=-20; dy=-20 ;;
        *) echo "no such border: $b" >&2; return 1 ;;
    esac
    # A corner's pixel is its own. An edge is TouchTarget (8 px) wide and stops
    # cornerOffset (40 px) short of each corner, so the midpoints are safely on
    # the strip whatever the corner zones do.
    input move "$x" "$y"
    sleep 0.15
    input rel "$dx" "$dy"
}
push_border() { push_border_on "$1" 0 0 "$WIDTH" "$HEIGHT"; }

# A pointer placed on a border pixel and then taken away, the way a KVM switch
# (Deskflow, a network KVM, a remote session) drops a pointer onto this machine
# and the user then moves it: KWin wants two motion events on the pixel inside
# ElectricBorderDelay..Cooldown, and one is not an attempt. Returns after the
# move away, so a scenario can read the state.
kvm_drop_on_border() {
    local b=$1 x y
    case $b in
        0) x=$((WIDTH / 2)); y=0 ;;
        7) x=0; y=0 ;;
        6) x=0; y=$((HEIGHT / 2)) ;;
        4) x=$((WIDTH / 2)); y=$((HEIGHT - 1)) ;;
    esac
    input move "$x" "$y"
    sleep 0.5
    input move $((WIDTH / 2)) $((HEIGHT / 2))
}

# ---- fixture layout ---------------------------------------------------------
# A fixed arrangement of the fixture windows in canvas units. Everything
# assumes the current activity's target is (0,0), which resetview guarantees.
declare -A LAYOUT=(
    [KCalc]="100 120 480 420"
    [sample.txt]="640 120 700 520"
    [Konsole]="100 600 620 420"
    [Dolphin]="780 680 700 360"
    [Gwenview]="1400 120 460 420"
)
arrange() {
    c cancel >/dev/null 2>&1 || true
    c resetview
    open_1to1
    for cap in "${!LAYOUT[@]}"; do c "placeby $cap ${LAYOUT[$cap]}"; done
    sleep 0.6
    c commit
    # Deterministic screenshots: a fixed focus chain and stacking order (the
    # fixtures' launch order, KCalc on top), so the active window (shadow,
    # decoration) is always KCalc, the window KWin falls back to when KCalc
    # leaves the activity is always Gwenview, and overlaps stack the same,
    # whatever order the fixtures came up in; and the pointer parked where
    # it hovers nothing.
    for cap in sample.txt Konsole Dolphin Gwenview KCalc; do c "activate $cap"; done
    have_input && input move 1915 1075
    sleep 0.3
}

have_input() { [ -x "$HERE/build/tools/fakeinput" ]; }
