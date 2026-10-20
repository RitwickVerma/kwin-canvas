<!--
SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
SPDX-License-Identifier: GPL-2.0-or-later
-->

# Several monitors: two cameras on one canvas

This is the design for how the canvas behaves with more than one monitor, written
before the code it describes. It says what each interaction should do, what KWin
allows, and in what order to build it. Parts marked **built** exist; the rest is
the plan. When the code and this page disagree, the page is what to change or what
to build.

## The model

There is one canvas, one infinite plane, and every window has a place on it. A
monitor is a **camera**: a window onto the plane with its own position and zoom.
Nothing on the plane is a monitor. The overview does not draw monitors as
rectangles with output names; it draws where each camera is looking, and each
activity's desk frame, once.

Two modes, chosen with the `Cameras` setting and a toolbar toggle:

- **Merged.** The monitors are one camera over the whole arrangement, a larger
  canvas the size of the desktop. This is how the canvas has always worked, and
  it stays the answer for people who want one continuous surface.
- **Separate.** Each monitor has its own camera. What you do on one monitor, pan,
  zoom, fly, open the overview, grasp, throws, never touches another monitor.

The overview's animation is the same idea in both: it belongs to the camera it
happens on. In Separate it plays on the monitor under the pointer and nowhere
else. In Merged it is one animation driven by one clock across the whole
arrangement, so the monitors stay in step.

## What KWin allows (checked, not assumed)

These shape everything below.

1. **Real windows have one position in one global space.** The plane maps to the
   real desktop through each activity's target (the "location"). With one camera
   that mapping is one rigid translation, so nothing leaks. With several, a window
   pushed off one monitor's edge lands on its neighbour in real coordinates. A
   Separate desk therefore has to *park* a window that no camera shows, far outside
   every monitor, and un-park it when a camera comes back to it. Its plane
   coordinates stay the truth; its real geometry is a projection.
2. **The scene effect covers every output.** `QuickSceneEffect` makes one view per
   output and paints no real windows underneath. A monitor the canvas is not using
   cannot simply be left alone; it has to show a *quiet* scene, the canvas at 1:1,
   which is pixel-identical to the desktop it covers (the existing quiet slide
   relies on this). Whether an output can have no view at all is **not tested**.
3. **One activity for all outputs.** KWin has a single current activity. A camera
   cannot be in another activity than its neighbour; entering a location picks the
   activity from the pointer's camera and the others follow it.
4. **The pointer plugin has one plane transform.** The pass-through plugin and the
   plane-input shim map the pointer through a single scale and offset. Separate
   needs one per output.
5. **Fits and flights already name a monitor.** `actionScreen()` is the output the
   pointer is on, and `smartPan`, `placeTarget` and `flyToEntry` fit to its
   geometry. The one place that did not was the test for whether a window needed a
   fly at all (fixed, see below).
6. **View caching exists in C++ only.** `QuickSceneEffect::setViewCachingEnabled`
   keeps scene views alive between activations. It is not a QML property, so using
   it means a small hook in the plugin. It would take out most of the per-open cost
   (a fresh window and render interface per open, about half of the open's first
   100 ms in the nest). A candidate, not a plan.

## Every interaction, in both modes

"Active camera" means the camera of the monitor the pointer is on.

### Opening and leaving the canvas

| Interaction | Merged | Separate |
| --- | --- | --- |
| Chord, toolbar | Overview on every monitor, one animation, rippling out from the pointer. | Overview on the pointer's monitor only; the others show their quiet scene. |
| Screen corner or edge | The corner on monitor B fits around B (already so), the rest of the world fills the arrangement. | Opens B's camera only, fit to B. A second corner push on A opens A's camera independently. |
| Enter / Escape | Leaves for every monitor at once. | Leaves the pointer's camera; the other overview, if open, stays open. |
| Enter with the pointer between monitors | The location under the pointer's monitor centre. | Same: the camera the pointer is on decides, never the seam. |
| Leaving with a window straddling the seam | Window is nudged wholly onto the monitor it is mostly on. | Not possible: a window belongs to one camera. |

### Moving the camera

