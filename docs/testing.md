# Testing

The effect moves windows and grabs input, so a bad build in the live session is
a session you cannot use. Everything runs in a nested KWin first.

## The nest

`make nest` (`dev/nest.sh up`) starts `kwin_wayland --width 1920 --height 1080`
as a window of the live session, under `dbus-run-session` so it has its own
`org.kde.KWin`, its own `kglobalaccel` and its own portals, with
`XDG_CONFIG_HOME` pointed at a seeded config that enables the effect, gives it
two virtual desktops and disables Zoom and Overview. The live kwinrc is never
touched. It then starts `plasmashell` inside the nest and shapes it through
`org.kde.PlasmaShell.evaluateScript`: no panels, the Canvas Ground wallpaper,
a folder view on an empty directory. That is the same scripting call the
effect uses to publish the ground offset, so the handoff runs on every nest.

`NEST_NAME=foo` gives an independent nest with its own socket, bus, config and
log. Tests use `test`, the demo uses `demo`, and the default is `kwincanvas`.
`NEST_SHELL=0` skips plasmashell. `NEST_VIRTUAL=1` renders to KWin's virtual
framebuffer instead of a window — the test suite uses it, and `make play`
gives a window you can use. `NEST_PRELOAD=SHIM.so NEST_KWIN=BINARY`
runs BINARY with the plane-input shim preloaded and the pass-through plugin
off the plugin path (see below). `NEST_BORDERS=0,1,2,3,4,5,6,7` seeds every
screen border into the effect's `BorderActivate` instead of the default 7
(the top-left corner), the same numbers the Screen Edges page writes.
`NEST_OUTPUTS=2` gives the nest two outputs (`--output-count 2`), a frame and a
wallpaper haze layer each; `make test-two-outputs` runs the scenarios written for an
arrangement against one.

The nest seeds the motion knobs off - `SmoothZoom`, `PanInertia`,
`WindowPhysics` and `MovesGlide` - so a scenario measures the canvas and not
the spring: every drag lands exactly where it was put, every camera move
arrives at once, and every layout write is found at its landing. `94-physics`
turns them on and measures them.

```bash
make play                       # up, fixture apps arranged, canvas open and fitted
make play ARGS=--closed         # same, canvas closed at 1:1
make nest                       # up, empty
make nest-fixtures              # kcalc kwrite konsole dolphin gwenview on fixture files
make nest-clients               # or the plain trio: kcalc konsole kwrite
make nest-cmd CMD=open          # a debug command
make nest-shot                  # spectacle against the nested compositor
make nest-log
make nest-down
make nest-clean                 # leftovers of nests whose state is gone
```

`dev/nest.sh` is sourceable: `source dev/nest.sh` exposes `up`, `down`, `run`,
`cmd`, `shot`, `input`, `fixtures` and the rest without running anything,
which is how `tests/lib.sh` reuses it. `js 'CODE'` runs a KWin script in the
nest and returns the lines it passes to `out()`; `probe NAME` launches a
probe window titled `Probe NAME` that logs every press, release and key it
receives, with surface-local coordinates, to `$STATE/probe.log`, and opens
a menu on a right press. Everything that talks to the nest takes the
nest's bus from `$STATE/bus` and fails when it is missing: an empty
`DBUS_SESSION_BUS_ADDRESS` would fall back to the live session's bus. The
nest's own D-Bus daemons see only the nest's Wayland socket.

A nest never competes with the live session on equal terms. Everything it
runs (compositor, bus and daemons, plasmashell, clients, probes) starts
under `nice -n 10 ionice -c3`; `/usr/bin/kwin_wayland` gives its threads
SCHED_RR through its file capability, so `up` moves the nest's compositor
back to SCHED_OTHER. `fixtures` and `clients` launch one app at a time,
each waiting (up to 10 s) for its window to map before the next. The nest's kded does not load its
GTK module, which writes `$HOME/.gtkrc-2.0` whatever `XDG_CONFIG_HOME` says
and so makes the live session's kded reload its xsettings. Everything
the nest runs gets the nest's XDG config, state and cache homes under
`$STATE`, and the compositor and its bus the nest's data home too. Clients
keep the user's data home, since the goldens depend on it (Dolphin's view
properties), so a fixture app still writes its own data there: KWrite's
anonymous session, Gwenview's recent folders.

