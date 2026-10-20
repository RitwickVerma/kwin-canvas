# Where the work stands

The state file for whoever picks this up next, a person or an agent. It is the one
document here that is allowed to go stale: update it when you stop, rewrite what is
no longer true rather than appending, and keep it short. The model is in
[architecture.md](architecture.md), the harness in [testing.md](testing.md), and
what a user sees in [release-notes.md](release-notes.md).

## Where it stands (2026-10-15)

Everything below was measured in the hidden nest (`NEST_VIRTUAL=1`) and, for what
is marked seen live, on the user's desktop after a relogin ("looks sexy", "pretty
tight").

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
and offset as the owner's are.

**Window coordinates drifting, the main cause (2026-10-20).** KWin moves a window toward the screen
when its focus changes, and the canvas absorbed that as a plane move (`docs/architecture.md`, *KWin
nudges a window when its focus changes*; scenario `204`, which fails on the previous code for the
two fly cases and passes now; its overview and hover cases pass either way). Reproduced in a nest at
scale 1.25, where windows laid out for 1920x1080 are partly off the smaller screen. Not checked on the
desktop; the `nudged` Perf lines will show it.

**Window coordinates drifting.** Two causes found and fixed: a floated window rode to a screen
edge on every slide (`178`), and KWin pulled parked windows back inside whenever its work area
changed (`180`, `181`; `docs/architecture.md`, *KWin pulls parked windows back inside*). Neither
is checked on the desktop yet; the `pulled`, `bounced` and `moved` Perf lines will show whether
anything else moves windows.

**Known failing, unexplained.** `112-overlay` fails one check ("the drag never grabbed
the window": Gwenview at x 3980, expected 4000) every time it runs alone, with and without
the arrange fix, and passes inside the full run. A trace shows the entry's x reading as 1400
early in the hold and 3980 later, so the coordinates shift under the quiet hold; not traced
further. `126-grasp-landing` failed one check intermittently and passed 3 of 3 later.

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
per-open cost is left as it is: that it cannot be avoided without keeping the
effect started is reasoned from the KWin API (a started effect draws the
full-screen scene, which would break direct scanout), not tried. Nest timings,
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
