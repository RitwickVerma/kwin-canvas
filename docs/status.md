# Where the work stands

The state file for whoever picks this up next, a person or an agent. It is the one
document here that is allowed to go stale: update it when you stop, rewrite what is
no longer true rather than appending, and keep it short. The model is in
[architecture.md](architecture.md), the harness in [testing.md](testing.md), and
what a user sees in [release-notes.md](release-notes.md).

## The fork

`main` is a fork of [`aaronsb/kwin-canvas`](https://github.com/aaronsb/kwin-canvas)
(remote `upstream`, GPL-2.0-or-later) that adds four scenarios, the recovery notes,
the pass-through work, and this repository's hygiene: the conventions files,
per-file licensing, CI and `make lint`.

- `origin` is `git@gitlab.com:ritwick7/kwin-canvas.git`, and the fork is pushed
  there (`main` ahead of `upstream/main` by the fork's own commits).
- Upstream's tags `v0.3.0`, `v0.3.1` and `v0.4.0` are fetched locally and have not
  been pushed to the fork.
- `make release`, `make aur` and `make aur-passthrough` publish to upstream's GitHub
  releases and AUR packages, so they are not ours to run.
- The fork's own work is `git log --oneline upstream/main..HEAD`: the eight commits
  in the table below — 50 files, +2602/−128 up to `4cbc21a` — plus this file's own
  commit.

## The fork's commits

| Commit | What it is |
|---|---|
| `74289ed` | Both input routes hand the plane's navigate buttons to the canvas |
| `a2c986f` | Portals, smart placement, a carried window, honest clocks |
| `5a48952` | Scenarios: `81-nav-hold`, `91-two-outputs`, `93-backdrop`, `94-physics` |
| `4f083f9` | `.editorconfig`, `.gitattributes`, `.gitignore` |
| `8f3e421` | `REUSE.toml` and per-file attribution |
| `cfa5af7` | `.gitlab-ci.yml`: what a container with no compositor can check |
| `f8bd927` | `make lint`: the CI checks, runnable here |
| `4cbc21a` | The fork's new files match the tree (no shebang on a sourced scenario) |

This file arrived in one commit on top of those, together with `AGENTS.md` and
`CLAUDE.md`: the way in for whoever works here next.

## Verified, and how

On this session's tree, in a nested KWin 6.7.5 with the pass-through plugin
built and loaded (the live-session half stays untested, below):

- `make lint-qml`, `make lint-shell` and `make lint-deadcode` — exit 0 (the
  census in `tools/deadcode.sh` keeps the tree free of declarations nobody
  references; it runs in CI too). `lint-reuse`, `lint-shell` with
  shellcheck and `lint-python` with vulture all run here now too (the
  tools were installed in the session that added them).
- `make unit` — 50 pure-logic assertions in node, in the CI's check stage
  as well as locally (the seam band joined the tested half).
- The scenarios, by the batches that pin them (the overlay's cluster gate,
  the hold in the open overworld, the map's drag-eater and the verbose
  trace are the newest work): `make test ARGS=112-overlay` — 20/0,
  `107` — 6/0, `85` — 17/0, `87` and `88` — 2/0 each (`89` skips, two
  outputs), `103` — 24/0, `109` — 9/0, `110` — 5/0, `7[01]` — 18/0,
  `10[013479]` — 87/0, `8[0-9]` — 62/2 (the panel and the two-output
  skips), `10[49]` — 29/0, `70` and `71` with the poll-tolerant slide.
- The full suite is not green on this machine right now: `make test`
  failed with a different set of scenarios on each of three runs (40
  failures, then a handful, then two scenarios), each of which passes
  alone and in its batch. This is the documented GPU-pressure flake
  (docs/testing.md → Things that cost time), amplified by leaked VRAM
  from crashed nests - the next session should reboot before taking a
  full-suite result as evidence, or judge by the named batches above.
- The goldens are recorded against the pinned nest (Breeze Dark, the dark
  icon theme, the Breeze widget style and decoration; the fixture apps'
  own configs are reset before each run), so they mean the same pixels on
  every machine and every day. The fly's fade moves no golden: the quiet
  slide wears no chrome and the scenes snap before and after the fade.
- `make fixtures` — regenerates the committed fixtures byte for byte.

## What cannot be checked on this machine

- **The plane-input shim** (`make test-shim`, `tests/shim/*`):
  `dev/spike/preload/shim.cpp` expects libkwin build-id `b4a7f7ab…` (kwin 6.7.5-1)
  and the installed libkwin is `d8d86b3c…`, so the shim scenarios skip before
  compiling. The pass-through plugin, the shim's substitute, does build here
  now (the dependencies were installed) and `85-passthrough` runs for real.
- **The live-session half**: the `evaluateScript` handoff, and the wallpaper inside
  a real plasmashell, have been rendered in isolation only.

## Decisions taken, and the ones still open

Taken, with the reasoning in `AGENTS.md` → *Deliberate, not accidental*: no
`.clang-format`; docs and images stay `GPL-2.0-or-later`; no test job in CI (the
linters run there, shellcheck at error severity included); `qmllint` by absolute
path; the scenarios stay local because they need a nested KWin.

Open:

- Whether the fork publishes anything of its own (tags, GitLab releases) or upstream
  stays the only publisher.
- Whether a runner can host a nested KWin — that is what a CI test job would need.
- Whether docs and images should move to `CC-BY-SA-4.0`, KDE's own choice for them.

## Next candidates

`docs/architecture.md` → `Next` holds the remaining ideas (snap zoom to 1 on
the plain commit paths, drawing limits, auto-pan while dragging to a screen
edge at 1:1, bookmarks and a minimap, persisting `view` on commit). Beyond
those, from this side of the fork:

- Two-output goldens exist only for `91-two-outputs`; another arrangement would
  widen `make test-two-outputs`.
- The haze is measured at one zoom and one blur; how the blur reads at
  extreme zooms, and the per-view fade under the frames on two outputs, is
  only partly pinned.
- The one skip left in `make test` is honest: `91-two-outputs` needs a
  two-output nest, which `make test-two-outputs` gives it. `make test-shim`
  would be a second runner on a machine whose libkwin matches the shim's
  pinned build-id - the biggest gap left in the suite.

## Sessions

### 2026-10-13 — the tilt fits a scattered desk, and the ladder asks twice

The user's verdict on the first 3D look: "no threads, translusent
windows, no tilt, no 3d, no grid, half ass job." The misdiagnosis first
(the ladder degrading under a busy GPU - the user: "I have not been
playing any game since boot") - the live state (ql=0, gpu 46) proved
the ladder innocent. The real cause: the tuning was built for a tight
desk and the user's desk is scattered (a saved view at -43048 canvas
px, windows thousands of px apart) - the distance fog washed every far
window translucent, the cluster's cohesion fade dissolved the threads
to nothing, and the pitch was too timid to read. Fixes: the fog scoped
to the world beyond the viewport's edge (reach = vs.max/max(zoom,
0.25), cap 0.35), the lit thread's floor (never below 0.3), the pitch
0.30 → 0.42 + the lift 90 + the grid boost 1.8. Also found: the
camera channel was broken for the user's stale system plugin - the
6-arg setCamera had become a contract mismatch, so the camera channel
is back to 5 args and the tilt travels its own setTilt channel; and
the ladder now needs two hot samples before stepping down and toasts
when it does, so a launch spike cannot flash the canvas bare. The
scenario batch re-verified green (the whole list), the depth goldens
re-recorded for the stronger picture, and the one reinstall the user
owes: the system plugin is 3+ hours stale - `sudo make
plugin-install-system` + re-login once (the camera works with the old
plugin again; only the tilt-aware hover needs the fresh one).

