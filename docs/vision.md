# SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# The one canvas

What this project is, stated as one coherent story, and the gaps between
that story and what the tree does today. This is the picture the work is
meant to converge on; the mechanics live in
[architecture.md](architecture.md), and this file is only the whole.

## The story

There is one place: the plane. Every window lives on it at its own
coordinates, and every screen is a viewport onto it. The *location* is a
viewport at 1:1 - stock Plasma, nothing of ours running - and the
*overworld* is the same viewport stepped back far enough to see the plane.
They are not two modes. They are one space, and the only things that change
with the camera are how much of the space you see and how much of the
canvas's own skin - the frames, the threads, the tags - is in view.

Holding MB4 and opening the overworld are the same gesture at two depths.
MB4 is the canvas through a keyhole: the location itself becomes the canvas
quietly, the hand works the plane through it, and the release commits. The
chord is the same canvas stepped out. Inside, they are indistinguishable:
the same pan, the same edge pan, the same wheel, the same hover glow, the
same threads, the same clusters, the same float, the same fly. The keyhole
shows the plane bare while the camera is at home - it must, or the desktop
would not look like itself - and the skin fades in as the camera departs,
so by the time you are zoomed out the keyhole and the overworld are the
same picture. One space, one skin, one physics.

What belongs to the space, and behaves identically at every depth:

- **The fly.** Anything that focuses a window - a click, Alt-Tab, the task
  bar - slides the viewport the least that brings the window wholly into
  view. It never moves a window, never grabs the gesture that caused it,
  and works whether the window is already active or not.
- **The hover.** The pointer resting on a window makes it the canvas's
  focus: the glow, the Enter target, and the camera pans the least that
  fits it - over the client area too, where the plugin owns the pointer.
- **The float.** A floated window keeps its coordinates; only the hand
  moves them. While it sits inside the screen its picture is the window,
  at rest, under any camera or zoom; pushed out, the picture bounces off
  the edge and settles against it; the camera returns and the picture is
  the window again.
- **The clusters.** Nearby windows are one cluster - the gap is the
  windows' own scale - wearing a thread that rides the camera with them;
  the brackets fly between clusters in reading order.
- **The edge pan, the WASD keys, the Tab cycle, the bookmarks.** Routes
  around the plane, the same at 1:1 and stepped out.

What differs with the depth, and only this:

- The **skin** - the frames' tint and outlines, the tags, the threads, the
  badge - fades in as the camera departs from the location, and is what
  the overworld shows at full strength.
- The **toolbar** and the **help** are the overworld's: the controls for
  the stepped-out view, not the keyhole.

## The invariants

1. **A window's coordinates change only by the hand.** The camera never
   moves a window; the fly, the hover, the float, the clusters and the
   bookmarks move the viewport or the picture, never the plane position.
   Commits write coordinates the hand (or a slide) put there.
2. **The camera never grabs the hand.** A fly, a nudge or a close waits
   for the buttons to come up; a gesture that caused a camera move is
   never swallowed by the canvas that opened for it.
3. **The eye knows what is yours.** The focused window glows wherever the
   pointer rests, and Enter applies with it.
4. **Nothing snaps.** Every camera move is a spring, every fade a fade,
   every membership a hysteresis band, every edge a bounce.
5. **The picture and the plane agree.** What the overworld shows is what
   the commit writes; a slide's projection absorbs as no move.

## The gaps

- **The keyhole and the overworld wear different skins.** The quiet canvas
  hides the frames, the tags, the threads and the hover glow entirely, so
  zooming out during the hold reveals a bare plane where the overworld
  shows the skin. The skin should fade in with the camera's departure.
- **The double-click mid-spring.** The first click of a double-click pans
  the camera (the click-fit); the second click's placement can read a
  camera still in flight, and a window-focused placement must not depend
  on where the camera happens to be mid-spring.
- **Special windows.** A window whose type the canvas filter rejects (a
  utility window, an X11 oddity) is invisible to the fly, so KWin's own
  keep-visible rule moves the window alone - and its activation can still
  open the canvas for a split second. The fly must cover every window the
  user can click, and the canvas must never open for one it does not fly.
- **The tests are one big nest.** The pure logic - the cluster gap, the
  placement, the physics - is exercised only through the scenarios; small
  unit tests over the same functions would fail in milliseconds instead of
  minutes.
