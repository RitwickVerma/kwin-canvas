# Where the work stands

The state file for whoever picks this up next, a person or an agent. It is the one
document here that is allowed to go stale: update it when you stop, rewrite what is
no longer true rather than appending, and keep it short. The model is in
[architecture.md](architecture.md), the harness in [testing.md](testing.md), and
what a user sees in [release-notes.md](release-notes.md).

## Where it stands (2026-10-31)

Everything below was measured in the hidden nest (`NEST_VIRTUAL=1`) and, for what
is marked seen live, on the maintainer's desktop after a relogin.

**Working, verified in the nest and seen live:** the quiet slide and the auto fly
(ease-out with a hair of carry, length by distance, raised on landing), bookmarks
(`Ctrl+1..9` save, `Alt+1..9` fly), the throw and the snap magnet, float (the on-all-desktops flag, held by KWin; keep above is separate), tiled and maximized windows
moving as a room and returning to their plane spot, the corner push at zoom-to-fit
and back to where it began, the dock approach, and a wallpaper that is not a picture
(Wallpaper Engine) drawn through the desktop window.

**Cost at rest** (nest KWin, 6 s samples): closed 0.3%, open canvas 0.8%, a slide 6
to 12% (all on the compositor's main thread). The idle bob was the one decorative
cost, 21% of a core zoomed out, and is gone.

**The suite in the nest** (2026-10-16, `NEST_VIRTUAL=1`, one full run): 655 `ok`,
0 `FAIL`, 4 skip in one run; the runner repaired window sizes after about ten
scenarios (see below). It is one run, not a repeated green: the skips are the
live-session proof of the press delivery, the canvas decoration, and 91 twice for
needing two outputs; no `TypeError`. The old totals were
low: `source tests/lib.sh` at the top of many scenarios reset the runner's tallies, so
`== pass` counted only the tail; that is fixed. The leak was one scenario:
`113-thread-duck` left the nest on Activity 2, and the next `arrange` pulled
Activity 2's view target onto Activity 1's (the "tint" and the "Activity 2" failures
from 20 to 95). Others found and fixed: `117`, `149`, `86` leave Plasma's default
panel and wallpaper, `159` added three windows, `115` raced its own read, `111`
read the rest's focus too early (fixed by a quiet wait past the hover delay; the
plugin also restarted a running hover clock on every debug command, a separate
fault fixed in the plugin and pinned by `168`), `107` pressed where a dock
is inferred to sit. The runner now also resets the activity, a
leftover panel and window sizes after every scenario and prints
`desk reset after NAME` for each, which a clean scenario never triggers; today those
lines still name `114`, `115`, `116`, `117` (KCalc and Gwenview 410 high), `120`
(432), `148` and `95` to `99` (Dolphin 368 to 370). Cause, found on 114 only:
`placeby` sizes go through the user-resize path, which snaps an edge to a
neighbour still standing at its old place (12 px), so `arrange` is not idempotent
on size; the others show the same signature and were not run (`docs/testing.md`).

**Several monitors.** The design for two cameras on one canvas (Merged and Separate
modes, every interaction in both, the data model, the build order) is in
`docs/multimonitor.md`. Built: a focused window is never left on the seam or in dead
ground (`173`), the chrome sits on the pointer's monitor (`172`), one frame tag per
activity with no output names. Built, off by default (`Cameras=separate`, experimental): a desk per monitor, the overview
on one monitor with the others showing their desk, and a slide that moves one monitor only
(`174`, `175`). Input on the other monitors needs the rebuilt plugin (`176`). Not built: panels on the other
monitors, the rest of stages 3 to 7. Tested only in the nest, on two outputs stacked
and offset as the maintainer's are.

**The frame path (2026-10-23).** The owner's zoom-to-fit opens ran at about 650 ms a frame at zoom 0.34,
steady after the camera settled: with a floated window the cluster web's model changed every frame and
rebuilt hundreds of path items. Fixed, and checked live after `make hot` (two fit opens: 16 to 17 ms
frames, worst 49, no stall, settled in 0.5 to 0.8 s instead of 3). Then the general cure
(`docs/architecture.md`, *The frame path*): the web woven once by the effect from explicit triggers and
drawn as layers (26 items a session instead of about 480 in `208`), clusters published only when they
change, the clusters and web computed at the open, the chrome built only when the overview needs it,
the `built` Perf line, `208-frame-budget`, and a `frames` check in the doctor. In the nest, with the web
drawn, the previous commit's fit open had a p95 of 61 ms and a drag one frame of 654 ms; now 18 ms and
35 ms at most on one output. The nest's frame times are a software renderer's and vary with the host.

