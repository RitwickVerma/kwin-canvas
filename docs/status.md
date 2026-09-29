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

On `4cbc21a`, in a live KDE Plasma 6.7.5 Wayland session (kwin 6.7.5):

- `make lint` — exit 0, on `4cbc21a` and again with this file in the tree. REUSE 3.3
  compliant: 111/111 files with copyright and licence information (108 before these
  three).
- `make test` — `== pass 244  fail 0  skip 2`. The full run was on `f8bd927`, whose
  tree differs from `4cbc21a` only by `.gitlab-ci.yml`'s last newline and the three
  scenarios that lost a shebang; `make test ARGS=94` was re-run after that commit
  and passed 27/0/0.
- `make fixtures` — regenerates the committed fixtures byte for byte.
- The four CI job scripts, taken from `.gitlab-ci.yml` and run here by hand — all
  four exit 0.
- `make test ARGS=81` — 29/0/0, and `make test-two-outputs` for `91` — 17/0/0. Both
  were re-run on this tree for this file, not remembered from an earlier session.

## What cannot be checked on this machine

- **The pass-through plugin** (`make plugin`, `make plugin-try`, `85-passthrough`):
  `extra-cmake-modules` is not installed, so nothing compiles. KWin's own headers
  are here (`/usr/include/kwin`), so ECM is the missing piece.
- **The plane-input shim** (`make test-shim`, `tests/shim/*`):
  `dev/spike/preload/shim.cpp` expects libkwin build-id `b4a7f7ab…` (kwin 6.7.5-1)
  and the installed libkwin is `d8d86b3c…`, so the shim scenarios skip before
  compiling.
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

`docs/architecture.md` → `Next` holds upstream's own list (snap zoom to 1 on commit,
drawing limits, an edge pan at 1:1, auto-pan while dragging to a screen edge,
bookmarks and a minimap, persisting `view` on commit). Beyond those, from this
side of the fork:

- Two-output goldens exist only for `91-two-outputs`; another arrangement would
  widen `make test-two-outputs`.
- `93-backdrop` measures the tiling at its edges; the plane's behaviour past
  `BackdropReach` and under a second output's tile is only partly pinned.
- The two skips in `make test` are honest ones: `85-passthrough` needs the plugin
  and `91-two-outputs` needs a two-output nest. A machine with matching KWin headers
  and ECM would turn the first into a real check — and `make test-shim` into a
  second runner rather than a skip — which is the biggest gap left in the suite.

## Sessions

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
