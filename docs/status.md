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
read the rest's focus too early (the plugin restarted the hover clock on every
debug command; fixed in the plugin, `161` pins it), `107` pressed where a dock
is inferred to sit. The runner now also resets the activity, a
leftover panel and window sizes after every scenario and prints
`desk reset after NAME` for each, which a clean scenario never triggers; today those
lines still name `114`, `115`, `116`, `117` (KCalc and Gwenview 410 high), `120`
(432), `148` and `95` to `99` (Dolphin 368 to 370). Cause, found on 114 only:
`placeby` sizes go through the user-resize path, which snaps an edge to a
neighbour still standing at its old place (12 px), so `arrange` is not idempotent
on size; the others show the same signature and were not run (`docs/testing.md`).

**Not verified:** KZones, `sticky-window-snapping` and `rememberwindowpositions`
against the canvas (not in the nest); a Wallpaper Engine wallpaper in the nest;
the raise after a fly with focus-follows-mouse and no click-raise (reasoned from
the code; the nest raises on activation itself, so scenario `155` is only a guard).

**Installing.** `make install` is the only target that writes `~/.local/share`, the
copy the live session loads at login. Tests and the nest use `build/nest-data`
(`make nest-install`). The plugin in `/usr/lib/qt6/plugins/kwin/plugins` is
installed by hand with `sudo`.

## Next candidates

- Make `arrange` stop snapping against stale neighbours (place every window, then
  size them; tried on 114 and it held 420, not applied or run on the whole suite),
  then drop `heal_sizes`. Same guard as the hover clock for `setHoldDelay`, which
  restarts a running hold timer the same way (not shown to matter).
- A real Wallpaper Engine / KZones run, which only the desktop can give.
- The slide costs 6 to 12% of the main thread; where it goes is not known.
- The fly starts with the open (no warm-up turn). The first painted frame is
  the desktop's own picture; only the nest has checked there is no flash.

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