## Driving the effect

Two channels, both from the shell.

**Debug commands.** QML effects cannot export D-Bus, so the harness writes a
command and a sequence number into the nest's kwinrc and calls
`org.kde.kwin.Effects.reconfigureEffect`. The effect runs the command when the
sequence changes and logs its state.

```bash
make nest-cmd CMD=open
make nest-cmd CMD="pan -1500 -400"        # screen px
make nest-cmd CMD="zoom 0.4 960 540"      # zoom [anchorX anchorY], global px
make nest-cmd CMD=extents
make nest-cmd CMD=commit
make nest-cmd CMD="frames 300 0 1"        # move activity index 1's frames by screen px
make nest-cmd CMD="place 2 2300 100"      # set entry 2's canvas position
make nest-cmd CMD="placeby KCalc 100 120 480 420"   # by caption, with optional size
make nest-cmd CMD="resize 0 1000 700"     # command entry 0's window to a size
make nest-cmd CMD="activate KCalc"        # by caption substring, at 1:1
make nest-cmd CMD="shift 2200 900"        # move the current activity's viewport at 1:1
make nest-cmd CMD="activity 1"            # switch to activity index 1 (asynchronous)
make nest-cmd CMD=addactivity             # add an activity, named by count
make nest-cmd CMD="rmactivity 2"
make nest-cmd CMD="hide 1 0"              # hide activity 1's frame on screen 0; show puts it back
make nest-cmd CMD=activities              # raw activity ids and each window's list
make nest-cmd CMD=resetview               # 1:1 only: forget the pan so canvas == frame
make nest-cmd CMD=list                    # every window with its frame and activity
make nest-cmd CMD=cancel
make nest-cmd CMD="locate In"             # log the global centre of the toolbar control labelled In
make nest-cmd CMD="verbose on"            # every decision the canvas takes, into KWin's log
```

Each command prints the effect state afterwards: `visible`, `zoom`, `view`,
the current activity, every activity's target (and hidden outputs), and
every entry's canvas rect, frame and activity.

`verbose on` (or the `Verbose` knob) turns the effect into its own witness:
every decision lands in KWin's log as a `[canvas]` line - `open`, `commit`,
`cancel`, the hold's branches, the map's sheet clicks - each with the zoom,
view, quiet and grasp state it left behind, and the pass-through plugin's
matching `canvas-passthrough:` lines for the hold, the hover and the click
replay. A failing scenario is a `grep '\[canvas\]'` away from the exact call
sequence and end state; `make nest-log` tails the nest's log, `journalctl`
the live session's.

The same channel works against the live session, so a change can be checked
without a nest. The effect logs its state to the journal rather than to a file
there, so read it with `journalctl`, and the installed CLI is the shortest way
in:

```bash
kwin-canvas status      # the effect is loaded, and whether the plugin answers
kwin-canvas open        # nest-cmd open, in the live session
journalctl --user -b _COMM=kwin_wayland --since "1 min ago" | grep "kwin-canvas state"
```

A QML edit is not picked up this way — `make reload` reconfigures the running
effect, and unload/load reload the component KWin compiled at login (see
"Things that cost time"), so a new `main.qml` needs a new Plasma session. The
settings form is read by System Settings when it opens, so a new `config.ui`
appears at once, but the effect only learns a new key when its QML is new.

**Real input.** `make tools` builds `build/tools/fakeinput`, a small C client
for KWin's `org_kde_kwin_fake_input` protocol. `dev/nest.sh input` runs it
against the nest:

```bash
./dev/nest.sh input move 960 540
./dev/nest.sh input wheel -3                       # three notches out
printf 'drag 300 300 600 500\n' | ./dev/nest.sh input   # left-drag, 20 steps
./dev/nest.sh input key esc
```

Commands: `move X Y`, `rel DX DY`, `down|up|click [left|middle|right]`,
`drag X1 Y1 X2 Y2 [STEPS] [MS]`, `wheel N`, `key NAME [down|up]`, `sleep MS`.
KWin only advertises the protocol to registered executables, so the nest runs
with `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1`. Against a live session you would
need `make -C tools desktop`, which registers the binary with a desktop file
in your home directory.