**KWin's effects on the canvas (2026-10-31).** A thumbnail is drawn past KWin's effects chain, so the
canvas redraws two of them itself, with what the plugin reads (`docs/architecture.md`, *What KWin does not
do for a scene effect*): the Rounded Corners effect's corners (`222`) and the blur effect's blur behind
translucent windows (`223`: Better Blur DX's wallpaper mode exactly, KWin's blur over the bare desk; another
window behind is not blurred; `223` passes in the nest). Not drawn: the corner outlines and Better Blur
DX's refraction. All of it, and view caching (`220`), needs the
plugin of the same commit installed (`kwin-canvas fix-plugin`).

**The suite in software (2026-10-31).** The nest renders with Mesa's llvmpipe unless `NEST_GPU=1`. The one
full run since (with fonts pinned, for portable goldens) went 831 ok, 27 FAIL, 14 skip, but a game started
five minutes in and held the CPU: the failures are drags and flicks read mid-gesture (`103`, `104`, `81`,
`94`, `152`, `161`, `165`, `30`, `126`) and two screenshot compares (`93`'s knobs, `128`'s seam). It has not been repeated on an idle
machine, so whether llvmpipe alone slows those reads is not known; its goldens were thrown away. Repeated
on an idle machine it went 860 ok, 4 FAIL, 14 skip, and three of the four were view caching's: `128`'s seam
twice (the kept scene drew the desktop window `117`'s layout reload had replaced) and `30`'s restore (the
kept scene put back the canvas's own shift), both fixed (`docs/architecture.md`, *View caching*). The
fourth, `150`, caught one stale landing in 40; it caught one in a later batch of six scenarios and none
in 80 more landings, alone or after `117` and `128`. Cause not found. `81`'s window-follows-the-step check
failed once in that batch and passed alone and after `30`.

**Portable goldens (2026-10-31).** The goldens depended on three things of the host's, now all pinned in
the nest: its fonts (`tests/fonts`, a fontconfig of the nest's own; Konsole's width snaps to its font's
cells), the checkout's path (Dolphin's breadcrumb, now a `fixtures` place), and its third-party KWin
effects. KWin 6 builds its own effects into itself, so every binary in `effects/plugins` was installed
on top, and those load by default: the maintainer's Rounded Corners reshaped every window (and rewrites
`breezerc`), so a full run's goldens showed it before `222` unloads it and not after (`resized` 0.047
between the two). The nest now switches every such effect off and drops `breezerc` at each start; `222`
and `223` load theirs over D-Bus. Recorded that way, the snapshot scenarios match their goldens within
0.007 run alone and run after `222` and `223`, and the two-output ones (with `222` first) within 0.006.

**GPU memory and a closed canvas's cost (2026-11-02).** A game filled the maintainer's card (Deadlock, 7.2
of 10 GB) and the NVIDIA driver then refused every new GPU channel until a reboot: the video wallpaper's
renderer could not start, and a full card had wedged the driver on 2026-10-30 too. Three changes:
the corners are cut straight from KWin's thumbnail texture through the plugin's `CanvasSceneHelper`
(no full-size layer per window; `scenehelper=`), the fidelity ladder has a fourth channel, the GPU's
memory (`vram=`, `VramReduced`/`Minimal`/`Bare`, doctor), and the kept scene is idle while closed. That
last one was a real cost of view caching: every thumbnail kept its window, and KWin copies a
thumbnail's window on every frame it changes and keeps a hidden one drawing at the screen's rate. Now the
pictures have their windows only while the canvas is up (not at bare either), and a video wallpaper,
which the canvas never drew through `DesktopBackground`, no longer has one per frame and screen.
Measured in the nest: windows KWin draws offscreen after a close went from 6 to 0 (`offscreen=` on
the state line, `220`; at bare 5 to 0, `116`); a minimized client that draws on every frame callback
(`es2gears_wayland`) used 8.7% of a core after the canvas had been opened and closed and 0.0% now, as
before any open. KWin's own CPU with one window redrawing did not move measurably on one output in
software. Not measured: the GPU-side copies on the maintainer's 4096x1152 screen, and frame times of the
new corners on a GPU. Full suite in a software nest: 871 pass, 1 fail, 13 skip; the one failure was
`126-grasp-landing`'s known intermittent check, and `126` alone then passed three runs of three.

