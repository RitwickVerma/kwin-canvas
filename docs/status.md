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

**A float steps aside by the shortest move, room or none (2026-11-16).** The owner: the dodge "doesn't work if
the geometries don't fit on the screen", and some overlap is fine if the most of the floats and the
focused window shows. `Logic.dodgeSpot` returned null when none of its eight spots cleared the
focused window, so the float stayed wholly under it. It now falls back to `Logic.leastHiddenSpot`:
the spot in the work area where the float shares the least with the union of the focused window
and the other floats (`Logic.coveredArea`, an area two of them share counted once), which is the
spot that leaves the most of all of them on show; nearest its own spot among equals, and only for
a gain of a tenth of the float's area or more (`DODGE_MIN_GAIN`), so a sliver or a maximized focus
moves nothing. Exact by construction: the shared area is bilinear between the places where the
float's edges meet theirs, so the candidates are those places, the area's ends and the float's own
row and column. The home logic is unchanged (the float goes back once its home clears the focus).
Then the owner: "at all times, the windows should move minimum distance to satisfy conditions".
The clear search tried eight fixed spots (four straight slides, four corners a gap in from the
screen's edges), so a blocked slide sent the float to a corner or the far side; it is now exact
(`Logic.spotLines`: every crossing of the lines where the float's edges meet the area's or another
window's, flush or a gap away, holds the nearest point of every box the float may take), with the
other floats kept a gap away too when there is room. A seeded property test checks 35 random desks
against a scan of the whole area every 4 px: none has a nearer clear spot. Verified: `make unit`
(logic 366: the least hidden corner, another float counted, the sliver, the
union counted once, a float wider than the area, the nearest of equal spots), `make lint`; the
nest: `225` extended (a 1500x850 focused window with no room for a 460x420 float: it lands at
1460,660, the spot `Logic.dodgeSpot` works out from the nest's own work area, and goes home when the
focus moves on), with the 12 other float scenarios, 70 pass, 0 fail, on the partial step and
again on the exact search (225's clear step still lands at 1352,250, the straight slide being the
shortest there). Not verified: live, and two monitors (the dodge keeps each float on its own
monitor's work area, as before).

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

**The display's rate, and a review round (2026-11-14).** The owner's monitor runs 5120x1440 at
240 Hz (`kscreen-doctor`); the live Perf `ticks` read p50 16 ms. KWin's compositor installs its own
Qt animation driver and advances it once a composited frame (`Compositor::composite`, read from
`libkwin.so`), so the slides' `NumberAnimation`s already moved every frame, while the open canvas's
camera, glides, floats and edge pan were stepped by a 16 ms timer: 60 positions a second, each held
four frames. They are now stepped by a `FrameAnimation` while something moves, the timer only
starting a motion and carrying it when no frame comes, both paced by `Logic.tickPace` on one clock
(12 unit cases: even 240 Hz steps from a whole-millisecond clock, no double steps at 60 Hz, a
stall carried). Also: the bookmarks as global actions that work closed (`145` extended); the
decoration's accent from the window's palette and a bar that grows with the title font; NVML
started on a worker at plugin load (its first call measured 26 ms on the owner's card, on the
compositor thread at the first open; a reading is 0.1 ms); and the fixes from two read-only reviews
of the newest code: ten in the Canvas Map (a label or tray click did two actions, a screen's frame
drag moved the pointer's screen, separate cameras lost a dropped window, open-canvas go/bring on a
minimized window only restored it, closed cluster numbers disagreed with the next open's, minimized
windows listed twice, no drag cancel, the zoomed map drifting on readings, the search missing the
tray, the pager's wheel) and eight in the far fly (a fly
outliving its slide under a swipe or a grasp, floats shrinking in a fly, an activation mid-fly aimed
from the zoomed-out camera, a map drop during a slide written against the old view, extreme
distances racing at the zoom floor, vertical and diagonal jumps under-flown, the fall-through slide
at the fly's zoom, the toggle chord mid-fly entering instead of opening). Two more reviews, the
plugin and the keys, found and this round fixed: a CSD title-bar drag (Brave, Zed) in the open
canvas started a KWin move that the effects' filter starved (KWin's move-resize filter comes after
it), so the window followed the cursor after the close (the plugin now drives and ends it while the
canvas has the pointer); the idle swallowing a held button's release; a window's held key repeating
into the canvas; a canvas key's release (Space) forwarded to a window; the grasp overlay dropping a
live grab; forwarded events without their timestamps (`setTimestamp` was never called); Back held by
the plugin with the effect turned off; NVML's `call_once` still able to block the compositor on a
wedged driver (now a detached thread and a ready flag); QSaveFile's fsync on the compositor thread
for the ground's state file (now write-and-rename); and in the keys, the switcher stuck open by a
re-press during the enter's flight, a held Tab stepping six times a second, the card naming another
window than the release enters, a slide in the show's beat, the search's text reaching a window
when the probe answered late, a cluster digit leaving an old single pick in charge, the carry back
ignoring a later move, and separate cameras' closed walk and carry. Left: the release routed by the
nav mask at release rather than at press (needs a reconfigure mid-press), and the D-Bus surface
(any session client can call the plugin, as it can KWin's own scripting). The nest (2026-11-15, on
KWin 6.8.3) then found three bugs of this round's own, all fixed: the edge pan never ran (its live
flag and tick sat on an anonymous item while the frame and the timer read them off `view`: "Unable
to assign [undefined] to bool", `81`); the map's go did nothing (`mapGo` took a third parameter for a
screen, and the plugin's `invokeMethod` with two finds no QML function of three: the screen's go is
`mapGoOn` now, `224`); and the review's lease change (a release left a plain reader's lease running)
broke the documented rule that a widget's release stops the watching, so it is undone (`224`). And
four scenarios whose premise had rotted: `117` and `86` found the panel clock by the bright pixels
of a whole strip, and a `.desktop` file on the owner's ~/Desktop (the nest's folder view shows it)
made them click the icon (86 had been passing on that icon's menu), while the bottom strip's box ran
from the task bar's icons to the clock - `clock_box` (lib.sh) now asks Plasma where the panel and
its digital clock are; `143` switched to `org.kde.plasma.worldmap`, which no package ships (the
closed desktop itself read black), and uses Hunyango now; `230` read `undo=`, the commit stack,
where the open canvas's Ctrl+Z is the move history (it brings two windows now and checks that one
undo puts both back). Verified: `make unit` (logic 351, map layout 40, CLI 203), `make lint`, the
plugin builds without a warning, the map widget headless (no QML error; the zoomed view holds
across a reading; the search finds a minimized window), and the nest: the whole suite in two passes
(the first cut at 82 scenarios by a session end; 489 pass in the second, its twelve failures the
ones above), then every failed scenario again on the fixes (`81`, `86`, `117`, `143`, `224`, `230`:
0 fail), the ten two-output scenarios on a two-output nest (55 pass, 0 fail) and the three
decoration scenarios wearing the canvas decoration (22 pass, 0 fail; `135`'s close glyph skips, as
ever: the nest's KWin cannot close a window). `123` failed once under a load average of 25 (the fidelity ladder
stepped down and its toast reached the golden) and passed on the rerun. Not verified: the 240 Hz
motion, which only the owner's monitor can show (`kwin-canvas perf` should read `ticks p50=4` in a
flight), and anything live.

