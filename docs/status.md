# Where the work stands

The state file for whoever picks this up next, a person or an agent. It is the one
document here that is allowed to go stale: update it when you stop, rewrite what is
no longer true rather than appending, and keep it short. The model is in
[architecture.md](architecture.md), the harness in [testing.md](testing.md), and
what a user sees in [release-notes.md](release-notes.md).

## Where it stands (2026-11-11)

Everything below was measured in the hidden nest (`NEST_VIRTUAL=1`) and, for what
is marked seen live, on the maintainer's desktop after a relogin.

**The suite in the nest** (2026-11-11, `NEST_VIRTUAL=1`, the 126 scenarios in batches of
twelve, each batch a fresh nest): 959 pass, 5 fail, 13 skip before the day's fixes, no
`TypeError`, no desk reset. The five: `227`'s carried-back check (the exact return refused
a spot a window had always overlapped; fixed), two goldens the new threads moved (`90`,
`93`), and `111`/`113`, which probed where the old centre-to-centre web ran (re-aimed at
the thread between the facing sides). The skips are the two-output scenarios, `86`
(the panel's popup), `104` (the live press) and `135` (the nest cannot close a
window). **The targeted re-run after the fixes** (2026-11-12, the same nest, 32 scenarios: the
graph, the switcher, the echo, the threads, the goldens, keys, search, input, the pass-through,
grasp, activation, the frame authority, game and safe mode, the map widget, flight, and the two
decoration scenarios with `NEST_DECOR=canvas`): 375 pass, 0 fail, 0 skip, after one fix it found
(the plugin's new ` buttons=` token had gone after ` win=`, which the decor applet's contract and
`137` read as the reply's last; it now goes before). The runner's repair now names what it
repaired: thirteen of those scenarios leave another window above KCalc and `111` leaves KCalc
moved, all put right before the next scenario (see Next candidates). **Side buttons**
(2026-11-12): the hold button's quick-press replay and the overworld's hand-over of a button went
through KWin's `SeatInterface::notifyPointerButton(Qt::MouseButton)`, whose Qt-to-evdev table is
not the inverse of KWin's input mapping for the side buttons, so a real mouse's back button
(BTN_SIDE) reached windows as BTN_BACK and a BTN_BACK one as Forward; both now hand on
`nativeButton`, pinned by `229-side-buttons`. Not seen live: everything
after f2bf19e (a relogin is pending).

**Working, verified in the nest and seen live:** the quiet slide and the auto fly
(ease-out with a hair of carry, length by distance, raised on landing), bookmarks
(`Ctrl+1..9` save, `Alt+1..9` fly), the throw and the snap magnet, float (the on-all-desktops flag, held by KWin; keep above is separate), tiled and maximized windows
moving as a room and returning to their plane spot, the corner push at zoom-to-fit
and back to where it began, the dock approach, and a wallpaper that is not a picture
(Wallpaper Engine) drawn through the desktop window.

**Cost at rest** (nest KWin, 6 s samples): closed 0.3%, open canvas 0.8%, a slide 6
to 12% (all on the compositor's main thread). The idle bob was the one decorative
cost, 21% of a core zoomed out, and is gone.

**The flash at a landing (2026-11-05).** The owner: "always a flash after auto pan finishes". With
Rounded Corners on, every cornered window's picture is cut from KWin's texture through the
plugin's `frameInTexture`, which read the window item's scene rect; the item takes a move in its
own slot after the binding asks, so at a landing (every window moved) each picture sampled its
texture shifted by the whole slide until the close. Burst-captured in the hidden nest through
KWin's ScreenShot2 at about 45 frames a second, with Rounded Corners at the owner's settings, a
video-like wallpaper (the desktop window path) and the canvas decoration: the scene's last frame
differed from the settled desktop on 19.5% of the screen after a slide and 10.5% after a fly; with
the plugin reading the item's own bounds, 0.49% and 0.38%, the Rounded Corners outline the canvas
does not draw. `222` pins it: a window moved on the open canvas shows its own picture (rmse 0
fixed, 0.26 with HEAD's plugin). Needs the rebuilt plugin live (`fix-plugin`, a relogin).

**Bare slides after a game (2026-11-12).** The owner: the canvas "degraded still". The live Perf
log had every slide's `stall` line at `ql=3` (bare: rectangles, no window pictures) with the same
reading, `vram=96`, from 01:55 to 05:50, while `nvidia-smi` read the card at 37%: Deadlock had
filled the GPU's memory, the ladder stepped to bare, and only a full open reset the step or took
a reading (`loadPulse` runs only when not quiet, and the open's reset sat inside `if (!quiet)`).
Every open now starts at the mode's rung; the full overworld alone samples, as before. `116`'s new
check forces bare in a full open, keeps every reading busy, and slides: `ql=0` with the fix, `3`
with the old code. Verified: `116`, `143`, `144` and `170` in the hidden nest, 24 pass, 0 fail;
`make unit` 303, `make lint`. Not seen live (not installed).

**The window graph and the switcher, rethought (2026-11-11).** The owner: the cluster web was
not good enough; windows should be walked like a graph with Mod+arrows, across clusters too, a
window carried between clusters with Shift, and "alt+tab never enters". Decided with the owner:
Meta+Alt+arrows walk (KWin's *Switch to Window* keys, which they take over), Meta+Alt+Shift+arrows
carry, a carry always hops clusters, the threads are the walk's edges, and KWin's conflicting
shortcuts get unbound. Built: `Logic.dirScore/dirStep/walkStep/walkEdges/edgeSegment/
carryCluster/carrySpot` (unit-tested), `planeGraph`, `walk`, `carry` and `focusAndFly` in
main.qml, the threads drawn from `walkEdges` (bridges dashed, `graph=` on the state line), and the
switcher as a task switcher: MRU order, a tap flips without opening, a hold shows, the release
enters at once, reverse chords owned by the canvas, and the plugin's key filter bumping `chordUp`
on the chord's release (the poll and the scene's key-up stay as other paths). The live Alt+Tab
bug was the settle beat restarted forever by the poll (4d76af3, not installed live), plus KWin's
reverse chord still bound over the canvas's Shift+Tab. Closed flies now take their neighbours from
the live windows, not the last open's entries; a glide that lands re-clusters. The nest unbinds
KWin's switcher and directional keys (`dev/nest.sh`), and `227` and `228` press the real chords.
Found by review and fixed the same day: without the plugin the switcher never entered (KWin's
`DBusCall` reports a missing object through `failed`, which nothing handled, so the blind path
never armed; `chordBlind` is now set at the press when the plugin's helper is absent), a window
carried straight back could not return when it had been alone or when a window had always
overlapped its old spot, a closed carry under separate cameras wrote through the wrong target, the
cluster switcher on a cluster of one fitted the lone window and picked one off the screen, Esc in
the switcher cancelled the whole canvas, and the reverse chords' modifiers were not in the release
mask. Verified: `make unit` 303, `make unit-cli` 203, `make lint`, the plugin builds; the nest:
the full suite and the targeted re-run above (`227` and `228` press the real chords, 0 fail). Not
verified: anything live, and in the nest the chords without the plugin, the OSD fallback of
`notify`, Bring here, Close and the two-tap trash (no scenario drives them yet).

**Windows drifting on the plane (2026-11-09).** The owner: windows "drift from their
coordinates all the time". The live Perf log showed `slide dist=316` then `moved … System Monitor
dy=316` (and 632/632, 822/822): a window going back by a slide's whole length right after the
landing, adopted as its own move. KWin 6.8.2's source has the mechanism: each configure keeps the
window's place when sent (`bounds = moveResizeGeometry()`), a commit of it puts the frame there,
and a script's `frameGeometry` write (MoveResize) leaves the queued configures alone, unlike
`Window::move`. A focus change sends one to the window gaining and to the one losing the focus; a
busy client, or one the scene covers, commits it after the landing. Fixed: `setReal` moves a window
at its own size through the plugin's new `canvasPlugin.moveWindow` (`Window::move`); without it the
effect notes the spots its writes leave and puts back a plain move onto one (`Logic.isEcho`,
`reverted … why=echo`). The state line's `mover=` says which; Perf `moved` now logs closed-canvas
adoptions too (they were silent). `226` stops KCalc across a fly (gaining and losing the focus).
Also fixed, from 4d76af3 (never run in the nest before this): a reconfigure and
the load published only the hold mask and the door to the plugin, so a changed HoverDelay or
HoldDelay reached it only at the next open (`85` failed); both publish everything again, and the
plugin's `setHoldDelay` leaves a running hold's clock alone at an unchanged value, as
`setHoverDelay` does. The echo net was narrowed after review: it reverts only after a focus change of that window since
the spot was noted, and never within 300 ms of the hand letting go (a tiler writing a window back
where it was is adopted, as the README promises). Verified: `226` in the nest with the plugin
(`mover=plugin`, 0 echoes, no plane change), the full suite above. Needs the rebuilt plugin live (`fix-plugin`, a relogin); the effect's echo net
covers an older plugin meanwhile.

**MB4 in a borderless game (2026-11-08).** The owner could not bind MB4 in Deadlock. Deadlock ran
borderless (KWin: maximized, `fullscreen: false`, 4096x1152, class `steam_app_1422450`), so game
mode, which needed `fullScreen`, stayed off; the plugin's hold mask was `72` (BackButton, the
default `CanvasHold`), and it took every MB4 press: under 300 ms replayed as a click, longer
never reaching the game. `Logic.isGameWindow` now also takes a Steam game's window
(`steam_app_<id>`) however it runs. Verified: `make unit` 205 (the new cases), `make lint`.
Not verified: the nest (no Steam game there) and the live game. Games outside Steam (Lutris,
Heroic) that run borderless still need fullscreen or another `CanvasHold`.

**Whole-codebase review (2026-11-07).** Five read-only reviewers over all the code (main.qml in three
parts, ui.qml with logic.js, the plugin with the CLI, applets and decoration) plus a review of the
last week found about 70 issues; all are fixed in one commit except the narrow timing of a hold
landing exactly as a slide closes (handled, not reproduced). The ones a user would notice: the
chord switcher never stepped in after the release with the plugin live (the 80 ms poll restarted
the settle forever); a key held in a passed-through window kept repeating after the pointer left
it; a release over a panel lost the next click; Home and Search during a slide, an activity
switch mid-slide, and input during the 170 ms farewell (a second commit, an extra undo step);
`reset` left plane restore spots, app homes and parked windows behind; `tidyRows` put the second
row thousands of px off at a negative origin; separate cameras moved undrawn windows by the wrong
monitor's delta, drew other activities' windows on the replica and frames at the camera
monitor's target; the door ate the desktop's wheel-up and sideways scroll; the decor applet
spawned `qdbus6` four times a second for the session. Closed-canvas cost cut: the kept scene's
per-thumb handlers and geometry bindings, `skinReveal` on every pointer motion, seven D-Bus calls
per game-mode flip, the plugin's effect lookup and unchanged property writes per event, the state
file's fsync every second. New: the map widget holds and releases the map (`hold`, `release`,
a bus watch, a minute's lease for a plain read); the camera keeps its speed across a retarget and
pan steps add up from the goal; the blurred wallpaper only while a window wears a patch; web
strokes by quarter octaves of zoom; switches for `FloatDodge` and `ThumbnailBlur`; the inert
`BackdropBlur` and `BackdropDim` rows gone. Verified: `make lint`, `make unit` 199, the CLI
tests 137, `make plugin`. Not yet verified when committed: the hidden nest (a game held the GPU);
the full suite, the decoration batch and a control of `102` against the previous effect are
queued.

**Audit after the auto pan revert (2026-11-05).** A review of f061db1..a890058 found 10 issues,
all fixed: the float dodge's home spot is forgotten on a hand move (not a resize in place), on
unfloating and on an overview open; a focus on a launcher, a panel, the desktop or a maximized,
tiled or floated window moves no float; floats are planned in turn, so two never take one spot
and none goes home onto another; a glide in flight lands before the next is planned or the
canvas opens; a settle while the canvas is up waits for the close instead of re-arming; the plugin's
frame watch is per window (`frameWatch`), so one window's resize re-reads only its own picture,
and it finds the window's item again when KWin builds one later; the three idle wakes are one
(`wakeFromIdle`). The full suite (123 scenarios, the first full run since 86cc400) gave 903 pass,
2 fail, 13 skip; both failures traced and fixed: `225` showed that un-maximizing the focused window
never re-checked the floats (the focused window's maximize, tile and hand move now start the
clock), and `87` failed whenever it ran after `85` (on HEAD's plugin as on the new one, 3 of 3
each): closing the canvas left the plugin's hover candidate set, so a rest on that same window at
the next open never started the hover clock and the window never took the input until the pointer
left and came back. `181` left the seeded default panel for the runner to repair; it reshapes the
desk as `117`, `149` and `86` do. Not explained: a 1.8 s KWin stall during a hold on the live
desktop at 05:10 (cpu 19%, gpu 39%).

**A float steps aside (2026-11-05).** The owner's idea: a floating window moves so the focused
window shows whole. `docs/architecture.md`, *A float steps aside for the focused window*.
Verified in the hidden nest: `225` (steps right of the focused window, comes back, stays with
`FloatDodge` off), with `105`, `162`, `166`, `178`, `222`, `150`, `204`, all pass; `make unit` has
`dodgeSpot`'s cases. Not verified: the live session, two monitors, a float bigger than the gap
beside the focused window on both sides (it then takes a corner or stays).

**The decoration is a bar (2026-11-05).** The owner asked for the decoration's look as a bar "so
rounding can play nicely": with Rounded Corners (16 px, an outline) on, the effect shaped the
frame, whose top 32 px were a transparent band, so the rounding and the outline fell on nothing
and the visible window kept square top corners. The band is now drawn edge to edge in the colour
scheme's title bar colours (`DecorationOptions.titleBarColor`, `fontColor`, `titleFont`, which
follow the focus), the glyphs keep their marks in the scheme's text colour, left and right sets on
their own sides, and the caption sits centred between them. Verified in the hidden nest with the
decoration loaded (`NEST_DECOR=canvas`): `135` (rewritten: both windows wear a drawn bar, the
active and inactive colours differ and swap with the focus, the frame's top corners are the bar),
`221`, `137`, 22 pass, 0 fail, 1 skip (the close glyph, live only); the shot was looked at. Not
verified: the live session with Rounded Corners (the nest runs no third-party effects), a light
colour scheme.

**Review of f1ebb2c..f061db1 (2026-11-05).** Fixed: the hover rule's gaps (since removed with the
rule, above); the map widget and the built-in minimap colour a
frame by its activity, not its place in `frames()`; the map watches `currentActivity`; `mapGo`
centres on the camera screen with separate cameras; `220` no longer leaks `VramReduced`; a press
that wakes the pass-through tells the effect; the kept scene's VRAM watch makes one NVML call.
Verified in the hidden nest: `204`, `180`, `182`, `207`, `224`, `220`, `116`, `123`, `85`, 99 pass,
0 fail; control, `204` against f061db1's effect fails exactly the new click-to-focus case. Not
fixed, stated instead (`docs/architecture.md`, *The map widget*): once read, the map keeps
watching until KWin restarts, a removed widget included. A stop rule (the widget saying it is
gone, a lease per D-Bus client) is a proposal.

## Next candidates

From the seven reviews of 2026-11-11 (interactions, the pending diff, the plugin, the
satellites, the harness, settings and docs, performance), what was not done that day:

- Minimized windows in the switcher pool: KDE's Alt+Tab reaches them, the canvas's does not
  (the plane does not draw them, so the pick would be invisible; a card-only pick is the design
  question).
- Bookmarks with the canvas closed (`Alt+1..9` are scene keys): nine global actions with no
  default that slide to a saved view at 1:1.
- The slide's 6 to 12%: most likely the `viewX`/`viewY` binding fan-out, twice per frame (two
  NumberAnimations) over every thumbnail, frame and chip on both views, plus the ground's ~100
  invisible items re-bound at 1:1 and the chrome's edge marks once the chrome has been built.
  The measurements that settle it: `perf record` on the nest's KWin over 50 slides; hot-reload
  ablation of the ground models, the marks' `quiet` gate and a single camera point; a per-slide
  `ticks=` on the Perf `slide` line. A plane `Item` with one transform per view is the
  architectural fix.
- NVML on the compositor thread (`load`, `gpuMemory`): time it, then a worker thread or a skip
  while a fullscreen game has the focus. The 16 ms physics timer runs for the whole open
  session; gate it on a camera, a float or a glide being live.
- The harness: `kwinjs` should poll the log for its tag instead of a fixed settle and fail
  loudly; `arrange` should place every window and then size them so `heal_sizes` can go; the
  runner should trap INT/TERM and bound `spectacle`; a scenario with no checks should count as a
  failure; CI could build the plugin (`kwin cmake extra-cmake-modules` in `ci/packages.txt`).
- `main.qml` is 7k lines: the switcher, the graph, the frame authority and the search are each a
  block that could be its own QML object or JS library once the suite can prove a split moved
  nothing.
- The decoration's accent is a fixed blue; the band is 32 px whatever the title font. The map
  widget is unchanged by this round.
- Scenarios that leave the desk changed: the runner now names each repair (`desk reset
  after …`). Thirteen leave another window above KCalc (`80`, `85`, `87`, `103`, `113`, `126`,
  `137`, `184`, `204`, `210`, `221`, `226`, `227`), and `111` leaves KCalc at 900,300. Each should end with `arrange` (or its own undo) so the repair is the exception again.
- Scenarios for what only review has seen: Bring here, Close and the two-tap trash, the `notify`
  OSD without the toast, the switcher with no plugin (`chordBlind`), the plugin's popup-grab and
  keyboard-focus checks.
- A real Wallpaper Engine / KZones run, which only the desktop can give.
- The fly starts with the open (no warm-up turn). The first painted frame is
  the desktop's own picture; only the nest has checked there is no flash.
- The open's first tick comes 150 to 200 ms after `open()`. Read `kwin-canvas perf:
  first-paint` on the desktop (`Perf` knob) to see whether it is the same there; if
  it is, only a smaller scene or a KWin change would shorten it.
- Pre-warm the first open (user item 4): the nest says it works (first open 284 to
  338 ms down to 172 to 178 ms, idle CPU unchanged) but only for the first open of a
  session; the shipped form is not written. Open questions: whether a start/stop at
  load flashes the full-screen scene or grabs input on the desktop, and a cheaper
  warm than a raw `visible` toggle. Keeping the effect started permanently to skip
  the per-open `QRhi` cost is not tried; direct scanout is reasoned, not measured.

## The fork

`main` is a fork of [`aaronsb/kwin-canvas`](https://github.com/aaronsb/kwin-canvas)
(remote `upstream`, GPL-2.0-or-later). `origin` is the GitLab fork
(`git@gitlab.com:ritwick7/kwin-canvas.git`) and is pushed. `make release`, `make aur`
and `make aur-passthrough` publish to upstream and are not ours to run. The fork's
own work is `git log --oneline upstream/main..HEAD`.

## Decisions taken, and the ones still open

Taken, with the reasoning in `AGENTS.md` → *Deliberate, not accidental*: no
`.clang-format`; docs and images stay `GPL-2.0-or-later`; no scenario job in CI (the
linters and `make unit` run there, shellcheck at error severity included); `qmllint` by absolute
path; the scenarios stay local because they need a nested KWin.

Open:

- Whether the fork publishes anything of its own (tags, GitLab releases) or upstream
  stays the only publisher.
- Whether a runner can host a nested KWin — that is what a CI test job would need.
- Whether docs and images should move to `CC-BY-SA-4.0`, KDE's own choice for them.

## Sessions

Older session logs, newest first, are in [status-archive.md](status-archive.md).

## How to keep this file

Date your entries, delete what is no longer true instead of stacking a new version
on top, and do not let it grow into a second `architecture.md`: the model belongs
there, the traps belong in `testing.md`, and what a user sees belongs in
`release-notes.md`.