Follow-up the same day: the closed scene let go under memory pressure, and a quiet input filter. The kept
scene held its views' swapchains and every window's last picture in GPU memory for good; now a closed
canvas reads the GPU's memory every 5 s while it keeps a scene (`gpuMemory()`, in process) and drops the
scene at `VramReduced` (`kept=`, `220`). In the nest, KWin's resident memory fell from 454940 to
437712 kB on the drop (software rendering, one 1920x1080 output, five small windows); the GPU memory
freed on the maintainer's card is not measured. The plugin's filter ran its hover logic for every motion
of the session while closed, and its idle clock restarted on every event and repeated every 4 s for
good; closed, motion now stops after the chrome flag. KWin's CPU under a stream of about 1850 motions a
second over a window, closed canvas, three runs each: 18.2 to 18.5% before, 17.4 to 19.3% after, so the
filter's share is lost in the noise of the nest's software cursor; not claimed as a saving. Full suite
after both: 872 pass, 4 fail, 13 skip. The failures were `87-passthrough-zoom` (the hover over the
picture), `94-physics` (a spring-on drag landing 23 px off) and `98-snap` (the grid snap 9 and 12 px
off), none of them flaky before; run alone straight after, the three gave 34 pass, 0 fail. Read as the
batch's order or the machine's load, not as this change, but not proven so: watch them in the next
full run.

**The map widget (2026-11-03).** `applet-map` (**Canvas Map**) is the corner lens as a Plasma widget,
on the desktop or in a panel, with the canvas closed (`docs/architecture.md`, *The map widget*). The
effect answers the plane (`mapPlane`), the plugin's new `/KWinCanvas/Map` object relays it and says
`changed()` at most every 100 ms once someone has read, and the widget reads on that signal through
Plasma's own D-Bus module, with no polling. Verified in the hidden nest: `224` alone, 16 pass, 0
fail (the reading matches the effect's entries and view, no signal before the first read, `go` and
`focus` slide the desk, the widget draws and a click on it moves the desk); with `137`, `85`, `220`,
`154` and `145`, 75 pass, 0 fail. Control: the first run sent `go`'s arguments under the signature
`dd`, the call reached KWin with none, and exactly the click check failed. The panel form was looked
at once in a nest panel (the compact map and its popup). Not verified: the live session (it needs
the plugin, `kwin-canvas fix-plugin`, a relogin, and the widget added), the popup's size on the
maintainer's 4096x1152 plane, and separate cameras on two outputs.

**Windows snapping back on a hover (2026-11-03).** The owner: window positions get reset, a window
jumps back by itself. With focus following the mouse, resting the pointer on a window hanging over
a screen edge gives it the focus; KWin then brings its title bar or edge into reach, the canvas took
that for a pull and put it back, and the auto fly slid the whole desk to show the rest (84 px for a
window 60 px above the top, about 500 px for one 50 px in from the right). The live log that day:
302 reverts, 243 of them parked windows pulled (correct), 15 of 4 to 99 px on windows that showed
on the screen; 112 slides, 74 of 300 to 999 px. Fixed: a focus that followed the mouse (no button,
the pointer on the window) does not fly, and, closed, the window the pointer rests on keeps KWin's
nudge (`docs/architecture.md`, *Frame authority*, fourth edge). A first, wider rule (keep the nudge
of every window that showed on a monitor) broke `182`: the canvas's own sliver-on-screen placements
were pulled to 1820 and 1052. Every other path was checked in the nest at the owner's settings
(scale 1.25, focus follows mouse, autoraise, no click raise) before the fix, 15 pass, 0 fail: drags,
an overview move and step in, the task bar's fly, a reopen, a restore, a zone snap, a same-size
move, Move Window to Center, Quick Tile Left. Verified in the hidden nest: `180`, `182`, `207`,
`204` and `224`, all pass (`204` 10, `224` 16); control, `204` against the committed effect fails
exactly the two hover checks (the desk slid 84 px, the nudge put back). `204`'s old hover case
rested on a title bar, which takes no focus, and passed whatever the canvas did
(`docs/testing.md`). Not verified: the live session, the paths sweep again with the fix, the full
suite.