| Interaction | Merged | Separate |
| --- | --- | --- |
| Wheel, pinch, zoom keys | Zoom about the pointer; the arrangement scales as one. | Zoom the active camera about the pointer; the other cameras do not move. |
| Drag the ground, middle button, pan keys | Pans the whole arrangement. | Pans the active camera. |
| Flick / inertia | Coasts across the seam; the glide is one body. | Coasts and stops at nothing; it never crosses to another camera. |
| Quiet slide at 1:1 (wheel on the wallpaper, border push, swipe, MB4 grasp) | Shifts every monitor's windows together. | Shifts only windows on the active monitor; windows that leave its view are parked, windows that enter are un-parked onto it. |
| Fit (`F`, corner at fit) | Fits all windows within the **pointer's** monitor; the rest spills across. | Fits all windows within the active camera. |
| Home, origin, bookmarks | Fly the one camera. A bookmark stores one view. | Fly the active camera. A bookmark stores a view *per camera*, restored on the monitor it was set on, or on whichever is active when the monitor is gone. |
| Edge pan (window in hand at a screen edge) | Pans the arrangement, only when the edge is a real outer edge, never the seam between two monitors. | Pans the active camera; the seam is an edge only if the other monitor is not in the way. |

### Windows

| Interaction | Merged | Separate |
| --- | --- | --- |
| Drag a window within a monitor | As today. | As today, in the active camera's coordinates. |
| Drag a window across the seam | Moves continuously; the window straddles while held. | The window is carried by the pointer; on crossing, it is placed on the other camera at the pointer, in that camera's coordinates. It shows in both cameras while held if they overlap on the plane. |
| Throw, snap magnet | Snap to other windows and to frame edges; the seam is not an edge. | Snap within the active camera; monitor edges are the camera's edges. |
| Resize across the seam | Allowed. | The window stays on one camera; the grip stops at the camera's edge. |
| Auto fly to a window (double-click, Alt-Tab, hover fetch) | Lands wholly inside the **pointer's** monitor; never on the seam, never in dead ground (**built**, see below). | Lands wholly inside the active camera. A window that is wholly on another monitor is left where it is. |
| Focus a window on the other monitor | No fly if it is wholly on its own monitor. | Same, and the pointer is not moved. |
| Float (on all desktops) | The picture rides the edge of the monitor the window is on. | The picture rides the edge of the active camera's view; it is shown on every camera that sees the window. |
| Tiled, maximized, KZones | A tile is a room; it moves as a whole in its camera. | Same, per camera; a tile never spans two cameras. |
| Arrange, tidy, send to activity | Lays out inside the pointer's monitor. | Lays out inside the active camera; "send to" is per activity, not per camera. |
| Marquee, selection | Selects across the arrangement. | Selects within the active camera. |

### Chrome

| Interaction | Merged | Separate |
| --- | --- | --- |
| Toolbar, toast, minimap, switcher | On the monitor the pointer is on (**built**), moving once it has rested on another for 450 ms. | One set per open camera, each on its own monitor. |
| Frame tags, rectangles | One tag per activity, no output names (**built**); a numbered chip per monitor shows or hides that monitor's frame. | No monitor frames on the plane; the camera's own viewport is drawn on the minimap and, optionally, as a faint corner mark. |
| Minimap | One rectangle for the arrangement's view. | One rectangle per camera, tinted, so both can be seen on one map. |
| Grasp map | On the pointer's monitor. | On the pointer's monitor only; the other camera is untouched. |
| Switcher (Alt-Tab, Meta-Tab) | One map of the plane. | One map on the pointer's monitor; stepping selects windows from the whole plane and flies the active camera. |
| Fidelity ladder | One rung. | One rung per output: a 240 Hz HDR primary can be reduced while a 60 Hz monitor stays full. |

### Around the canvas

| Situation | Behaviour |
| --- | --- |
| A game or video is fullscreen on one monitor | Separate: the canvas never opens on that monitor, and a chord on it opens on the other. Merged: the canvas stays closed over a fullscreen app on any monitor. |
| Hot-plug, lid close, DPMS wake, resolution or scale change | Cameras are kept by output name. A returning monitor gets its camera back; a new one starts at 1:1 on its own desk. The plane is never rebuilt around a missing monitor. |
| Different scale and refresh rates | A camera's zoom is in logical pixels of its own output; animation time is wall-clock, so 60 Hz and 240 Hz outputs move together. |
| HDR | Not touched by the canvas; quiet scenes must not change the picture. |
| Panels and docks | Per output. A dock approach (the pointer reaching for a panel) never pans a camera. |
| Wallpaper | One ground per output. A live wallpaper that spans the arrangement is drawn once, cropped per camera. |