## Tests

```bash
make test                 # all scenarios
make test ARGS=60         # scenarios matching a pattern
make test-two-outputs     # NEST_OUTPUTS=2, the 91 scenarios (91-two-outputs, 89)
make test-two-outputs ARGS=--update-golden   # re-record 91's golden
make test-panel           # NEST_PANEL=1, the panel scenarios (86-panel-popup, 117-dock)
make golden               # re-record the golden screenshots
```

`make test-panel` runs the two panel scenarios (86-panel-popup, 117-dock)
against a nest whose plasmashell grows a bottom panel with the digital
clock, the only place an applet's dropdown - a popup - is representable.
86's camera asserts are the regression; its popup-premise check skips when
plasmashell's popup does not render in the virtual nest, and the skip says
so rather than pretending. 117 is the dock's own proof: the dock and its
applets keep their pixels, and no click, hover or rest on them may focus
the window beneath or fly the canvas.

`tests/run.sh` starts the `test` nest, launches the fixture apps, arranges
them at fixed canvas positions with `placeby`, then sources each
`tests/scenarios/NN-name.sh` and calls its `run_scenario`. Scenarios use
`tests/lib.sh`:

- `c "command"` sends a debug command and keeps the state it printed.
- `sget zoom|viewx|viewy|visible|activity|entries|nactivities|screens|backdrop|cam|draglag|lean`
  reads the state line: `screens` is the output count, `backdrop` the number of
  wallpaper haze layers the plane is drawing (one per output in wallpaper mode,
  none in grid mode), `cam` `goal` or `glide` while the
  camera moves, `draglag`/`lean` the weight a dragged window is wearing.
- `eget CAPTION x|y|w|h|fx|fy|activity|index` reads an entry by caption substring.
- `tget INDEX x|y|name|hidden` reads an activity target.
- `screenrect INDEX` prints an output's `X Y W H`, `screenname INDEX` its name.
- `setcfg KEY VALUE` writes an effect config key and reconfigures the effect
  (the same path `set_borders` uses), so a scenario can flip one knob - a
  motion knob, `Backdrop`, `BorderZoom` - without restarting the nest. It ends
  its options with `--`, because `kwriteconfig6` reads a value that starts with
  a dash as a flag. Undo a key the way the settings page does:
  `kwriteconfig6 ... --key KEY --delete`.
- `assert_eq`, `assert_near NAME ACTUAL EXPECTED [TOL]`, `assert_true`.
- `snap NAME` screenshots the nest and compares against `tests/golden/NAME.png`
  by normalized RMSE, within `GOLDEN_TOLERANCE` (default 0.03). With
  `UPDATE_GOLDEN=1` it records instead. Diffs land in `build/test/NAME.diff.png`.
- `assert_differs NAME A B [MIN]` compares two shots `snap` already took: the
  two have to differ by at least MIN (0.01) of normalized RMSE, for a setting
  that has to change the screen where a golden would only pin one of them.
- `input ...` injects real events; `have_input` says whether the tool is built.
- `set_borders LIST` writes `BorderActivate` and reconfigures the effect, which
  is what makes a new list of borders take effect (7 is the top-left corner).
- `push_border N` pushes the pointer into border N the way KWin wants it and a
  hand does: one motion event on the border's own pixel, `ElectricBorderDelay`
  (75 ms) later a second one that lands back on it, and nothing after that -
  a push that keeps going past `ElectricBorderCooldown` (350 ms) fires the
  border twice and the second toggle enters the location. A glide that stops
  on the pixel leaves one event there and never fires. `push_border_on N X Y W
  H` does it on an output that is not at the origin, which is what a corner on
  the second output needs.
- `kvm_drop_on_border N` places the pointer on border N's pixel and then takes
  it away, the way a KVM switch hands the machine over, and never fires.
- `arrange` restores the fixed fixture layout.

`tests/run.sh` takes `SCENARIOS=DIR` to run another directory of scenarios.

## What CI checks

