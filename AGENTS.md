# Working on kwin-canvas

An infinite canvas for KDE Plasma: a KWin QML effect that draws every window on
one unbounded plane, a wallpaper that draws the plane at 1:1, a panel applet, a
terminal CLI, and an optional C++ plugin that hands the open canvas's input to
the real windows. This file is the way in for whoever works here next, a person
or an agent: the commands, the conventions, what is deliberate, and what has
already cost someone a session.

The model lives in [docs/architecture.md](docs/architecture.md); where the work
stands right now is [docs/status.md](docs/status.md).

## The four rules

1. **Never test in the live session.** The effect moves windows and grabs
   input, so a bad build is a session you cannot use. Everything goes through
   the nested KWin first: `make play` to look at it, `make test` to prove it.
2. **A QML edit needs a nest restart** (`make nest-reload`), not `make reload`:
   KWin's QML engine holds the component it compiled, so neither a reload nor
   clearing the QML cache picks up a new `main.qml`. In a live session only a
   new Plasma session does.
3. **Measured, not assumed.** A scenario measures the effect's own state
   (`make nest-cmd CMD=state`), a screenshot pins the pixels, and a commit
   message ends with a `Verified:` paragraph naming the commands that passed.
4. **Keep [docs/status.md](docs/status.md) current.** It is the one file that is
   meant to go stale: update it when you stop.

## Commands

`make` alone lists every target. The ones that matter:

```bash
make deps                    # what is missing on this machine, and how to install it
make deps-install            # ... with pacman
make lint                    # REUSE metadata + QML syntax + shell syntax + the dead-code census (what CI runs)
make lint-reuse              # copyright and licence metadata, REUSE 3.3
make lint-qml                # every .qml file, failing on a [syntax] warning
make lint-shell              # bash -n on every script, then shellcheck at error severity (.shellcheckrc)
make lint-deadcode           # tools/deadcode.sh: nothing declared may be referenced only at its declaration
make lint-python             # vulture over the Python: no dead functions, imports or variables

make tools                   # build/tools/fakeinput, the fake-input client
make fixtures                # regenerate tests/fixtures (committed; CI diffs them)

make play                    # nest + fixture apps arranged + canvas open: look at it
make play ARGS=--closed      # ... at 1:1 with the canvas closed
make nest                    # the bare nest
make nest-cmd CMD=state      # drive the effect without a mouse
make nest-cmd CMD="zoom 0.4 960 540"
make nest-shot               # screenshot the nest
make nest-log                # tail the nested KWin's log
make nest-reload             # reinstall, restart the nest, relaunch clients
make nest-down               # stop it
make nest-clean              # kill leftovers of nests whose state is gone

make test                    # all scenarios, ~10 min: expect "== pass 244  fail 0  skip 2"
make test ARGS=60            # scenarios whose file name matches
make test ARGS="--update-golden 93"   # re-record that scenario's golden shots
make test-two-outputs        # NEST_OUTPUTS=2, the 91 scenarios
make test-shim               # tests/shim/* under the plane-input preload shim
make golden                  # re-record every golden screenshot
make demo                    # scripted session with real input; stills, frames, mp4, gif
```

`make install`, `make reload`, `make enable`, `make status` and
`./configure.sh install|uninstall|enable|disable|status|try` touch the **live
session**. Use them to try something on your own desktop, never as the evidence
that a change is correct. `make test`, `make play`, `make demo` and `make golden`
all depend on `install`, so they leave the packages installed in `~/.local/share`
for the live session too: the nest loads the effect from there, which is also why
a scenario sees exactly what `make install` produced.

Deeper: `source dev/nest.sh` exposes `up`, `down`, `run`, `cmd`, `shot`,
`input`, `js 'CODE'`, `probe NAME`, `fixtures` and the rest without running
anything, and `tools/kwin-canvas exit|cancel|open|toggle|status` is the same
debug channel from a terminal. `docs/testing.md` documents both.

## What to run before you claim a change works

Cheapest first, and stop where the change warrants:

1. **While editing**: `bash -n FILE.sh`, `/usr/lib/qt6/bin/qmllint FILE.qml`.
   The Qt5 `qmllint` in `/usr/bin` answers to the same name and is the wrong
   one, and qmllint returns 0 even on a syntax error, so grep its output for
   `[syntax]` (which is exactly what `make lint-qml` does).
2. **`make lint`** — metadata, QML and shell, in about a second, and exactly
   what the CI jobs run, so a red pipeline reproduces here.
3. **`make test ARGS=<name>`** — one or two scenarios in a nest, a minute or two:
   the right size for a change you can describe in one sentence.
4. **`make test`** — the whole suite against a fresh nest, ten minutes or so,
   `== pass 244  fail 0  skip 2` on a healthy tree. Both skips say what they cannot
   check here: `85-passthrough`, because the plugin is not built, and
   `91-two-outputs`, because it needs a two-output nest — which is what
   `make test-two-outputs` gives it instead of a skip.
