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

### 2026-10-13 — a static audit from outside the nest

Written without a nested KWin, then verified in one. `make lint` is green,
`make plugin` compiles the C++ edits clean (no warnings), and the scenarios that
touch them pass alone after `make nest-reload`: `106` 8/0, `124` 9/0, `125` 5/0,
`127` 6/0, `129` 10/0, `137` 11/0, `85` 21/0, `87` and `88` 2/0 each. The
full suite gave pass 253, fail 15, skip 2 with no `TypeError` in the log.
Ten scenarios failed alone with the same counts on a clean `HEAD`, and every
one had a cause (fixed in the next commit): `5328642` made `publishGround`
wait on a plasmashell query that always answered empty (`evaluateScript`
returns what the script `print`s, not its last expression), so the wallpaper
never received the camera or the knobs (`128`, `115`); `80a7231` took the haze, dim
and veil out and re-recorded two goldens, leaving `60`, `61`, `80`, `90` and
`123` on stale goldens and `93`/`133` asserting a dim that is gone; `114`
sampled the hint strip 40 px above where it is, which the old haze hid.
After those fixes the full suite gave pass 254, fail 11, skip 2 (no
`TypeError`), and each of the 13 scenarios that failed in it passes alone
(`103 115 123 127 129 131 30 50 60 61 81 93 97`): the suite-order flake, so
the baseline is now 254/11/2, not 256/12/2 (253/9/2 with three scenarios
added: `138-drag-glide`, `139-focus-activity`, `141-click-pan-close`).
Tests run hidden with `NEST_VIRTUAL=1`; only `make play` needs a window.
From the audit list: `dragRaw` cleared in `endDrag`, the click-pan timer
stopped on commit, cancel and slide end, `deskArea` clipped to the screen's
rectangle, the dead `farewellHide` fade branch removed. The focus-activity
case did not reproduce as a bug (139 pins it). **Dock approach (`149`, needs `make test-panel`): the hover's fetch stands back within 120 px of a dock. `107-overlay` fails one check under `test-panel` with or without that change (passes in the plain nest): the panel changes its setup. Not investigated.**
**End-of-slide flash, still OPEN (measured in the nest, picture wallpaper): in about 5% of
quiet slides (2 of 30, 4 of 45) a screenshot taken 340-520 ms into a 400 ms slide-back shows
the scene at the slide's start position with ~21% of the screen black (the right and bottom,
exactly the strip the frame left), `state` already says `visible=false` and the fades are
1/1/1. It happens with the wallpaper layer swapped for the desktop-window thumbnail alone, so
it is not the wallpaper layers. Reading: a stale scene frame is composited for one frame
around `endSlide`'s `visible = false`. Not fixed. A hold-the-last-frame or
hide-before-write ordering is the next thing to try; reproduce with the loop above (slide
300 100, slide -300 -100, one screenshot at a varied offset).**
**Tiled room (`147`): dragging one tiled/maximized window drags every tiled/maximized
window of its cluster; a free window moves alone. `111-thread-z` fails 3 checks on every
commit I bisected (back to 273f9e7) although it passed in earlier full runs: an environment
or order effect, not this change.**
**Tiling/maximize (`146`): a window leaving maximized or tiled returns to its plane spot (`main.qml`; needs a session restart; KZones untested). Next: a room of tiled windows moving as one, canvas-side maximize filling the frame.**
**Bookmarks landed (`145`): Ctrl+1..9 saves, Alt+1..9 flies back; effect-side (`main.qml`),
so a Plasma session restart loads it. Not yet seen live.**
**The effect now remembers whether the wallpaper is a picture (`wallpaperPicture` in
`main.qml`, asked at load, on reconfigure and on every open); the scene reads it
instead of asking afresh each open, so it is known before the first frame. A hot
reload swaps only `ui.qml`, which falls back to its own query. Open: a thumbnail's
first frame is still black. Considered and not built: playing the video inside the
scene with QtMultimedia (a second 2560x1440 decode in the compositor process, a
cold first frame again unless the player lives in main.qml and forwards frames,
and a decoder crash would take KWin, and the session, with it). The cheaper next
step is to hold the first presented frame until the thumbnail has painted.**
**Third black, from the user's own screen recording (16:29, 5120x1440, 60 fps): three
single-frame dips (frames 73, 117, 143), each the right-hand quarter of the screen
and the bottom black while the windows had already moved, i.e. the first frame of a
slide's scene before any wallpaper layer had content. `wallpaperDrawable` started
true (optimistic) so the frames painted KWin's black for that frame; it now starts
false and the desktop window shows until plasmashell has said the wallpaper is a
picture. NOT reproduced in the nest (its wallpaper is a picture); verify with a new
recording.**
**Second black, measured in the nest: late in a quiet slide 36% of the screen was
black (the frame had left and the wallpaper layer was off at 1:1); the layer now
draws whenever the canvas is up (`144`, 36% -> 0). Open: the landing still differs
~14% RMSE between the last slide frame and the desktop (video wallpaper not yet
separated from position/colour), and frame pacing is unmeasured.**
**The black fly is fixed by `wallpaperDrawable` in `ui.qml` (the last paragraph here is history).**
**Cause, measured live on 2026-10-13 with a Wallpaper Engine video: during a quiet
slide the frames' `KWin.DesktopBackground` painted solid black (0,0,0 where the
closed desktop was 6,28,63); with that item hidden the same patch matched. The
item draws only Plasma's own picture wallpapers.** Frames and the zoomed-out
background now draw only when every wallpaper plugin is a known picture one
(`org.kde.image`, slideshow, colour, potd, our ground); otherwise a
`WindowThumbnail` of the desktop window sits under the plane. Pinned by `143`.
The earlier layer that was removed (`e8fa19b`) was drawn *over* the black frames,
which is why it never helped.
The black flash on a fly (and at 1:1) is a Wallpaper Engine wallpaper
(`com.github.catsout.wallpaperEngineKde` is the live one): `DesktopBackground`
cannot draw it and KWin composites the scene over black. `ui.qml` now draws
the desktop window with a `WindowThumbnail` whenever the canvas is open
(`deskwin=` in `state`, pinned by `93`); in the nest, with a static wallpaper,
it is pixel-identical to the compositor's. **Not verified: a Wallpaper Engine
wallpaper, which the nest cannot run.** Live check (2026-10-13): KWin's scripting API reports plasmashell's desktop window
on DP-3 (`desktopWindow=true`, 4096x1152 logical, layer 0, not minimised), and
the scene finds it and logs it (`kwin-canvas ui: desktop window for DP-3`).
The layer is found imperatively in `ui.qml` (a 1 s timer while the canvas is
open) because the stacking order does not notify. Not seen: the open canvas
on the live desktop. The first build bound the layer's `client` to a function call: the live journal said
`ui.qml:286:13 depends on non-bindable properties` and the layer stayed null
(black still, at 1:1). It binds to `desktopWindows[output]` now, refreshed
with the window set. If it is still black live, check the journal for that
warning, then whether that window is a `desktopWindow` to KWin at all. What the live session showed: a steady open canvas at 1:1 matched the closed
desktop pixel for pixel (so the black is during motion), the layer did not cure
it, and from the hot reload that held the wallpaper's window (14:55) waywallen's
renderer logged `all slots are busy, dropping frame` continuously (about 65 a
minute, against a few before) and plasmashell's main thread spun at ~100% and
stopped answering D-Bus. Correlation, not proof (no stack: ptrace is blocked);
the layer is gone as unproven and possibly harmful. Next time: reproduce the
black on a recording first, and treat any thumbnail of the wallpaper window as
suspect for pinning its buffers. The sphere map was nested inside the lens (an unclosed content `Item` in
`ui.qml`, a stray `}` after the sphere): it never drew in a grasp. Fixed,
pinned by `114`'s corner-glass check. A second `commit` on a closed canvas is now a no-op (`142`; it pushed two undo
entries). Still open: an Esc that lands inside the 170 ms farewell after a
commit (the debug channel cannot deliver it that fast, so it is unmeasured), the forced-close `sceneGestures` write, the
minimap drag scale, delegate TypeErrors, `nest_env`
word-splitting. Not checked: the decor applet in a
real plasmashell, and the plugin's NVML path (no NVIDIA load measured).

