<!-- SPDX-FileCopyrightText: 2026 Ritwick Verma -->
<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
# Security policy

## Scope
Everything shipped in this repository: the KWin QML effect, the ground
wallpaper, the three applets, the window decoration, the C++ pass-through
plugin (a KWin input filter that forwards pointer and key events to windows
while the canvas is open), the `kwin-canvas` CLI, and the two paths that run
as root: `kwin-canvas fix-plugin` and `kwin-canvas plugin-hook`, which
install the plugin through `sudo` and, with the hook, through a pacman hook
that builds as the checkout's owner and installs as root. Bugs in KWin,
Plasma or Qt belong to those projects.

## Reporting
Open a **confidential issue** on this GitLab project. Don't use a public issue
or merge request for a vulnerability.

## What to include
- Affected version or commit, KWin/Plasma version, and session type
- Whether the pass-through plugin is installed (`kwin-canvas status`)
- Steps to reproduce, and the impact you expect
- A proof of concept or logs, if any

## Response
Best effort, no guaranteed timeline. There is no bug bounty.