5. **Screenshots.** A change that shows on screen usually moves a golden: run the
   affected scenario, look at `build/test/NAME.diff.png`, and re-record with
   `make test ARGS="--update-golden NAME"` **only when the new picture is what
   you mean**. A golden diff is evidence, not noise: say in the commit what
   moved and why.
6. **`make fixtures && git diff --exit-code -- tests/fixtures`** when you touch
   `tests/fixtures/gen.py`: CI fails when the committed fixtures are not the
   generator's output.

## The tree

| Path | What it holds |
|---|---|
| `effect/contents/ui/main.qml` | The canvas: 3.3k lines, the whole effect — snapshot, ground, frames, thumbnails, pan, zoom, pick, commit |
| `effect/contents/ui/config.ui` | The settings form. **Every knob is declared in `effect/contents/config/main.xml` first** — that file is the schema |
| `shared/Ground.qml` | The ground renderer, copied into the effect and the wallpaper at stage time: one edit has to suit both |
| `wallpaper/` | The ground at 1:1 in a real plasmashell |
| `applet/` | The panel button that fires the canvas chord |
| `plugin/` | The optional pass-through plugin: a KWin plugin plus an input filter (C++) |
| `tools/kwin-canvas` | The CLI: the debug channel from a terminal or a VT |
| `tools/fakeinput.c` | The fake-input client the tests and the demo drive |
| `tests/run.sh`, `tests/lib.sh` | The runner and its vocabulary: `c`, `sget`, `eget`, `setcfg`, `snap`, `arrange`, `input`, `push_border` |
| `tests/scenarios/NN-name.sh` | Scenarios: sourced fragments, mode 644, no shebang; each sets `scenario_desc` and defines `run_scenario` |
| `tests/golden/`, `tests/fixtures/` | Committed screenshots, and fixtures generated from `gen.py` |
| `tests/shim/`, `tests/run-shim.sh` | The plane-input scenarios, under `dev/spike/preload` |
| `dev/nest.sh` | The nested-KWin harness: sourceable, its own bus, config, activities and log |
| `dev/deps.sh`, `dev/play.sh` | The dependency check, and the prepared nest |
| `dev/spike/preload/` | The `LD_PRELOAD` shim (1.1k lines of C++) that lets the canvas pass input without the plugin |
| `packaging/` | PKGBUILD templates and the install scriptlet |
| `docs/` | architecture (the model, KWin API facts, limits, ideas), testing (the harness and its traps), install, recovery, tour, release-notes, status, images + `tour.sh` |
| `VERSION` | Read by the Makefile; bumping it is part of a release |

## Where the thinking is written down