`.gitlab-ci.yml` runs in an `archlinux:latest` container, which has no
compositor, so it holds the checks that do not need one and skips the rest
rather than pretending they passed. Six check jobs are the six parts of
`make lint`, and a seventh, `unit`, runs `make unit` (needs `diffutils`), so a
red pipeline reproduces here:

```bash
make lint            # lint-reuse, lint-qml, lint-shell, lint-deadcode, lint-python
make lint-reuse      # reuse lint: copyright and licence metadata (REUSE 3.3)
make lint-qml        # every .qml file, failing on a [syntax] warning
make lint-shell      # bash -n on every script, then shellcheck at error severity
make lint-deadcode   # the dead-code census (tools/deadcode.sh)
make lint-python     # vulture over the Python (tests/fixtures/gen.py)
make unit            # logic.test.js in node, cli.test.sh (doctor and perf) in bash
```

Shellcheck reads `.shellcheckrc` for the standing policy: the shell is bash
(the scenarios are sourced fragments with no shebang), and SC2046 is off -
the word splitting in `dev/nest.sh`'s command assembly is the point. The gate
is error severity, so the deliberate warnings print without failing.

The census is the QML dead-code graph by hand, since no graph tool parses
QML: every function, property, signal and id in `main.qml` (plus the logic.js
exports, the scenarios' helpers and the plugin's file-local helpers) must be
referenced somewhere beyond its own declaration, or the check fails. graphify
covers the bash surface and agrees, but its grammar list has no QML.

`reuse lint` reads the headers in the files, plus `REUSE.toml` for the PNGs, the
JSON and XML KWin parses, `VERSION` and the text fixtures. `qmllint` returns 0
for everything by default and an unresolvable import is expected off KDE, so the
QML job fails only on a `[syntax]` warning, and it calls
`/usr/lib/qt6/bin/qmllint` by path because the Qt5 build in `/usr/bin` answers
to the same name. The build job runs `make tools` and `make fixtures` and then
`git diff` on `tests/fixtures`, so the committed fixtures have to match the
generator.

The scenarios, the demo, the plugin and the shim stay local: they need a
nested KWin with real windows and virtual outputs, or KWin's headers to build
against. `make test`, `make test-two-outputs`, `make test-shim`, `make golden`
and `make plugin` are those commands, and `dev/deps.sh` prints the packages
they need.

## Plane input under the shim

```bash
make test-shim            # tests/shim/*.sh under the preload shim
make test-shim ARGS=--keep
```

`tests/run-shim.sh` builds the shim (`dev/spike/preload/nest-preload.sh
build`: `shim.so` against KWin's headers, and a capability-free copy of
`kwin_wayland`, since the file capability on the real binary makes ld.so
drop `LD_PRELOAD`), then runs `tests/run.sh` with `NEST_NAME=shim`,
`NEST_PRELOAD` and `SCENARIOS=tests/shim`. It prints a skip line and exits 0
when the installed libkwin is not the build the shim was written for, or
the shim does not build. The shim scenario drives two probe windows with
real input while the canvas is open at zoom 0.5: clicks reach the windows at
their drawn positions with the right surface-local coordinates, inside and
outside the output, focus and keys follow, title-bar, tag and toolbar
gestures stay the canvas's, the cursor is drawn at the screen point, the
chord and the hot corner exit, closing clears the transform, twenty cycles
leave KWin stock, and unloading the open effect clears it too. The popup
scenario opens the probe's menu (an xdg_popup, magenta) and submenu (cyan)
with real input at zoom 0.5: each is drawn at its real geometry over the
windows, found by pixel colour in a screenshot, a click on an item reaches
the app, a click on the ground or the toolbar closes an open menu and does
nothing else, and the menu of a window outside the output opens beside it.
`make test` runs without the shim.

The spike's own gates (`dev/spike/preload/test.sh`, 16 checks with the
effect unloaded and the transform from `$XDG_RUNTIME_DIR/kwin-canvas-preload`)
run in the `preload` nest, which sets `KWIN_CANVAS_PRELOAD_FILE=1`.

The fixtures are procedural (`tests/fixtures/gen.py`): a wallpaper with
labelled quadrants, a seamless tile, and two text files. The fixture apps open
them so every run shows the same content. Konsole runs `cat` on a fixture
instead of a shell, so no prompt or clock changes between runs.