**Desktop stutter, read from the perf trace (2026-11-03).** Another session's audit counted 267
"compositor freezes" of 50 ms or more in 24 hours. They are the effect's `stall` lines: the 16 ms
tick late by 60 ms or more, which is KWin's main thread blocked, measured only while the canvas
scene is up. In those 24 hours the canvas ran 871 times (mostly slides) and 146 runs had a stall;
208 of 269 stalls were 60 to 99 ms, 112 came with the GPU's memory at 95% or more, and most of the
rest were full-fidelity slides with the GPU under 80% busy (about 5% of slides have a p95 tick of
60 ms or more). They do not line up with the plugin's 1 s state-file write. KWin's own watchdog
("The main thread was hanging temporarily!") fired 9 times: the NVIDIA driver out of video memory
during a game (01:05), a Proton launch (18:05), audio devices re-added around a Vibepollo stream
session (17:06, 3.2 s then 22 s; 04:58), and 19:06 unexplained; four of the five clusters also sit
within a minute of snapper's hourly cleanup, a lead only. With the canvas closed, a 30 s probe of
KWin's D-Bus answered within 12 ms at worst. Vibepollo's session controller runs `kscreen-doctor -j`
about every 5 s (23,691 runs in 24 hours) with no measurable delay to KWin. Turning the canvas off
removes this measure with it, so an on/off count cannot settle it. Next: a measure of KWin's main
thread that runs with the canvas on or off, and a stall line that splits the canvas's own JS time
from the rest.

**Window coordinates drifting (2026-10-20).** Causes found and fixed: a floated window rode to a screen
edge on every slide (`178`), and KWin's reachability rule moved the windows the canvas parks beyond every
monitor, every time it looked at one again (focus, activities, work area, an open or close): `112-overlay`'s
3980, a fly's target landing at the screen edge, parked windows scattered by a scale change, Discord moved
by 7075 px at an overview open. They are now one classifier with one rule (`docs/architecture.md`, *Frame
authority*; scenarios `180` to `184`, `204`, `206`, `207`). Its price is stated there: a script that brings
an out-of-reach window onto a monitor is undone. What makes KWin look again at every open in the maintainer's
session is not known and the nest does not reproduce it (`205`); the `moved` and `reverted` Perf lines say how
long after an open, close, focus change, dock event or layout change each move came. Not checked on the desktop.

**Known failing (full run of 106 scenarios on 2026-10-21, KWin 6.8.1: 765 checks pass, 5 fail, 10 skip by design).**
Four of the five are golden snapshots a little over the 0.03 threshold (`10-open-identity` `open-1to1`, `50-resize`
`resized`, `80-input` `input-dragged`, `93-backdrop` `backdrop-slide`: rmse 0.032 to 0.044), and `30-commit`'s
`after-commit-1to1` (0.045) and `91-two-outputs`'s `two-output-corner` (0.086) fail the same way on other
runs. Not the canvas: the diff is Konsole and Dolphin. Konsole's window is about 10 px narrower than the
golden's, because a terminal's size snaps to its cell grid and this machine's monospace font has other
metrics, and Dolphin's breadcrumb shows the checkout's whole path (`Stuff > Projects > kwin-canvas > tests >
fixtures`) where the golden shows `fixtures`. So the goldens depend on the host's fonts and on where the
checkout lives (both pinned since: *Portable goldens*, above). They also fail on the commit before the
frame authority, so the consolidation did not cause them.
`127-rest-cue` failed its last check in that run: it still asserted the rest cue ends at the handoff, and
the cue has stayed full while the window holds the pointer since the 2026-10-07 "window wears the hand" change. It
now asserts that, and that the line goes when the pointer leaves (7 checks pass).
`126-grasp-landing` failed one check intermittently once and passed on the later runs. `112-overlay` passes
alone; why it once failed inside a full run was not found.

**Not verified:** KZones, `sticky-window-snapping` and `rememberwindowpositions`
against the canvas (not in the nest); a Wallpaper Engine wallpaper in the nest;
the raise after a fly with focus-follows-mouse and no click-raise (reasoned from
the code; the nest raises on activation itself, so scenario `155` is only a guard).