### 2026-10-13 — the tilt's floor reads: the haze lifts, the grid brightens

The user's first look at the 3D: "bro the whole backgroundd is blur. no
grid no nothing. how am I supposed to see 3d with just windows zoomed
out???" The tilt existed but had no floor to express itself on - the
backdrop haze (the designed blur 48 + dim 0.45) and the faint grid
swallowed the pitch. Three changes: the pitch deepens (0.21 → 0.30, 17°
max); the floor reads it (the blur radius and the dim scale down with
the zoom - the floor sharpens and lifts as the table comes out - and
the ground's grid brightens with the skin, so the converging lines
carry the perspective); and the backdrop stays flat by necessity - a
perspective transform on the blur layer made the scene graph drop the
whole layer (measured: the dim A/B collapsed to rmse 1.5e-05; flat it
is 16.8%), which is documented in the code and in the architecture.
The seven depth goldens were re-recorded for the stronger picture, the
whole batch stayed green (lint 147/147, unit 85/0).

### 2026-10-12 — the plane tilts into depth, and the input follows it through

The user asked "can we make everything 3D?" - and the plane now pitches
into perspective as it zooms out. The tilt pivots at the screen's centre
(the first cut drifted the whole desk as it tilted - the matrix rotated
around the origin, not the centre; the pivot-correct chain keeps the
centre fixed and scales the projection so the centre renders at its flat
size), the windows lift by their depth and fog with their distance, and
the camera's layers (ground, frames, threads, chips, badge, tags) ride
the same matrix.