Golden images are captured on this machine's fonts and theme. Re-record them
with `make golden` after an intentional visual change, and expect to
re-record after a Plasma upgrade.

## Demo

`make demo` runs `demo/demo.sh` in the `demo` nest: fixtures, then a scripted
session driven by fake input while a background loop screenshots the nest,
with named stills at each stage. `ffmpeg` assembles `build/demo/demo.mp4` and
`demo.gif`. `make video` re-assembles from existing frames. For a real-time
recording, point OBS at the nest window while `DEMO_FRAMES=0 make demo` runs.

## Things that cost time

- **The full suite flakes under GPU pressure, and the failing set differs
  per run.** A scenario that passes alone, in its batch and in a clean full
  run can fail when the machine's VRAM is exhausted by leftover nests (a
  crashed nest's compositor keeps its buffers): the failures were 8 px frame
  offsets, a stale caption, then 40 failures one run and two the next. `make
  nest-clean`, a reboot, and judging by the named scenario batches rather
  than a full-suite run are the workaround; a full-suite failure that does
  not reproduce as a named scenario or a pair is not a code regression.
  Each scenario also leans on the desk it finds, so the order matters: a
  stray window or a scrolled client fails the next checks - one full run's
  golden diffs (30, 50, 60, 61, 93, 123) were window content and a panel
  label while the frames and the ground matched. `make test ARGS=<name>`
  is the arbiter: green alone means the desk, not the code. Never re-record
  a golden from a suite shot. (The known polluters 109, 10-open and 96 now
  restore or arrange before they end.)
- **The runner resets the desk after every scenario, and says so.** Besides
  the settings, remembered state, pointer and layout, `desk_reset` in
  `tests/run.sh` puts back what an arrange cannot: the current activity (the
  first), any extra activity, an open canvas, the panel count (plasmashell
  shaped again by `shell_shape`) and the windows' sizes (`sizes_off`). Each
  correction prints `desk reset after NAME: ...` under the scenario that needed
  it, so the offender is named instead of found by bisecting; a clean run prints
  none, and a scenario that prints one is a bug to fix at its source. Windows
  other than the five fixtures, floats, popups and menus are reported the same
  way but not removed. The leaks it closed, for the record: `113-thread-duck`
  activates windows it had committed into Activity 2's frame, KWin switches to
  that activity, and the next scenario's `arrange` (`resetview` acts on the
  *current* activity) pulled Activity 2's target onto Activity 1's, which
  tinted every frame wrong from 20 to 61 and made 60 and 95 meet "Activity 2";
  `117-dock`, `149-dock-approach` and `86-panel-popup` seed Plasma's default
  layout for its clock, which swaps every wallpaper for Plasma's own and adds a
  panel (123 drew that); `159-float-close` ran `fixtures` to replace one closed
  KCalc and added three windows to every desk after it. Sizes drifted too, and
  `sizes_off` / `heal_sizes` mend that: after `114-overlay-map` (alone, twice,
  the same each time) the next `arrange` leaves KCalc and Gwenview 410 high
  instead of 420, and `heal_sizes` asks for 400 first, then arranges. Cause,
  found on 114 by logging `requestSize`: `placeby NAME X Y W H` goes through
  the same `requestSize` as a user's resize, which snaps the dragged edge to any
  other entry's edge within `SnapDistance` (12 px). `arrange` places the five
  one after another, and after 114's release Gwenview still sits at its old
  place (610,110, bottom edge 530) when KCalc is placed, so KCalc's bottom at
  540 snaps to 530 and the request is 410; Gwenview then snaps to KCalc's new
  bottom the same way. That is a fixed point: two windows with the same top
  and 10 px of difference snap each other to it, so the next `arrange` repeats
  it. The effect does what it was built to do for a user's resize; the fault is
  `arrange` feeding it stale neighbours. Placing every window first
  (`placeby NAME X Y`) and sizing after left 114 at 420 (one run, tried and
  reverted, not applied: it changes the start of every scenario and needs a
  whole-suite run). Not run: that 120 (432, which is 420 plus 12), 148 and
  95 to 99 (Dolphin 368 to 370) are the same cause. They have the same
  signature (a size within 12 px of a neighbour's edge), nothing more.
- **The runner's tallies survive a scenario that sources `tests/lib.sh`.** Many
  scenarios begin with `source tests/lib.sh`, and `PASS=0; FAIL=0; SKIP=0` there
  zeroed the counts, so the closing `== pass N fail M` covered only what ran
  after the last such scenario, and the exit status forgot every earlier
  failure: a full run printed `fail 0` under a `FAIL` line, 266 passes for 653
  `ok` lines. Earlier full-run totals in the docs and in commit messages were
  low by that much; count the `ok`, `FAIL` and `skip` lines when in doubt.
- **A debug command is a settings write, and a settings write restarts the
  plugin's hover clock.** Every `c ...` reconfigures the effect, which publishes
  `HoverDelay` again, and `QTimer::setInterval` restarts a timer that is
  running. Polling `c state` inside the 900 ms after a pointer move therefore
  starves the rest. The plugin now leaves a running clock alone when the
  published delay is unchanged (`setHoverDelay`, `plugin/passthrough.cpp`), and
  `168-hover-clock` pins it: it polls `c state` ten times during a rest and
  failed before the guard (focus never landed) and passes with it. Even so the
  rest's focus lands 1.5 to 1.9 s after a pointer move here (polled with the
  guard in, so not starvation), later than the 900 ms delay alone suggests, so
  a read at 1.2 s is early (111 read there and failed the same 3 checks in
  the one run tried, with the guard in). Wait quietly past that, with no `c` calls in the wait,
  then read once (111 waits 2.5 s). Polling for it is now safe only because of
  the guard; `setHoldDelay` has the same pattern and no guard.
