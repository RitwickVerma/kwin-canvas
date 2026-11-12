<!--
SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
SPDX-License-Identifier: GPL-2.0-or-later
-->

## What happened

<!-- One or two sentences. What did you do, what did you expect, what did you see? -->

## How to reproduce

1.
2.
3.

## Setup

- kwin-canvas commit (`git log -1 --format=%h`):
- KWin / Plasma version (`kwin_wayland --version`):
- GPU and driver:
- Wallpaper plugin (picture, slideshow, video, Wallpaper Engine...):
- Number of monitors:

## Evidence

<!--
Paste the output of `kwin-canvas doctor` first: it says what is installed,
whether the session is older than the files, whether the plugin matches KWin,
which chords clash, and lists the effect's QML errors since boot. It only
reads, so it is safe to run any time. Then the effect's own log:
    journalctl --user -b | grep -E "kwin-canvas|TypeError" | tail -50
A short screen recording helps for anything visual (a flash, a jump).
-->

```
kwin-canvas doctor output here
```

/label ~bug
