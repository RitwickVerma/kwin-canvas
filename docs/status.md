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

**The suite is not green.** Last full run (`make test`, nest isolated): pass 240,
fail 25, skip 2, no `TypeError`. `111-thread-z` and `115-stress` fail for their own
reasons; the rest (from `20-zoom-pan` on) follow one leak that is not explained:
`113-thread-duck` then `20-zoom-pan` renders the frame tints differently, with the
activity, windows and view all normal. Every other leak was found with
`SCENARIO_LIST="a b c" tests/run.sh` and fixed (a setting left on, a stacking order,
a tour anchor, a held float picture), and the runner now restores settings,
remembered state, layout and pointer after every scenario.

**Not verified:** KZones, `sticky-window-snapping` and `rememberwindowpositions`
against the canvas (not in the nest); a Wallpaper Engine wallpaper in the nest;
the raise after a fly with focus-follows-mouse and no click-raise (reasoned from
the code; the nest raises on activation itself, so scenario `155` is only a guard).

**Perf trace.** The `Perf` knob (off by default, free when off) writes `kwin-canvas
perf: EVENT key=value` lines to the journal: `open`, `first-paint`, `settle`,
`slide`, `hover-fetch`, `ticks` (format in `architecture.md` → *Motion*). Scenario
`161-perf` checks it, and that off writes none. With it, the open's 150 to 200 ms
before the first tick was taken apart in the nest: about half is KWin building a
fresh `QQuickWindow` and `QRhi` for the scene on every open, a quarter is
instantiating `ui.qml` (spread thin, no one section above noise), a quarter is the
first frame. None of it is reachable from QML without keeping the scene running, so
the stall is left as it is. Nest timings, not the desktop's.

**Installing.** `make install` is the only target that writes `~/.local/share`, the
copy the live session loads at login. Tests and the nest use `build/nest-data`
(`make nest-install`). The plugin in `/usr/lib/qt6/plugins/kwin/plugins` is
installed by hand with `sudo`.

## Next candidates

- Explain the `113` then `20` leak and bring the suite to green.
- `111-thread-z` (three checks, since `273f9e7`) and `115-stress`.
- A real Wallpaper Engine / KZones run, which only the desktop can give.
- The slide costs 6 to 12% of the main thread; where it goes is not known.
- The fly starts with the open (no warm-up turn). The first painted frame is
  the desktop's own picture; only the nest has checked there is no flash.
- The open's first tick comes 150 to 200 ms after `open()`. Read `kwin-canvas perf:
  first-paint` on the desktop (`Perf` knob) to see whether it is the same there; if
  it is, only a smaller scene or a KWin change would shorten it.

## The fork

`main` is a fork of [`aaronsb/kwin-canvas`](https://github.com/aaronsb/kwin-canvas)
(remote `upstream`, GPL-2.0-or-later). `origin` is the GitLab fork
(`git@gitlab.com:ritwick7/kwin-canvas.git`) and is pushed. `make release`, `make aur`
and `make aur-passthrough` publish to upstream and are not ours to run. The fork's
own work is `git log --oneline upstream/main..HEAD`.

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

## Sessions

Older session logs, newest first, are in [status-archive.md](status-archive.md).

## How to keep this file

Date your entries, delete what is no longer true instead of stacking a new version
on top, and do not let it grow into a second `architecture.md`: the model belongs
there, the traps belong in `testing.md`, and what a user sees belongs in
`release-notes.md`.