**The map's screen rectangle (2026-11-14).** The owner asked whether it is inaccurate. The data is
not: every window the live map reads sits where KWin's own `getWindowInfo` puts it, to the pixel,
relative to the screen rectangle, and the installed effect's camera code is the repo's. What makes
the installed widget (Nov 5) wrong is staleness: it never holds the map, and the plugin installed on
Nov 12 stops watching a minute after the last read with no holder, so after a quiet minute (a game,
a still page) the widget never hears another change and keeps showing an old screen; `make install`
brings the widget that holds. In the new widget, two drawing faults were found and fixed: the window
sheets glided while the screen rectangle, the cards, the labels and the folds jumped (for a glide's
length after each change the windows sat off the screen rectangle), and a sheet's width was measured
from its gliding x, stretching it mid-glide. Every layer now glides together (`glideMs`) and sizes
from where it is going. Verified: a headless render at rest, mid-glide and settled shows all layers
in register; `224` in the hidden nest, 39 pass, 0 fail, no QML error. Not seen live.

**Far jumps fly (2026-11-14).** The owner: "the widget makes the windows teleport". Not installed
yet, so this was the Nov 5 widget and effect: a map click is `mapGo` or `mapFocus`, a closed slide,
and the slide's time was capped at 1.5 slides whatever the distance. The live Perf log had six
slides of 12 000 to 16 000 px in about 290 ms each (16:23 to 16:27), about four screen widths in a
third of a second at 1:1. Fixed in the effect for every far slide, not only the map's: `flyGo`
(`Logic.zoomPath`, van Wijk and Nuij's zoom-pan path) eases the quiet scene out until both ends are
in view, travels and lands at 1:1; short slides are unchanged; separate cameras keep the slide.
A window dropped on the map within a screen of where it was glides there (`glideReal`, the float
dodge's glide, now shared); a farther drop is written at once. `229` pins the fly. Verified:
`make unit` (logic 330, map layout 40, CLI 203), `make lint`, the plugin builds; in the hidden
nest, 22 scenarios (the fly, the map, the slides, perf, the animation factor, far stress, border
slide, moves, activation, the switcher, the graph, the echo, grasp, quality, frame authority):
234 pass, 0 fail, and `229`, `224` and `225` again on the final code, 62 pass, 0 fail. A fly
stretched to five seconds and shot mid-way: the desk shrinks to a card, the ground passes under,
and it lands at 1:1 (`arc=0.30` for 6060 px on the nest's 1920 px screen). Not seen live.

**Canvas Map rebuilt (2026-11-14).** The owner: the map widget "does not show all the clusters",
and needs "a huge revamp, transparency, blur, interactivity; move to windows by clicking". Found
live: the widget installed on Nov 5 never holds the map, and the plugin installed on Nov 12 sends
`changed` only to holders or for a minute after a read, so the old widget stopped hearing changes
after a quiet minute and froze on an old plane; `make install` brings the widget that holds. The
map itself was a to-scale picture: three clusters 10 000 px apart were small sheets with no
grouping, no names and no icons. Built: version 2 of the reading (`mapModel`: clusters numbered
as the canvas numbers them by `Logic.mapClusters`, apps, minimized windows, flags, game mode),
`mapAct` and the plugin's `act` (move, bring, minimize, above, close, cluster), and the widget
rewritten around `layout.js`'s squeezed ground: tinted cluster cards with labels, glass sheets
with icons (`AppIcons.qml`) or live PipeWire pictures (`Preview.qml`), drag to move, a drag of the
screen's frame to move the desk, a context menu, wheel zoom, search and keyboard, a tray for
minimized windows (on the ground, a far minimized window stretched the whole map), and a cluster
pager in a panel. In the nest, `224` passes all 39 checks with the v2 reading, `act`, the widget
on the desktop and no QML error in plasmashell's log. A headless render (the plain `qml` runtime, offscreen, no bus, synthetic
windows) found two bugs that would have kept the widget from loading at all: a cluster label's
`focus` role overrode Item's final `focus` (Qt 6.12 refuses), and `WindowSheet { view: view }`
bound the sheet's own empty property; it then drew the pager, the cards, labels, sheets, folds and
tray as designed, light and dark. Verified: `make unit` (313 logic, 40 map layout, 203 CLI),
`make lint`, the plugin builds, every new QML file parses and the map view and pager load and draw
with no QML error. Not seen live (not installed); the live pictures,
the icons from the task manager model and the panel popup are not verified anywhere yet.

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
  A proposal: a tray of the minimized windows' icons along the switcher's foot, as the Canvas
  Map's, stepped after the plane's windows; the pick restores and flies.
- The slide's 6 to 12% (measured at the nest's 60 Hz; on a 240 Hz monitor every slide, and now
  every open-canvas motion, pays it four times as often): most likely the `viewX`/`viewY` binding fan-out, twice per frame (two
  NumberAnimations) over every thumbnail, frame and chip on both views, plus the ground's ~100
  invisible items re-bound at 1:1 and the chrome's edge marks once the chrome has been built.
  The measurements that settle it: `perf record` on the nest's KWin over 50 slides; hot-reload
  ablation of the ground models, the marks' `quiet` gate and a single camera point; a per-slide
  `ticks=` on the Perf `slide` line. A plane `Item` with one transform per view is the
  architectural fix.
- The motion tick's 16 ms timer still runs for the whole open session (it starts motions); it
  could stop while nothing can move, with the gestures that start one kicking it.
- The harness: `kwinjs` should poll the log for its tag instead of a fixed settle and fail
  loudly; `arrange` should place every window and then size them so `heal_sizes` can go; the
  runner should trap INT/TERM and bound `spectacle`; a scenario with no checks should count as a
  failure; CI could build the plugin (`kwin cmake extra-cmake-modules` in `ci/packages.txt`).
- `main.qml` is 7k lines: the switcher, the graph, the frame authority and the search are each a
  block that could be its own QML object or JS library once the suite can prove a split moved
  nothing.
- Scenarios that leave the desk changed: the runner names each repair (`desk reset after …`).
  The thirteen named for "KCalc is not on top" were read from the state's entries, which closed
  are the last open's snapshot in the stacking of then, so the check saw the desk from before the
  arrange's own activations; it now reads KWin's real stacking (the state's `top=`). Whether any
  of the thirteen still leaves another window on top is for the next full run; `111`, which left
  KCalc at 900,300, ends with `arrange` now.
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
