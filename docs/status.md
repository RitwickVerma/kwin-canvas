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

- `origin` is `git@gitlab.com:ritwick7/kwin-canvas.git` and **does not exist yet**
  (the API answers 404 as of 2026-09-28), so nothing has been pushed. Once the
  empty project is there: `git push -u origin main`, which also moves `main`'s
  tracking from `upstream/main` to `origin/main`.
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

- `make lint-qml` and `make lint-shell` — exit 0. `lint-reuse` still needs
  `reuse`, which is not installed here (below).
- `make test` — `== pass 340  fail 0  skip 1`, the skip `91-two-outputs`
  needing a two-output nest; `85-passthrough` runs for real against the
  built plugin. `make test-two-outputs` — `== pass 17  fail 0  skip 0`.
- The goldens were re-recorded in the full-run sequence (`make golden`),
  since the plugin and the now-running 85 changed what the scenarios after
  them see; the 1:1 goldens did not move.
- `make fixtures` — regenerates the committed fixtures byte for byte.

## What cannot be checked on this machine

- **The plane-input shim** (`make test-shim`, `tests/shim/*`):
  `dev/spike/preload/shim.cpp` expects libkwin build-id `b4a7f7ab…` (kwin 6.7.5-1)
  and the installed libkwin is `d8d86b3c…`, so the shim scenarios skip before
  compiling. The pass-through plugin, the shim's substitute, does build here
  now (the dependencies were installed) and `85-passthrough` runs for real.
- **The live-session half**: the `evaluateScript` handoff, and the wallpaper inside
  a real plasmashell, have been rendered in isolation only.
- `reuse` itself is not installed here, so `make lint-reuse` needs
  `sudo pacman -S reuse`; it lived only in a scratch venv that has been deleted.

## Decisions taken, and the ones still open

Taken, with the reasoning in `AGENTS.md` → *Deliberate, not accidental*: no
`.clang-format`; docs and images stay `GPL-2.0-or-later`; no shellcheck and no test
job in CI; `qmllint` by absolute path; the scenarios stay local because they need a
nested KWin.

Open:

- Whether the fork publishes anything of its own (tags, GitLab releases) or upstream
  stays the only publisher.
- Whether a runner can host a nested KWin — that is what a CI test job would need.
- Whether `shellcheck` earns a job once it is installed.
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