- `main.qml`: the switcher's modifier poll called `effect.switcherSettle.restart()`,
  an id and not a property, so it threw on every poll; the cluster chip and the
  cluster switcher centred on a screen at the origin only (now the screen's
  `x`/`y` are in the fit, as `fitBox` has them).
- `ui.qml`: the rest cue's `restAnim.to` was left at 0 after a cancel, so the
  cue never refilled; `spaceHeld` is cleared on open.
- `applet-decor`: tooltips read `parent.modelData` (the Row, so always the
  capture text); the above/below/capture flags were not cleared without a
  focused window; `kreadconfig6` gets KDE's stock `--default` button sets.
- `plugin`: captions are stripped of `|` and newlines in the state reply; the
  shader state file goes through `QSaveFile`; NVML is initialised once; the
  D-Bus registration retries stop after one succeeds.
- `tools/kwin-canvas` (`--help` exits 0), `tools/fakeinput.c` (non-finite
  numbers refused, registry roundtrip and `strtol` overflow checked),
  `dev/demo.sh` (unused loop variable).
- This file: the session logs older than the latest three moved to
  `status-archive.md`; `AGENTS.md`'s line count for `main.qml` was 3.3k, it is 4.8k.

Found by the audit and **not** changed, because each touches behaviour a
scenario would have to judge: `dragRaw` is never cleared by `endDrag`, so
`animateEntry` skips a window dragged earlier (`main.qml` ~928, 3302); a
cross-activity `focusWindow` commits before `currentActivity` has updated
(~3049); `farewellHide`'s fade branch is dead because both callers set
`zoom = 1` first (~2523); `deskArea` ignores the screen origin (~2930);
`clickPanTimer` outlives a close (~3497); `commit`/`doCancel` can re-enter
while closing (~2702); the camera-rectangle drag in the minimap pans by the
wrong sign and scale (`ui.qml` ~1388); `sphereMap` appears to sit inside
`planeMap` in `ui.qml` (~1414), which would hide it; the forced close writes
`sceneGestures = 0` over a live counter (~1181). `dev/nest.sh`'s `nest_env`
is word-split on purpose-by-accident and breaks on paths with spaces.