## Data model

- **A target per activity and output.** `targets[activity]` stays as the merged
  target. `outTargets[activity|output]` is a per-output offset on top of it, used
  only in Separate. `targetFor(activity, screen)` returns the one to use. With one
  output, or in Merged, every output shares `targets[activity]`, so every existing
  path is unchanged.
- **A camera per output.** `cams[output] = { x, y, z }`, the plane point at the
  output's top-left and its zoom. The existing `viewX`, `viewY` and `zoom` stay as
  the *active* camera, mirrored: when the pointer rests on another output the
  active camera is written back and the other is loaded. Everything that acts on
  "the camera" keeps working on the active one.
- **A mode per view.** Each output's view knows if it is `open`, `quiet` or
  `idle`; today that is one flag for the effect.
- **Parking.** A window outside every camera's view is mapped to real coordinates
  far outside the desktop: outside the bounding box of all outputs, plus a margin,
  in the direction it lies from the camera. Un-parking is the inverse and happens
  when a camera's view comes to it.
- **Merge and split.** Merging moves every camera to the contiguous position
  relative to the active one (a spring, windows gliding); splitting leaves each
  camera where it is.

## The overview animation

One principle: the animation is a property of a camera, and it is quick and
low-resource. A cold open of the scene already takes about 100 ms before the first
frame, so everything below starts from that first frame, never from a held one.

- **Open.** The camera lifts out on its spring. The windows are on screen from the
  first frame and scale down with the zoom; the chrome fades in staggered from the
  pointer outwards, nearest first. The frames' tags and the minimap arrive last.
- **Separate.** The same, on one monitor. The other monitors show their quiet
  scenes, which are pixel-identical to the desktop; nothing on them animates.
- **Merged.** One clock. The stagger's origin is the pointer and its distance is
  measured across the whole arrangement, so the wave crosses the seam and reaches
  the far monitor a few frames later. The two monitors never run separate clocks.
- **Merge and split.** A split plays as the second camera detaching: its view stays
  while the active one moves on. A merge plays as the other camera sliding to join,
  windows gliding with it.
- **Cost.** One animation clock per output at wall-clock time, stepped in sub-steps
  of at most a frame, so a 60 Hz and a 240 Hz output cover the same distance.

## Built so far

- **Auto fly never leaves a window on the seam or in dead ground.** The test for
  "is this window on screen" used the desktop's bounding box, which contains the
  seam between monitors and, with monitors of different size or offset, ground no
  monitor covers. It now asks whether the window is wholly on one monitor
  (`wholeOnOneMonitor`). Scenario `173`.
- **The chrome follows the pointer's monitor** instead of sitting on the primary
  display (`chromeScr`). Scenario `172`.
- **One frame tag per activity, no output names**, with numbered chips.
- **A differential test of the rest.** With two outputs stacked and offset as the
  owner's are, floats, fits, undo, arrange, tidy and step-in behave the same as on
  one output (scenarios `91`, `166`, `89`).

## Build order

Each stage ships on its own, passes the existing suite on one output unchanged,
and adds scenarios on two stacked outputs with different scales and offsets.

1. **Cameras as data.** `cams`, `targetFor`, the active-camera mirror, per-view
   state, the `Cameras` setting. In Merged nothing changes.
2. **Separate, overview only.** Open, pan, zoom, fit and fly on the active camera;
   the other monitors quiet. Leaving writes only that monitor's desk.
3. **Separate, at rest.** Quiet slide per monitor, parking and un-parking, hot-plug.
4. **Window interactions.** Drag across the seam, throw, snap, float on every
   camera, selection, arrange.
5. **Chrome per camera.** Minimap rectangles per camera, one rung per output, a
   switcher and grasp per monitor.
6. **Animations.** The staggered open, the merge and split.
7. **The plugin.** One plane transform per output; optionally view caching.

## Open questions for the owner

- Should Separate be the default, with Merged as the toolbar toggle?
- In Separate, a window wholly visible in two cameras: stay on the monitor it is
  on, or follow the pointer?
- Bookmarks: per camera, or one set for the whole canvas?
- A live wallpaper that spans the arrangement: is it one image across both
  monitors, or the same image on each?