The hard part was the input. Qt's picking and drag through a
perspective matrix is broken - a window with the matrix on it lost its
whole drag (80-input measured zero movement) - so the windows stay flat
items re-sited by projecting their centres through the matrix (a
Scale/Translate affine, which the drag machinery handles exactly, times
the tilt-aware compensation for the perspective's gradient). The
pass-through plugin's toCanvas gains the closed-form inverse of the
pitch, so the hover and the pointer handoff land on the window under the
visual pointer, not the flat-math one. The 1:1 seam never tilts
(pixel-identical A/B), the ladder flattens the plane at the minimal
rung, and Depth3D is the hidden knob.

Measured: the tilt A/B at zoom 0.5 moves 12.6% of the picture; the drag
through the tilt lands within 2% of the flat prediction (the affine's
constant-k approximation); 126-depth3d 7/0 pins the seam, the tilt, the
drag and the ladder-flatten; 80-input 9/0 pins the drag and the
pass-through math. Two follow-up fixes: the enter-fade re-fired on
every re-sort (the activation's re-raise re-assigns the positional
delegates - the born check now also demands the entry is younger than
500 ms), and the fog gained the depth3d gate so the flat picture is
bit-for-bit the old one when the tilt is off.

### 2026-10-11 — the switcher reads its release from the seat

The user reported "switcher release doesnt always work". The release
depended on the scene receiving the chord's key-ups, which KWin's
global-shortcut consumption delivers inconsistently - and the Tab-keyup
arm also armed mid-hold (a re-tap's Tab key-up with the modifiers still
held). The release now reads the seat itself: the pass-through plugin
exposes `modifiers()` (KWin::InputRedirection's live keyboard mask),
and while a chord-held switcher is up the effect polls it at 80 ms - the
moment the chord's modifier clears, `chordRelease()` runs the
picked-scan, steps once when nothing was picked, and arms the settle
beat. The scene's bare modifier keyup remains the fast path; the
Tab-keyup arm is gone, so a re-tap mid-hold can never fire the release.
The plugin needs `sudo make plugin-install-system` for the channel.

### 2026-10-11 — the switcher wears its pick, and the demo walks the tour again

The user asked how to make it even more mindblowing; the picks were
the switcher's preview card and a fresh demo. The card sits under the
toolbar while the switcher is up - the chosen window's name, its live
picture, and its cluster line, riding the z-rise (scenario 125 pins it
with region probes). The demo capture exposed a real bug along the
way: `switcherToggle` had a leftover `visible && !quiet` reset branch,
so the chord on the open overworld did nothing - the switcher only
opened from the closed location. The branch is gone (a hold still
stands the chord down); the chain test proves the fit now runs from
the open canvas too (0.35 -> 0.4314).

The demo's capture was rebuilt around the two harness traps that froze
the earlier takes: a fixed-rate shot loop races spectacle's latency,
so each step now gets its own shot burst, and every input step is a
single fakeinput stream - separate invocations are separate devices,
each pressing at its own default corner. The verified tour: the
desktop, the step-out, the double-click fly, the web, the switcher's
snap with its card, the hold's wheel descent, the landing.

### 2026-10-10 — Alt+Tab scopes to the cluster, and the physics live at real time

The user's idea for the two switcher chords: one scope each. Meta+Tab
keeps sweeping the whole plane; Alt+Tab now opens the switcher fitted
to the cluster the eye is on (capped at the canvas's 1:1, a short hop
among neighbours) and steps only among that cluster's windows
(switcherMembers() walks the cluster's live entries; a cluster of one
falls back to the world fit). clusterRect() extracts the bounds the
chip flight already computed, and graspClusterTo rides it too. The
switcherCluster flag is set by the chord that opened the switcher and
cleared in endSwitcher(); scenario 124 proves the scoped fit (1:1 vs
the world's under-0.4), the scoped step, the enter, and the unchanged
world switcher.

### 2026-10-10 — the physics live at real time, and windows enter gently

The user asked for "more fluidity (overall project think deep)". The
camera spring, the float physics and the edge pan all stepped on fixed
16 ms timers - a 62.5 Hz grid - with a hard-coded dt; on a fast display
every flight rendered in 16 ms steps. The single frame timer now fires
every 8 ms and integrates the real elapsed time, clamped to 16.7 ms for
the Euler spring's stability (a busy frame slows the motion rather than
lengthening its steps, the old property kept), and the float bob's phase
advances with real time too. Windows that open into the overworld fade
and scale in from a 0.94 origin over 200 ms instead of popping; the
open's populate and the quiet seam carry no birth stamp, so the
pixel-exact seams are untouched.

The trap that ate the morning: the spawn-fade's `opacity` duplicate hit
"Property value set multiple times" - the delegate already wore
`effect.thumbOpacity` (the open's fade-in) - and the effect failed to
load, so the runner's load-wait hung forever and the batch timed out at
the first scenario. The fix merges both into one binding:
`opacity: effect.thumbOpacity * thumb.enterFade`. Also reverted: a
self-chaining Qt.callLater frame tick, which ran unthrottled on the
virtual-output nest and pegged a core.

### 2026-10-09 — the switcher stops machine-gunning, and the ladder's memory channel reads

The user reported "the switcher is broken at a very basic level": a
tap of Alt+Tab opened the canvas and closed it instantly with no
result, and holding the chord cycled the windows at light speed. Both
were the chord's mechanics: KWin refires the shortcut on every key
repeat of the held Tab, so the switcher's repeat branch cycled per
repeat, and a tap's release hit the release-enter with nothing picked,
which applied the enter to the window already focused - a no-op close.
The fix: one gated cycle (`switcherCycle`, a 150 ms window - real
re-taps pass, auto-repeats and double deliveries are swallowed), the
scene's Tab branches route through the gate while the switcher is up,
and the release-enter cycles to the next window when nothing is picked
- a tap is now the tabbox's plain Alt+Tab, a hold steps per deliberate
re-tap, the release enters the pick.

The same week, the user asked for a snappier switcher and suggested the
windows come up in z with it: the switcher's fit now rides a brisk
flight (rate 3), the pile's depth rises on its own 180 ms ramp the
moment it opens (`switcherRise`), and the picked window ranks at the
top of the pile while the switcher is up, so the cycle reads in the
shadows and the size.

The same week, two ladder bugs closed: the memory channel had never
read anything (/proc/meminfo reports a zero size, so QFile::atEnd() was
true before the first read - the loop now runs on readLine() alone),
and the quality channel now clamps every reading to [0,100] so a stale
plugin's kilobyte-scale answer can never force the canvas bare. The
toolbar's glass followed the machine's mutable colour scheme and
flipped between sessions; it now wears fixed house colours. And the
minimap's camera rectangle clamps to the lens - panned past the
world's edge it hugs the chip's border.

### 2026-10-08 — the desktops leave the plane, the ladder reads the memory, tidy stays

Three takes on virtual desktops - shadow tiles, live zones, a slide
transition - all felt bolted-on, and the user called it: "nah this does
not feel correct. maybe we need to go back to single virtual desktop.
this is not it man." The five desktop commits are reverted. The model
is what it always was: virtual desktops stay ordinary KWin desktops,
and the plane replaces them - one desktop, activities as the frames,
clusters as the groups, flying as the switch. The ladder's memory
channel (the used share as a third input, MemReduced/Minimal/Bare) and
the tidy action (TidyGap, the Arrange menu) were independent of the
desktops and stayed.

### 2026-10-04 — the dock and the applets own their pixels

The user clicked a dock icon and the window under it got focused and the
canvas flew. Three steal paths, all fixed: the closed-canvas
click-candidate (the plugin's `windowUnder` scanned past the dock),
the open-overworld plugin path (`windowAt` found the window under the
dock and entered it), and the scene's handlers plus the hover-tick
under the dock. One flag now governs them: `publishChrome()` in the
plugin runs `chromeAt()` on every pointer event - top-down over the
stacking order, the first client at the point decides; a dock, popup,
special or unmanaged window is the chrome, a plain client is not - and
sets the effect's `chromeHover`, which gates the plugin's enter/grab
paths, the scene's every pointer handler and the hover-tick's pan. The
last bug found was the edge pan itself: with a pan button (or the hold)
down, resting the pointer on the dock kept scrolling the canvas under
it - the edge-pan timer now stands back over the chrome too.

The panel harness that made this testable: `make test-panel` seeds the
default Plasma layout in the nest (a bottom panel with a clock),
scenarios 86 and 117 poll `panels().length` through `evaluateScript`
(whose `print()` output comes back through the reply), and the shared
`clock_box` locates the panel strip in a screenshot. Two traps worth
keeping: in bash case patterns a QUOTED bracket segment is literal
(`*"PANELCOUNT:[1-9]"*` never matches), and a fresh fakeinput device's
first event lands at (0,0) - every stream must open with a `move`.

The measurement that found the last bug: the grasp click moved the view
+60.9 canvas per run; instrumenting the camera's silent writers showed
`edgePanStep -> panBy` every 16 ms at the dock (EdgePanSpeed defaults to
900, EdgePanMargin to 24). Verified: 117-dock 15/0, 86-panel-popup
3/0/1, 85 21/0, 87/88 2/0, 109 9/0, 110 5/0, 112 20/0, 103 24/0, 106
8/0, lint green, unit 77/0.

### 2026-10-04 — the canvas sheds its finery as the system loads up

The system feature demand: the canvas must never steal resources from
more important processes for eye candy. It now watches the machine's
real load (a `load()` D-Bus call into the pass-through plugin, reading
/proc/stat deltas plus the GPU's busy share via NVML, loaded on demand
with QLibrary so the plugin carries no link-time dependency on the
NVIDIA driver) and steps down a four-step ladder: reduced (the backdrop
blur, the unlit constellation and the lens's edge blur go), minimal
(the whole cluster web, the standing shadows, the z-depth and the float
bob go), then bare (the live window pictures become named rectangles).
The CPU and GPU channels race each other: whichever sees the worse
pressure sets the step. The climb back up waits two calm samples, so it
never flutters. The functional paths - panning, zooming, clicking, the
pass-through, the hover raise, the chips, the lens's content - never
degrade. The QualityMode knob holds a step, and the six Cpu/Gpu
thresholds are hidden knobs. The suite pins all six thresholds to 100 in
the nest seed so no golden depends on the host's load; scenario 116
drives the ladder's edges itself (12/0). The pure threshold logic is in
logic.js (`qualityFor`), unit-tested to 77/0.

### 2026-10-03 — the overlay is gone: the world is the map

The overlay card never earned its screen: it was a second picture of
what was already on the plane, wearing a blur the GPU paid for. It is
deleted - the veil, the card, the sheets, the chips-in-the-map, the
resolver and the hint strip in it, along with the grasp's own
pick/hover machinery. The zoomed-out world is the map now: the windows
shrink live into the map's sheets, a click on a window during the hold
flies it to 1:1 (the window delegate's tap gained the grasp branch)
and the release lands there; the cluster chips float on the plane at
their clusters (a camera-transform wrapper like the threads', tapping
one fits the cluster at 0.75); the hint strip sits on the world; the
switcher opens fitted to the whole plane and is TabBox-style: the
chord's repeat steps the selection, releasing the chord (or Enter)
steps into the chosen window, Esc steps out, and a second chord
(SwitcherAltShortcut, Alt+Tab by default) rides alongside Meta+Tab;
the minimap's corner chip steps clear of the toolbar; the corner lens
in the overworld stays. Rewriting the scenarios
taught two traps anew: the quiet grasp shows only its own activity's
windows (a click on a far activity's window is invisible - the
scenario clicks a current-activity window), and the QML disk cache
(~/.cache/kwin/qmlcache) had the nest running the pre-removal build
until it was cleared.

The same pass hardened the camera: the commit and the slide refuse a
non-finite camera and reset it, and a NaN zoom request keeps the
current zoom, so a diverged spring or a poisoned pan can never write
NaN/Inf window geometries into KWin. The plugin's window pointers were
audited clean (all QPointer, re-checked before use). A new stress
scenario (115-stress) hammers the camera with spring flights, pan
bursts and a mid-flight grasp to prove it stays finite and answering.

The same pass almost shipped a key-eating bug, caught by 102-keys
failing 6/11 while the old tree passed 17/0: the chips' structural fix
had left one brace mis-placed, so planeMap (and with it the Keys
handlers, the HUD and the hint strip) was nested inside the view
instead of beside it, and every key died before the scene. The
bisect-by-diff (worktree at 7df8f34 + the world-map hunks applied in
halves, 102 run after each) pinned it to the last hunks, and the
brace tracer showed planeMap swallowing the keyboard. The structure is
restored (planeMap closes right after its minimap tap; the Keys, the
HUD, the help and the hint strip are the view's children again).

### 2026-10-02 — the seams swap instantly, and the threads travel the stack

- **The fly's flash, chased to the ground.** Three fade-shaped fixes
  (window, view, scene) all flashed because KWin composites the canvas's
  framebuffer over black, not over the desktop - measured with the fade
  slowed to 3 s, every pixel ramps through black - and the black was the
  flash. The same measurement showed the quiet scene at 1:1 to be
  pixel-identical to the real desktop (Klassy has no active/inactive
  decoration delta), so the seams no longer fade at 1:1 at all: the quiet
  slide opens opaque, glides after the first paint warms the thumbnails,
  writes the geometries and closes the moment it arrives. A fade remains
  only where the picture genuinely jumps - a close from a zoomed-out
  overworld - and there it fades through black, the honest mask for that
  jump. The flight's spring still starts as a gentle acceleration, and
  the chrome stays up through a flight.
- **The threads' depth.** A thread was flat: one z per pair, its
  endpoints' midpoint, so it ignored every window it crossed in the
  middle. Now each thread travels the depth between its two windows
  (the z at a point is the mix of the endpoints'), cut at every window
  crossing so each stretch renders at its own z: over the lower, under
  the higher, ducking under whatever covers the middle. `113-thread-duck`
  proves the duck in pixels; writing it also showed the nest's Konsole
  to be translucent (the wallpaper bleeds through it in the goldens), so
  the cover in the scenario is Dolphin. The debug channel gained
  `threads`, which dumps every stretch with its z.
- **One map everywhere.** The overlay now wears what the minimap wears -
  the desks and a chip per cluster - and the map's taps are judged once
  by a single resolver instead of per-item handlers: a chip inside a
  window's sheet wins its tap (the first cut fired both, and the sheet's
  fly overrode the chip's), and a chip flies the camera to fit its
  cluster at 0.75 - the cap that keeps the overlay up - with the release
  landing the location centred on the cluster. The chips and the desks
  ride the map's morph: their reads of the map's scale inside mx()/my()
  never registered as binding dependencies and froze them at the size
  the map wore when they were laid out - the house trap, fixed with
  explicit reads of the map's size. The overlay also teaches itself: a
  one-line hint (click to fly · drag to pan · wheel to zoom · release to
  land). `114-overlay-map` pins the chips, the desks, the resolver and
  the landing (10/0).

The full suite still is not green on this machine: the GPU-pressure
flake stands (docs/testing.md), and the named batches remain the
evidence until a reboot.

### 2026-10-02 — camera motion no longer re-weaves the threads

The lag report ("canvas animation only") pointed at the weave: the
threads' model deps read the camera, so every frame of every fly, zoom
and pan re-ran the full Liang-Barsky span clipping over every window
pair. The clipping now runs in the plane's own coordinates - the cut
parameters are invariant under a uniform translate and scale - so the
model re-evaluates only when the layout changes, and the delegate is a
camera-transform wrapper (x/y/scale per frame) with the strokes divided
by the zoom to keep their exact screen widths. Two always-on blur passes
were also wasting an FBO per frame: the overlay card's blur now switches
off once the map has materialized, and the camera rectangle's only on
the overlay. Measured in the play nest during continuous zoom flights:
~16-17% with the spring animating against ~5% at rest, and the weave no
longer runs per tick at all.

### 2026-10-02 — one skin, one hand, one map: the interface as a whole

The cohesion round, all four roadmap items at once:

- **One skin.** The chrome's reveal curve was keyhole-only (`quietReveal`
  gated on quiet && grasp). It is now `skinReveal`, one curve on every
  path: the zoom term (1-zoom)×4 plus a pan-away term measured from
  where the camera opened - the chord's overworld from its entry view,
  the grasp from the activity's target. Stepping out lands on the same
  calm desktop the location was, and the frames, tags, standing shadows,
  glow, badges and web come out as the camera leaves, whichever path
  opened the canvas. A transient slide still wears nothing. The depth
  pile is flat at 1:1 and grows with the skin. All fifteen chrome
  wiring points read the one curve.
- **The hand dot.** The toolbar wears a dot beside the activity swatches:
  filled when the pass-through has handed the pointer to a window, hollow
  while the canvas holds it. The effect polls the plugin's `state()` over
  the existing D-Bus channel (400 ms) and parses the hover/grab tokens -
  proven live in the nest (hover over Konsole → filled, off to the ground
  → hollow).
- **Bookmarks surfaced.** The help panel lists every saved spot with its
  name, so the digits are discoverable.
- **The glass card.** The overlay is a rounded card - 74% of the screen
  centred - on a lighter veil, instead of the full-bleed sheet. The map,
  the desks, the chips and the hint all live on the card, and the
  scenarios' click coordinates moved with it (107/112/114).

Goldens moved deliberately: `open-1to1` (the overworld at 1:1 is now the
calm desktop the identity scenario wanted), `input-dragged`, `resized`,
`three-activities`, `hidden-frame` and `two-output-corner` (accumulated
drift from the thread depth, the dot and the skin, verified small and
intended). Batches: 107 6/0, 112 20/0, 114 10/0, 71 12/0, 10 11/0, 30
14/0, 70 6/0, 103 24/0, 100 19/0, 85 21/0, 87 2/0, 88 2/0, 111 6/0, 106
8/0, 20 8/0, 90 28/0, 93 14/0, 98 5/0, 50 4/0, 60 12/0, 61 7/0, 80 9/0,
105 10/0, 102 17/0, 109 9/0, 110 5/0, 108 2/0, two-outputs 17/0 (94
flaked once in the batch, passes alone - the documented class).

### 2026-10-02 — the hold's map materializes with the keyhole

The user's report ("the overlay is broken. never shows up on time") was
measured to a real gate bug: the overlay required more than one cluster,
and the default arrange is one - so the overlay literally could not
appear on a one-cluster desk - plus the entrance was a hard 0.85 cut
followed by a 430 ms blur fade, which read as late. Now the gate opens
at 0.9 and the whole card (desks, sheets, chips, the veil) fades in
continuously between 0.9 and 0.7, so the map materializes as the keyhole
widens; the one-cluster gate is gone (the map is the plane's legend,
not a prize for scattered windows); the grasp's map takes clicks only
below 0.75, above which a tap falls through to the plane's own window
pick; the switcher keeps its 430 ms blur entrance. Measured in the play
nest: one cluster, map=overlay at 0.7 and 0.85, map=- at 0.95.
Batches: 112 20/0, 107 6/0, 114 10/0, 85 21/0, 87/88 2/0, 103 24/0,
111 6/0, 106 8/0; lint green; unit 68/0.

### 2026-10-02 — the skin retires across the flight

The step-in's skin fade was compressed into the spring's slow tail (the
(1-zoom)×4 curve spends its whole budget between 0.75 and 1:1, ~180 ms at
the live rate) - the threads blinked out at the end of the fly. The
retire is now measured against the flight's own progress: a rate-2
flight fades the skin evenly from its start zoom to the 1:1 arrival
(`skinFromZoom`, set in camGo, reset when the spring stops), a casual
wheel-in wears a straight 2×(1-zoom), and the reveal stays ×4 so a step
out still brings the skin in by 0.75. The unlit constellation now
dissolves between 0.45 and 0.5 instead of cutting at half zoom. The
first cut (a flat ×1 retire) would have stepped the skin down on the
flight's first frame - the progress-normalized curve was the fix that
did not move the flicker. The pixel pass found the nest's Konsole
interior near-white, which polluted the thread probes; the state
timeline and the curve math are the measurement. Batches: 11[0-9] 45/0,
10[0-9] 124/0, 9[3-4] 41/0, 98 5/0, 87 2/0 alone (the batch's hover
assert flaked - the documented class), 7[01] 18/0, 30 14/0, 20 8/0,
10-open 11/0.

### 2026-10-01 — the seam, the fly's fade, and the hover's real raise

Three live-session bugs, each fixed with a measure first:

- **The seam.** deskflow (running as this machine's server) parks the
  pointer on the screen border it hands the mouse over across; the hover
  poll read that parked pointer as a rest and glowed/paned the window
  under the seam. The outer few pixels of the desk are now a hover dead
  band (logic.js `seamPoint` + the plugin's `atSeam`), the bookkeeping
  runs through the grasp too - the first cut went stale during the quiet
  hold and handed the title-bar drags to the pan - and `109-seam` pins
  both sides.
- **The fly's flicker.** Measured in the nest: the quiet canvas at 1:1
  differs from the real desktop exactly over every inactive window (the
  thumbnails draw the active decoration; the active window matches pixel
  for pixel), so the fly's instant close flashed every inactive title
  bar at once. The quiet scene now fades in when the slide opens and out
  when it lands.
- **The hover's z.** A hover now raises the window in KWin's real
  stacking (the picture follows through the resync), so the overworld's
  order and the desktop's can never disagree and the raise survives the
  step back in - the picture-only re-stack from the earlier session is
  gone. `110-hover-raise` pins the raise, the sync and the survival.
- **The threads' z.** The web's per-thread z was inert (a child's z
  cannot lift it out of its parent), so every thread painted under every
  window. The threads are now one flat Repeater at the view level with
  the window z strict by stacking index (the hovered one at 2000), so
  the web weaves over the lower and under the higher and re-threads with
  the hover; `111-thread-z` proves the weave in pixels and the lift in
  state. `94-physics` now waits out the cancel's slow home flight, the
  flake that failed twice in a row.

The full suite is not green on this machine: three runs failed with
different sets (40, then a handful, then two scenarios), all passing
alone and in their batches - the GPU-pressure flake now written down in
docs/testing.md. The named batches are the evidence until a reboot.

### 2026-09-30 — the switcher, the scoped pass-through, and the public polish

The switcher: SwitcherShortcut opens the hold's map as a toggle - Tab
and Shift+Tab step the highlighted window, Enter enters it - the
window switcher the plane deserves. The pass-through is heavily scoped:
it engages on a rest (a 260 ms hover), the keys belong to the window
only while the pointer hovers one, it lets go after four idle seconds,
and the handover publishes itself so the canvas and the tests can see
whose the input is. Every fly is smart (the least movement, the most of
the desk in view) with a fresh destination, the web is tethered to the
windows' float and weaves over and under them, the map is one living
picture that morphs between the hold's sheets and the corner lens, the
camera's rectangle is draggable, and the float is KWin's keep-above.
The micro-feel: the click-pan responds after a beat (the double-click
still cancels it), the camera lands instead of crawling, the glow
fades. `make demo` drives the cinematic tour to docs/images/demo.gif,
the README's hero. The CI gained the unit job. The fork is pushed to
origin and the tree is FOSS-clean. The demo stays on the screenshot loop:
recording the virtual nest through the ScreenCast portal yields one stale
frame (docs/testing.md has the trap). Verified: `make unit` == pass 30
fail 0, `make lint-qml`, `make lint-shell`, `make test` == pass 374
fail 0 skip 1, `make test-two-outputs` == 17/0/0, fixtures byte for
byte.

### 2026-09-29 — one canvas: the vision, the reveal, the double-click, and unit tests

The coherent model is written down (docs/vision.md): one plane, one skin,
one physics, with the gaps listed. The keyhole and the overworld became
one space - the quiet canvas's skin (frames, tags, threads, glow) fades
in with the camera's departure (quietReveal). The double-click's first
click no longer pans at once: the click-fit waits out the double-click
interval, so the second tap keeps its count and the placement runs - the
grasp double-click on a fullscreen game used to land the window at the
wrong coordinates, and the placement now anchors on the camera's
destination, never a mid-flight view. The fly covers every clickable
window (isFlyableWindow - a utility window flies instead of KWin's
keep-visible rule moving it alone), the hold delay is configurable
(HoldDelay, published to the plugin), and the pure logic (the clustering,
the dynamic gap, the float's physics) moved to
effect/contents/ui/logic.js with `make unit` (30 assertions, node, no
nest). The same round added: the margin-free fly for screen-sized windows
(the task bar's click on a fullscreen app no longer lands it 24 px
off-centre), the minimap (the plane from above, click-to-fly), the
cluster drag (a hand on the badge moves the whole cluster), the quicker
hover (200 ms settle, the grace only after a hand drag), the keyhole's
toolbar at full reveal, and the persisted viewport (ViewX/ViewY written
on commit). Verified: make unit, make lint-qml, make lint-shell, make
test == pass 367 fail 0 skip 1, make test-two-outputs == pass 17 fail 0
skip 0.

### 2026-09-29 — clusters, the float, the honest hover, and a deterministic nest

Clusters: windows within `ClusterGap` of each other form a cluster live
(union-find on the entries, recomputed per revision), the active cluster
wears a dashed thread that rides the camera with its windows and a glass
badge naming its number, the rest are a faint constellation below half
zoom, and `[` / `]` fly the camera between clusters in reading order with
the travel's destination anchoring the next step. The pin became a float:
the window keeps its home coordinates, floats at the screen edge - bouncing
off it with the camera's velocity - when the camera would push it off, and
its position follows the picture so the commit and 1:1 always keep it on
screen; the flag is KWin's own onAllDesktops, repurposed, with the caption
list persisting it. The click fly works for already-active windows (the
plugin publishes the clicked window; the fly waits an event-loop turn so
the release reaches the window first), the hover glow follows the effect's
poll so it shows over client areas, the menus are opaque, and malformed
debug commands can no longer write NaN geometry. The nest pins the fixture
apps' look and resets their configs per run - the host's colour scheme had
flipped to light across a reboot and leaked into the nest through
kdedefaults, and the apps' leftover window state drifted the goldens.
Scenario 106 covers the clusters, 105 the float, 104 the already-active
click. Verified: `make lint-qml`, `make lint-shell`, `make test` == pass
365 fail 0 skip 1, `make golden` re-recorded, fixtures byte for byte.

### 2026-09-29 — the plane's desks, the minimal fly, the radial pan, and a quiet harness

Bookmarks: the digits jump to saved views, Ctrl+digit saves, persisted as
JSON, with a glass toast. The focus fly is minimal (the window's edge ends
at the screen margin) and defers while the pointer's buttons are down - the
plugin publishes the button mask, so the canvas never grabs the click that
caused the fly. A double-click during the modifier's hold animates (flyEnter
runs while visible, not just while the overworld is open). The edge pan is
radial with a speed curve toward the edge. The glass: a soft shadow under
the hovered and lifted windows. The nest harness stopped flaking: the
compositor's log is line-buffered (stdbuf -oL -eL), a nest whose effect
never answers restarts up to three times, the plugin retries its D-Bus
registration, and fakeinput's digits now send the digit keys rather than
their code values - which had silently turned `key 1` into Esc-adjacent
noise. Verified: `make lint-qml`, `make lint-shell`, `make test` twice ==
pass 353 fail 0 skip 1, `make test-two-outputs` == 17/0/0, fixtures byte
for byte.

### 2026-09-29 — pinned windows with edge physics

A pinned window is screen-fixed: it rides the camera and never leaves the
screen, the plane model's "on all desktops". Dragged past a screen edge it
bounces back inside on an underdamped spring (w=10, damping 5), and the pin
survives restarts by caption (`PinnedWindows`). Pin and unpin live on the
arrange menu; the debug channel gained pin/unpin/unpinall. Two bugs fell out
of the drive: the bounce's spring kept rewriting the pin map and resurrected
a pin the unpin had deleted (the spring now stops when the pin goes), and
the grasp's fullscreen zoom-in commit could be lost to a grab mid-flight
(it parks in deferredClose now). Verified: `make lint-qml`, `make
lint-shell`, `make test` == pass 345 fail 0 skip 1, `make test-two-outputs`
== 17/0/0, fixtures byte for byte.

### 2026-09-29 — clicks focus, the hover is the focus, and no more grab-on-click

Clicking a window focuses it everywhere (the title bar now activates, as the
client area already did natively under the plugin), the settled hover becomes
the canvas's focus with a soft activity-coloured glow and Enter applies with
it, and a click with hand noise no longer grabs: the drag and the weight's
lift both wait out a 14 px dead zone. Opening over a fullscreen app steps out
to `FullscreenZoom` (0.85) so the step is visible, for the chord and the
modifier alike, and the modifier's release springs back to 1:1 at the
committed viewport. The toolbar reads as glass. The user's live session runs
with Passthrough off for the natural feel (the plugin still watches MB4).
Verified: `make lint-qml`, `make lint-shell`, `make test` == pass 340 fail 0
skip 1, `make test-two-outputs` == 17/0/0.

### 2026-09-29 — flickerless steps, the hover made honest, and the hold threshold

The close paths fade the chrome before hiding (farewellHide, wired into
commit and doCancel), so stepping in from 1:1 no longer cuts the frames,
tags and toolbar in one frame. The hover navigation was rebuilt as an
effect-level poll of the real pointer - it works over client areas where
the plugin consumes the scene's events, and it waits out a 600 ms grace
after any gesture so it never un-pans a window the hand just dragged. The
edge pan direction flipped to the natural scroll (toward the edge), the
grasp's release commits to the panned viewport instead of snapping back,
and MB4 opens the canvas only after a 300 ms hold - quicker presses replay
as the window's own click, so games keep the button. The nest harness now
waits until the effect answers a command (KWin reports the effect loaded
before its QML completes), which was the intermittent empty-state flake,
and the runner's collation put 104 before 10, so 104 now closes its probe.
Verified: `make lint-qml`, `make lint-shell`, `make test` == pass 334
fail 0 skip 1, `make test-two-outputs` == 17/0/0, fixtures byte for byte.

### 2026-09-28 — the capture fix drive

The live journal showed one real exception storm: the thumbs restarted the
hover timer through an id (not a property), so every hover over a window
threw - the timer is a property alias now, and scenario 104 hovers, which no
earlier scenario did. The same drive hardened the close paths: a commit, a
cancel or a grasp end asked for while a gesture is in hand parks itself in
deferredClose until the buttons come up (sceneGestures counts the views'
drags), so the canvas never hands a still-held button to the desktop, where
its motion would be a native drag. Scenario 104 pins the hover, the
chord-mid-drag and the modifier-released-before-the-window cases. Verified:
`make lint-qml`, `make test` == pass 328 fail 0 skip 1,
`make test-two-outputs` == 17/0/0.

### 2026-09-28 — focus flies, the swap, pointer navigation, WASD, and the haze fades

Every focus change travels the canvas: an activation slides the desktop to
the window (and a half-off window counts as not visible, so a focused window
is always wholly on screen), the two most recent windows become the pair the
MB5 swap flies between while the modifier is held, and clicking or resting
on a window pans the camera the least that fits it. The in-canvas pan keys
are WASD (F alone is fit - W had collided with it), the haze fades with the
camera instead of switching, and the settings form was rewritten for people.
The plugin was built with the newly installed dependencies, which turned
85-passthrough from a skip into 17 real checks and made the grasp possible.
Scenario 70 covers the focus slide, 102 the WASD and the click-fit, 103 the
modifier, the swap and the held-in-overworld hold. Verified: `make lint-qml`,
`make test` == pass 328 fail 0 skip 1, `make test-two-outputs` == 17/0/0.

### 2026-09-28 — flights, the haze, border pan, the keyboard, and MB5

The step in and the cancel become flights on the camera spring (`camOnArrive`,
the chrome fade, the window fade-in on a moving opening view), home, origin
and the swatches take the spring, and a goal starts with a push so springs
move on the first frame. The backdrop becomes the wallpaper in a haze - exact
on the desks, blurred and dimmed once per output beyond them - instead of
repeated tiles (`BackdropBlur` replaces `BackdropReach`). `BorderSlide` turns
a border push into a pan, one slide at 1:1 and a camera step in the open
canvas. The open canvas gains keyboard navigation with collision-free
defaults: arrow keys pan, Tab/Shift+Tab step the selection with the camera
following, Enter with a selection steps into that window. `PanHold` defaults
to MB5, which needed both of its Qt names in the mask - KWin delivers MB5 as
ExtraButton3, not ForwardButton (verified against the 6.7.5 source's
`buttonToQtMouseButton` table). `fakeinput` grew forward/back buttons.
Scenarios 100/101/102 added, 81/91/93 reworked, the moved goldens re-recorded
after pixel checks. One trap fixed: the debug `cancel` no longer restores a
stale entry view when the canvas is already closed, which had corrupted the
scenario after a slide. Verified: `make lint-qml`, `make lint-shell`,
`make test` 281/0/2, `make test-two-outputs` 17/0/0, fixtures untouched.

### 2026-09-28 — repository hygiene, six commits

The fork's conventions written down (`.editorconfig`, `.gitattributes`,
`.gitignore`), then `REUSE.toml` with per-file attribution, then `.gitlab-ci.yml`
on `archlinux:latest`, then `make lint` so the CI checks run on this machine too,
then a commit making the fork's own files match the tree: no shebang on a sourced
scenario, no blank line at the end of the CI file. A one-number doc fix came with it
(`docs/testing.md` said the golden tolerance defaults to 0.02; `tests/lib.sh` says
0.03). A later commit added the way in: `AGENTS.md`, `CLAUDE.md` and this file.
Cleanup: a redundant clone at `~/.local/src/kwin-canvas` was removed after
`diff -rq` proved it identical outside `build/` and `dist/`, stale nest state under
`/run/user/1000` and the session's scratch files were swept. Verified: `make lint`,
`make test` 244/0/2, `make fixtures` byte for byte, all four CI scripts run here,
and the two scenario runs above re-run on this tree.

### 2026-09-27 — the fork's first session

Portals and smart placement, the carried window, honest clocks; the navigate
buttons handed to the canvas on both input routes; the physics camera; then
`81-nav-hold`, `91-two-outputs`, `93-backdrop` and `94-physics` with their goldens,
and `docs/recovery.md`.

## How to keep this file

Date your entries, delete what is no longer true instead of stacking a new version
on top, and do not let it grow into a second `architecture.md`: the model belongs
there, the traps belong in `testing.md`, and what a user sees belongs in
`release-notes.md`.