### 2026-10-12 — the hold works everywhere, and the door's knob is wired

The user asked for the canvas modifier to stop being a desktop-only
gesture: "long hold shold go to canvas everywhere". The plugin's
`pointerButton` hold branch had passed a CanvasHold press to the window
under the pointer while the canvas was closed (a game's own back button
must never open the canvas); that pass-through branch and its
`m_holdPassed` bookkeeping are gone. Every CanvasHold press is now a hold
candidate wherever it lands: outlast `HoldDelay` and the canvas opens
quietly at 1:1 (the grasp), release sooner and the press is replayed as
the window's own click through the seat, so the back button still works
over a game. Verified: `make plugin` builds; 103-grasp 28/0 with its two
new checks (a quick press leaves the canvas closed; a hold over a window
opens it), 85-passthrough 21/0, 127-rest-cue 6/0, and the full suite at
its baseline.

The user's "scroll on desktop doesn't work" turned out to be a knob, not
code: the live kwinrc carried `WheelDoor=false` (the only anomalous key
in the group), so the zoom door was off. The knob had no live route
either - the plugin reads its `m_door` once at load and the effect never
called `setDoorEnabled` - so a KCM toggle would have waited for the next
KWin start. main.qml now publishes it (`doorCall`/`publishDoor`, on every
reconfigure) and the live kwinrc is true again; both halves land at the
next login, and from then on the knob applies as it says it does.

The same evening the user asked for the grasp's look to be the desktop
alone: "pleaser dont show threads for 1:1 0 zoom pans" and then "dont
even show the grid or the canvas or anything". Two quiet-look fixes in
ui.qml: the thread delegate's lit branch regained its own zoom fade
(full by 0.75, gone at 1:1 - the want formula had lost it in the ui.qml
extraction, which the 113 scenario's flapping had already been hinting
at), and the Ground invocation is now `visible: !effect.quiet`, so a 1:1
grasp shows nothing of the canvas over the wallpaper: only the windows
move, exactly as the quiet hold promised. The threads fade and the grid
gate are scene-side: `make hot` puts them in a running session.