- **`docs/architecture.md`** — the model, the KWin API facts this rests on, one
  section per feature, `Known limits`, and `Next` (upstream's own idea list).
  Add a section here when you add a subsystem.
- **`docs/testing.md`** — the harness, the scenario vocabulary, what CI checks,
  and `Things that cost time`, where the hard-won specifics live.
- **`docs/status.md`** — where the fork stands: verified, not verifiable here,
  open decisions, next candidates.
- **`docs/release-notes.md`** — user-visible changes, newest under `Unreleased:`.
  Anything a user can see gets a line, in the same prose voice as the rest.
- **`README.md`** — what the project is, for someone deciding whether to use it.

## Conventions this repo holds you to

- **SPDX headers.** Every file that can carry a comment starts with its copyright
  line and an `SPDX-License-Identifier` of `GPL-2.0-or-later`. Files that cannot
  carry one (PNGs, the JSON and XML KWin parses, `VERSION`, the text fixtures) are
  listed in `REUSE.toml`. `make lint-reuse` fails otherwise: a new file needs a
  header or an entry of its own, and upstream's line is never replaced by yours.
  (Write the two tags exactly as the other files do — a tag inside prose counts as
  a tag, which is how this bullet was first written and how `reuse lint` caught it.)
- **Attribution.** The copyright line names who wrote the file: upstream's author
  for upstream's files, this fork's for what the fork added. Generated artifacts
  (goldens, fixtures) carry the project author.
- **Commit messages** are prose in this shape: a title saying what changed, bullets
  naming the files and the reasoning, then a `Verified:` paragraph with the
  commands and their results. No `feat:`/`fix:` prefixes.
- **British spelling** in prose (`licence`, `colour`, `neighbour`), as upstream.
- **Scenarios are sourced, never run**: mode 644, no shebang, `scenario_desc` and
  `run_scenario`, and a `snap` only where the pixels matter.
- **Shell** is bash with `set -uo pipefail`, and a script that sources another
  carries a `# shellcheck source=` comment whether or not the linter is installed.
- **The Makefile** is tabs, and every target documents itself with a trailing
  `## text` so `make` stays the index of what this repo can do.
- **Docs are part of the change.** If the code and a doc disagree, one of them is
  a bug: fix whichever is wrong in the same commit, and add a line to
  `docs/release-notes.md` for anything a user can see.

## Deliberate, not accidental — do not "fix" these

- **No `.clang-format`.** The C++ predates one and is not clean under any base
  style: under the closest (`WebKit` + `Allman` + right-aligned pointers)
  `clang-format` rewrites `dev/spike/preload/shim.cpp` (576 lines),
  `tools/fakeinput.c` (120), `plugin/passthrough.cpp` (80) and `tools/keys.h`
  (61), while `plugin/main.cpp` and `plugin/passthrough.h` come out unchanged. A
  config the tree violates is worse than none. Add one only with the reformat
  commit that makes it true.
- **Docs and images are GPL-2.0-or-later**, not `CC-BY-SA-4.0`: one licence
  across the tree. Revisit in `REUSE.toml` if that ever matters.
- **CI has no test job.** `.gitlab-ci.yml` runs in a bare
  `archlinux:latest` with no compositor: it lints (REUSE, QML, shellcheck at
  error severity, the dead-code census, vulture) and builds, and the scenarios
  stay local because they need a nested KWin with real windows. `docs/testing.md`
  says this out loud rather than pretending.
- **Goldens and fixtures are committed**, and CI checks that `make fixtures`
  reproduces the fixtures byte for byte.
- **The nest turns the motion knobs off** (`SmoothZoom`, `PanInertia`,
  `WindowPhysics`) so a scenario measures the canvas and not the spring;
  `94-physics` is the scenario that turns them on. A scenario expecting instant
  motion is not wrong.
- **`qmllint` is called by absolute path** (`/usr/lib/qt6/bin/qmllint`) because
  the Qt5 build in `/usr/bin` answers to the same name.
- **`make release`, `make aur` and `make aur-passthrough`** publish to the
  upstream project's GitHub releases and AUR packages. Do not run them from a
  fork; `docs/status.md` has this fork's remote setup.

## Traps, and where the rest of them are

`docs/testing.md` → `Things that cost time` is the long list. The ones that bite
first:

- **The QML component cache**: `make reload`, and unload/load, reuse the component
  KWin compiled at load. Restart the nest; a live session needs a new Plasma
  session.
- **The camera animates.** A `view` read right after `open`, `origin`, `home` or a
  zoom is mid-flight, and any delta measured from it is wrong. Poll `state` until
  it settles — the `cam=` field says when it has — or you will report a wild pan.
- **A held button needs an injector that stays alive.** `printf ... | input`
  blocks until its stream ends, the injector exiting *is* a release, and `sleep`
  in the stream is milliseconds (`sleep 5` is 5 ms, not 5 s). To read state
  during a hold, background it with a long tail.
- **A drag needs motion events**: `glide X Y 1 1` is a jump and pans nothing,
  while `glide X Y 10 20` pans by the full delta.
- **Read the effect's log, not `visible=true`**: a JS exception mid-commit leaves
  the canvas open. `make nest-log`, and grep for `TypeError`.
- **Everything that talks to the nest uses the nest's bus** (`$STATE/bus`), from
  the other side the CLI sets `DBUS_SESSION_BUS_ADDRESS` itself, and an empty
  variable would silently fall back to the live session's bus.
- **`make nest-clean`** when you are done: portals and kactivitymanagerd outlive
  the private bus they were activated on.

## Upstream, the fork, and the two things that cannot be built here

- Remotes: `origin` is this fork (GitLab, `ritwick7/kwin-canvas`), `upstream` is
  [`aaronsb/kwin-canvas`](https://github.com/aaronsb/kwin-canvas). The fork's own
  work is `git log --oneline upstream/main..HEAD`. Push to `origin`; upstream
  takes a merge request from a person's account, not a push.
- **The pass-through plugin builds here** (`extra-cmake-modules` is
  installed), so `85-passthrough` and `87-passthrough-zoom` run for real.
  `make plugin` builds it; the nest loads it from `build/plugin/bin`.
- **The shim does not build here either**: `dev/spike/preload/shim.cpp` pins the
  libkwin build-id it was written against (kwin 6.7.5-1) and this machine's
  libkwin differs, so `tests/run-shim.sh` reports the skip before compiling.
  Either needs a machine whose KWin matches; until then both are checked by
  reading, and the skips in the suite are honest rather than green.
- **The live-session half is untested**: the `evaluateScript` handoff and the
  wallpaper plugin have been rendered in isolation, not inside a real
  plasmashell (`docs/architecture.md` → `Known limits`).

## If you are the next session

Read `docs/status.md`, do the work, then update it: what you verified, what you
could not, what you decided and why. Leave the tree with `make lint` green, the
scenarios you touched green, and a commit in the shape above. `CLAUDE.md` is a
pointer to this file for tools that look for that name; if another tool wants its
own (`GEMINI.md`, `.cursor/rules/`), make it a pointer too, not a second copy of
these rules.
