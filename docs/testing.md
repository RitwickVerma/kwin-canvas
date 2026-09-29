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
wallpaper tile each; `make test-two-outputs` runs the scenarios written for an
arrangement against one.

The nest seeds the motion knobs off - `SmoothZoom`, `PanInertia` and
`WindowPhysics` - so a scenario measures the canvas and not the spring: every
drag lands exactly where it was put and every camera move arrives at once.
`94-physics` turns them on and measures them.

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
```

Each command prints the effect state afterwards: `visible`, `zoom`, `view`,
the current activity, every activity's target (and hidden outputs), and
every entry's canvas rect, frame and activity.

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
make test-two-outputs     # NEST_OUTPUTS=2, the 91 scenarios (91-two-outputs)
make test-two-outputs ARGS=--update-golden   # re-record 91's golden
make golden               # re-record the golden screenshots
```

`tests/run.sh` starts the `test` nest, launches the fixture apps, arranges
them at fixed canvas positions with `placeby`, then sources each
`tests/scenarios/NN-name.sh` and calls its `run_scenario`. Scenarios use
`tests/lib.sh`:

- `c "command"` sends a debug command and keeps the state it printed.
- `sget zoom|viewx|viewy|visible|activity|entries|nactivities|screens|backdrop|cam|draglag|lean`
  reads the state line: `screens` is the output count, `backdrop` the number of
  wallpaper tiles the plane is drawing, `cam` `goal` or `glide` while the
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
  by normalized RMSE, within `GOLDEN_TOLERANCE` (default 0.02). With
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
rather than pretending they passed: `reuse lint` for the copyright and
licensing metadata (REUSE 3.3 — the headers in the files, plus `REUSE.toml`
for the PNGs, the JSON and XML KWin parses, `VERSION` and the text fixtures),
`qmllint` on every `.qml` file, `bash -n` on every script, `make tools`, and
`make fixtures` followed by a `git diff` on `tests/fixtures` so the committed
fixtures have to match the generator. `qmllint` returns 0 for everything by
default and an unresolvable import is expected off KDE, so the QML job fails
only on a `[syntax]` warning, and it calls `/usr/lib/qt6/bin/qmllint` by path
because the Qt5 build in `/usr/bin` answers to the same name.

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
  session needs a new Plasma session. A config-only change needs no restart:
  `reconfigureEffect` is enough.
- **Socket name.** The Wayland socket lands in `$XDG_RUNTIME_DIR`, so it must
  not share a name with the harness state directory.
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