### 2026-10-12 — the automatic camera moves learn to wait

The user picked the feel pass from the improvement menu. The hover's
fetch no longer starts after a bare 200 ms of rest: it waits out the
same deliberate pause the pointer's own handoff uses (`HoverDelay`,
900 ms by default, never less than the old 200), and it asks for a
gentle 0.55 flight rate instead of the default - a suggestion, not a
flight. The edge pan's ramp exponent went from 1.7 to 1.2, so a
half-depth band gives 391 px/s from the first frame (up from 277) with
the same 900 px/s maximum and no late surge. A nest probe measured
both: the fetch made no move at 800 ms and arrived by 1700 ms at the
exact least-move (KCalc half-off at 1800 -> view 384), and the edge
pan carried 398.9 px in its first second. (The probe's nest has the
spring off, so it measured the gate and the landing; the 0.55 glide
shows where SmoothZoom is on.) The momentum the feel needed was
already there: PanInertia coasts a flick by PanFriction, and
`94-physics` measures it.

The verification, and one bug the suite caught on the way: the fetch
waits half of `HoverDelay` now, not the whole pause - the pass-through
takes the pointer at that same pause, so the camera's move must land
before the handoff, not after (109-seam had been red for it; it is 9/0
now). The edge ramp's exponent fell from 1.7 to 1.2, so it pulls evenly
from the first moment (391 px/s at half depth, the same 900 at the
edge). Three scenarios the leftover `panSphereRadius` call had broken -
104-capture (19/0, one honest skip) and 115-stress (4/0) besides the 109
above - came back once it was gone, and 113-thread-duck (4/0) exposed a
real regression the ui.qml extraction had carried since it happened: the
web's zoom fade had been lifted out of the unlit branch, so every LIT
thread vanished above 0.5 zoom - the fade is back inside the unlit
branch, where the comment always said it belonged, and a lit thread
draws at every zoom. The full suite: 256 pass, 12 fail, 2 skip - exactly
the documented baseline, every one of the 12 the known suite-order
artefact, green alone.

### 2026-10-12 — the sphere leaves, and 1:1 becomes exact

The user asked why the bend "does not work that well vertically", then
asked for the real thing - a curved slice out of a true sphere - and the
true sphere was built: orthographic arc sampling, aspect-correct, the
silhouette radius riding the zoom. Then the verdict to keep: "i take it
back. remove everything related to sphere. we need new vision." The whole
look stack is gone - shared/GroundBarrel.frag and its .qsb deleted, the
worldSource grab and its ShaderEffect removed from ui.qml (the plane
wrapper is a plain Item again), sphereWarp and sphereRadiusPx gone from
main.qml, and the build rail with them (the `make barrel` target,
lint-shader's regeneration check, the qsb check in dev/deps.sh and
qt6-shadertools in CI). The plane is flat at every zoom - which is what
the goldens always held: 20-zoom is 8/0 with both snaps untouched
(extents rmse 0.00120189; the snap pair predates the bend, so the flat
render simply lands on it), and 128 stays 3/0.

The same round honored the feel verdicts: at 1:1 the hand moves the
plane exactly (panBy's exact branch), and the scenarios that carry 1:1
hand values moved back off the torch's numbers (94's 100; 103's and
85's 200/100; 81's 200/100 and 140/60). Then the torch itself left: the
user asked why the "torch-like cursor navigation" survived the sphere's
removal, and the answer became the change - panBy is `view -= dx / zoom`
at every zoom now, `panSphereRadius` is gone, and 80/112/20-zoom carry
the linear values again. The quiet hold's sphere map remains: older,
separate, and kept by the user's own verdict.

Older sessions are in [status-archive.md](status-archive.md): they are history, not state, and are kept so that nothing the earlier sessions learned is lost.

## How to keep this file

Date your entries, delete what is no longer true instead of stacking a new version
on top, and do not let it grow into a second `architecture.md`: the model belongs
there, the traps belong in `testing.md`, and what a user sees belongs in
`release-notes.md`.
