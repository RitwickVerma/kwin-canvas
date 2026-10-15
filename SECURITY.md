<!--
SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
SPDX-License-Identifier: GPL-2.0-or-later
-->

# Security

kwin-canvas runs inside your compositor: the effect is QML loaded by KWin,
and the optional pass-through plugin is C++ that KWin loads at start and that
sees every pointer and key event while the canvas is open. A bug in either can
take the session down; a malicious change could read input.

- **Report** a vulnerability privately, by email to the address in the
  copyright lines, not in a public issue. Say what is affected and how to
  reproduce it; expect an answer within a week.
- **The plugin** registers a D-Bus object, `/KWinCanvas`, on the session bus.
  Anything running as you can call it. It changes window flags and the
  canvas's state, nothing outside the session.
- **Installing** the plugin system-wide needs `sudo`; the effect, the wallpaper
  and the applets install per user in `~/.local/share` and need no privilege.
