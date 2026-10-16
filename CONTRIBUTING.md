<!--
SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
SPDX-License-Identifier: GPL-2.0-or-later
-->

# Contributing

Bug reports and ideas: open an issue with the **Bug** or **Feature** template.
The effect's log (`journalctl --user -b | grep kwin-canvas`) and a short screen
recording make a visual bug fixable.

This repository is a fork of
[`aaronsb/kwin-canvas`](https://github.com/aaronsb/kwin-canvas), ahead of
upstream. The fork's own work is AI-generated under human direction, and is
proposed upstream in stages - [docs/status.md](docs/status.md) says where that
stands. Merge requests are welcome here for the fork's own features; changes to
upstream's code belong in an upstream merge request.

The bar every change must clear: measured, not assumed. A scenario proves the
behaviour (`make test ARGS=<name>`), a screenshot pins the pixels where they
matter, and the commit message ends with a `Verified:` paragraph naming the
commands that passed. The nested KWin is the test rig - never test against a
live session; `NEST_VIRTUAL=1 make test ...` runs it on a virtual framebuffer,
so nothing opens on your desktop. A new scenario should fail without the change
it pins - run it once with the change disabled and say so. [AGENTS.md](AGENTS.md) has the commands, the conventions, what is
deliberate and what has cost someone a session.

By contributing you agree to license your work under the project's
GPL-2.0-or-later, and to disclose AI-generated contributions as such, the way
the fork discloses its own.