- **A hold read has a deadline.** The debug channel's round trip is about 0.3 s
  here, so a read that follows several commands lands later than the sleeps
  suggest; give an injected hold ample time past the read (115's click came at
  1.66 s and the read at 1.75, and read the landing flight's zoom).
- **The pointer is where `arrange` left it, the screen corner, and a panel
  covers it.** Under `make test-panel` a press with no move first is inferred
  to land on the dock, which would own it (not measured: 107's hold never
  started there, and starting it from bare ground fixed that, which is
  consistent with the dock but does not show where the press went). Put the
  pointer on bare ground in the same injector stream (107).
- **Never edit what the running suite reads.** `tests/run.sh` sources each
  scenario as it reaches it, and bash reads a script lazily as it executes:
  editing `run.sh`, `lib.sh` or a scenario while a run is in flight can shift
  the byte offsets under the reader and abort the run with a bogus syntax
  error ("syntax error near unexpected token") at an innocent line. The
  effect's own files are safe - `make -s install` snapshots them once, before
  the loop, so a mid-run edit never reaches the nest of that run - but a
  script the runner is still reading is not.
- **The ScreenCast portal on a virtual nest streams one stale frame.** KWin's
  `--virtual` output presents the scene on damage, and the pipewire stream a
  ScreenCast session hands out repeats its last buffer: a recorder that
  negotiated 30 fps gets 30 fps of the same picture while the scene visibly
  changes (the Screenshot portal renders on demand and does reflect it). The
  KDE portal backend also needs the nest to declare `XDG_CURRENT_DESKTOP=KDE`
  (see `dev/nest.sh`), or the broker picks the GTK backend and hangs; and its
  screen-sharing dialog is a KWin overlay with no window id, so there is
  nothing to click programmatically but the pixels. `make demo` therefore
  stays on the screenshot loop.
- **Output goes to journald**, not stderr, when stderr is not a TTY. The nest
  sets `QT_LOGGING_TO_CONSOLE=1` so `kwin.log` gets it.
- **The state block is matched by shape.** `state()` in `dev/nest.sh` reads the
  effect's one message as the line that names it plus every indented line that
  follows, so a new kind of indented line in `logState()` needs its shape added
  there. An `awk` bracket expression is not an alternation - `[\[{]` matches a
  backslash or a brace - which is how the block came to stop at the first
  `  screen[` line and leave `eget`/`tget` nothing while `sget` looked fine.
- **The QML component cache.** `unloadEffect` and `loadEffect` reload the
  component KWin compiled, not the file, and that is true in the live session
  as it is in a nest: `make reload` cannot pick up a `main.qml` edit, and
  clearing `~/.cache/kwin/qmlcache` does not either, since the cache is
  KWin's own QML engine. `make nest-reload` restarts the nest; the live
  session needs a new Plasma session. The exception: the scene tree lives in
  `ui.qml`, loaded through a version-stamped URL, so `make hot` (install +
  a `HotRev` bump + a reconfigure) recompiles the scene in the running
  session - the engine treats the new revision as a new cache key. That
  stamp reaches `ui.qml` alone, though: a component it instantiates by
  path (`Ground.qml`) keeps the compilation of its own unversioned URL,
  so a fixed component file still resolves to the old, broken compile -
  `Type Ground unavailable` keeps appearing and the canvas draws black -
  until KWin restarts. The effect's logic stays in `main.qml` and still
  needs the restart; the proof is the `kwin-canvas ui: loaded` line
  appearing twice in KWin's log without one. A config-only change needs
  no restart:
  `reconfigureEffect` is enough.
- **Socket name.** The Wayland socket lands in `$XDG_RUNTIME_DIR`, so it must
  not share a name with the harness state directory.
- **A window parked in another activity is pulled to the screen's edge unless it is written
  in two steps.** Giving a window other activities makes KWin move it, a few milliseconds
  later, to keep 100 px of its width on a monitor, and opening or closing the canvas does the
  same to the windows of the other activities. A scenario that parks one by a script
  (`183`, `184`) sets `w.activities` in one `kwinjs` and writes the frame in the next; one
  that parks it with `placeby` and `commit` gets the canvas's own correction (`182`). The
  symptom in a trace is a plane x that is 20 px short, or a frame that is not the one
  written, and the Perf log's `pulled ... cause=` lines name the trigger.
- **A JS exception mid-commit leaves the effect open.** Check the log for
  `TypeError` before trusting a `visible=true` in the state line.
- **Cursor-anchored zoom does not reset the camera.** `zoom 0.4 960 540` from
  an already zoomed view keeps the point under the anchor fixed. Use `home`
  first when a scenario needs a known camera.
- **The camera animates.** `open`, `origin`, `home`, apply and a zoom all move
  the view over a few frames, so a `view` read taken right after is mid-flight
  and any delta measured from it is wrong (this reads as a wild pan, or as no
  pan at all). Poll `state` until the view stops changing before taking a
  baseline. `open` at the default `OpenZoom` then `origin` settles at 1:1 with
  the view at (0,0). With the motion knobs off in the nest a camera move lands
  in the frame that asked for it, so a scenario that wants a known camera only
  has to `home` or `origin` first and read it once; `94-physics` turns
  `SmoothZoom` on, where the same read lands mid-flight on purpose and the
  `cam` field says so.
- **A held button wants a client that stays alive, and a drag wants motion
  events.** A press sent a few milliseconds before the injector exits can be
  lost (`sleep` is milliseconds, so `sleep 5` is not a hold), and a gesture
  written as one jump is not a drag: `glide X Y 1 1` sends a single motion
  event and the view does not move at all, while `glide X Y 10 20` pans by the
  full delta. `printf ... | input` runs the injector in the foreground and
  blocks until its stream ends, so `sleep 0.5; c state` after it is a read
  *after* the release, not during the hold. To read the state while a button is
  still down, background it (`printf ... | input &`) and give the stream a long
  tail, because the injector exiting is itself a release: without one the effect
  sees the button lift and settles whatever the hold was showing (a dragged
  window's weight, a pan's glide) before the state is read.
- **Daemons outlive the bus.** Portals and kactivitymanagerd activated on a
  nest's private bus keep running after it dies. `down` kills everything on
  the nest's bus; `make nest-clean` sweeps the rest.
- **The nested window must keep its size.** KWin's nested backend scales its
  framebuffer to the window instead of changing the output mode, so resizing
  the nest window on the outer desktop distorts it. Leave it at the invoked
  size, or set `NEST_WIDTH` and `NEST_HEIGHT` before `make nest`.