**The CLI reads the machine.** `kwin-canvas doctor` (installed against the repo,
session against files, shortcut clashes, the fidelity ladder, what is enabled) and
`kwin-canvas perf` (summary of the effect's `kwin-canvas perf:` journal lines) are
read-only and tested by `tests/unit/cli.test.sh` (`make unit`) against a fixture
home, a fixture source tree (never the checkout's own `build/`) and a fake `qdbus6`;
CI runs them in its `unit` job. `doctor` makes one `Passthrough.load` call, which
advances the plugin's cpu sample window (the effect's next 2 s reading covers a
shorter span) and is otherwise read-only. `perf` only parses: the effect does not emit those lines
until its `Perf` knob lands. The first real `doctor` run found the Meta+Ctrl+Space
clash (Canvas Home and Mouse Tiler: Change Mode) and a CLI one commit behind.

**Perf trace.** The `Perf` knob (off by default; off costs a boolean test per
call site, idle CPU within noise) writes `kwin-canvas perf: EVENT key=value`
lines to the journal: `open`, `first-paint`, `settle`, `slide`, `hover-fetch`,
`ticks` (format in `architecture.md` -> *Motion*). Scenario `169-perf` checks it,
and that off writes none. With it, the open's 150 to 200 ms before the first
tick was taken apart in the nest: about half is KWin building a fresh
`QQuickWindow` and `QRhi` for the scene on every open, a quarter is
instantiating `ui.qml` (spread thin, no one section above noise), a quarter is
the first frame. The first open of a session is slower still: 284, 338 and
310 ms in three fresh nests (small sample, the harness's open at 1:1). A
throwaway start/stop of the effect 3 s after it loads brought that to 172 to
178 ms in three nests, with the closed idle CPU unchanged, so a pre-warm of the
first open works in the nest; it is not shipped (see the candidates below). The
KWin-side half is gone now: view caching keeps the scene between opens (through
the plugin, `220`), 39 to 59 ms to the first paint in the nest. Nest timings,
not the desktop's.

**Installing.** `make install` is the only target that writes `~/.local/share`, the
copy the live session loads at login (and the login autostart
`~/.config/autostart/kwin-canvas-plugincheck.desktop`, which warns when the plugin
was built for another KWin). Tests and the nest use `build/nest-data`
(`make nest-install`). The plugin in `/usr/lib/qt6/plugins/kwin/plugins` is
installed by hand with `sudo`.

**Float audit (2026-10-16, hidden nest, scenarios 161-167).** Fixed and tested: a
hand on a displaced floated window (161), stepping into one (162), a window that
grows at the edge (163, with unit tests of `floatStep`/`floatAdvance`), the marquee
(164), a throw guard (165), and a window on the second output (166, run with
`NEST_OUTPUTS=2 tests/run.sh 166`; `e.window.screen` does not exist in KWin 6).
A floated window stepped into another activity (167): `commit` first landed floats
against `targetOf(currentActivity)`, which is still the old activity while a switch
the same call asked for is unreported, so the float was written to the activity
being left (641f745 claimed otherwise); `commit(activate, dest)` now lands them
against the destination, passed from `finishEnter`, the cross-activity branch of
`focusWindow` and `activityAdded`. 167 covers `goto` with SmoothZoom off and on and a
cross-activity `focus`; `newActivityAt` and a real switch with a pointer are not covered.
Checked and fine: maximize/restore with the canvas open, arrange/tidy/send-to, undo.
Deliberate, now commented: floats are not thrown; the minimap sheets and the web's
thread ends sit at the coordinates. Not checked: the resize grip with a real
pointer, a drag across the seam, SmoothZoom on for anything but 167's goto,
vertically stacked outputs, the switcher's Alt+Tab chord on a float.

## Next candidates

- Make `arrange` stop snapping against stale neighbours (place every window, then
  size them; tried on 114 and it held 420, not applied or run on the whole suite),
  then drop `heal_sizes`. Same guard as the hover clock for `setHoldDelay`, which
  restarts a running hold timer the same way (not shown to matter).
- A real Wallpaper Engine / KZones run, which only the desktop can give.
- The slide costs 6 to 12% of the main thread; where it goes is not known.
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
