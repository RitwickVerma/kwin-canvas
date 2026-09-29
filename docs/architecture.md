# Architecture

## The model

Three coordinate spaces:

| Space | Meaning |
|---|---|
| canvas | the plane windows live on; unbounded |
| global | KWin's coordinate space across all outputs |
| screen | one output's local pixels; `global - output.geometry.topLeft` |

One camera and one target per activity. `view` is the canvas point the
camera puts at global (0,0), and `zoom` is its scale. `target(a)` is the
canvas point at global (0,0) when activity `a` is shown; its monitor frames
are drawn at `target(a) + output.geometry` for every output, so each activity
is a rigid group of frames in KDE's layout, placed anywhere on the plane.
While the canvas is closed, `view == target(current activity)`.

```
global = (canvas - view) * zoom
canvas = view + global / zoom
frame geometry = canvas - target(activity of the window)
```

A window's canvas position is its KWin geometry plus its own activity's
target. Activities never placed are laid out in a row beside the current one
on first open, which moves nothing. Virtual desktops stay ordinary KWin
desktops: the canvas shows the current desktop's windows across every
activity, and a desktop switch changes the set of windows, not the view.

A frame can be switched off from its tag. `HiddenFrames` lists
`activityId|outputName` keys; a hidden frame is not drawn, is not a snap
candidate, is left out of fit, and never claims a window when you step in. The
effect writes the key through its own `configuration` map and
`writeConfig()`, so the choice survives a restart.

At 1:1, `zoom` is 1 and a window at canvas `c` has KWin frame geometry
`c - view`. That is the whole trick. KWin's geometry *is* the canvas table,
offset by one vector. Windows beyond the screen are simply at off-screen
positions, which KWin allows and stops sending frame callbacks for.

The effect holds only `view` between activations. Everything else is
re-derived from live geometry each time the canvas opens.

## Lifecycle

Two places. A **location** is an activity's frame group at 1:1 with the
canvas closed. The **overworld** is the open canvas. One chord, Toggle
Canvas (`ToggleShortcut`, default `Meta+Ctrl+Alt+Space`), steps out of a
location into the overworld and back in.

**Closed (in a location).** The effect is not running. No transform, no
grab, no per-frame work, so games and fullscreen apps get KWin's native
path: direct scanout, no extra composition. Three things happen in this
state:

- `windowActivated` on a window with no on-screen intersection shifts every
  canvas window by the same delta so it lands centred on its output, and
  adjusts `view` to match. The task manager becomes a way to travel.
- A pan chord or a touchpad swipe starts a slide (below).
- The Toggle chord steps out: the canvas opens.

**Slide.** A pan at 1:1. `slide(dx, dy)` opens the canvas *quiet*: `open(true)`
snapshots as usual but skips the opening view, and while `quiet` is set the
per-screen delegate is disabled for input and draws the ground, the frames
as bare wallpaper (no tint or outline at 1:1), and this activity's
thumbnails, with no tags, borders or toolbar. At zoom 1 that is
pixel-identical to the real screen when the Canvas Ground wallpaper is in
use. A `ParallelAnimation` moves `viewX`/`viewY` to `slideTo` over
`PanDuration` with an ease-out; a second slide while one runs adds to the
destination and restarts. On arrival the entry targets are restored and
`shiftAll` moves this activity's windows by the distance travelled, while
the thumbnails still cover them, and the effect hides. A slide is
navigation: only the current activity's windows are drawn while quiet, and
no window changes activity, so what slides is what 1:1 shows before and
after. A slide that ends where it began cancels instead. Any action that
wants the real canvas while a slide runs (`toggle`, Home) finishes the slide
first. A pan chord while the canvas is open moves the camera by the same
step and nothing more. A slide never leaves the location; the Toggle chord
is the only way out.

**Pass-through** is the optional binary plugin under `plugin/`, a
`KWin::Plugin` that is also an `InputEventFilter`, and it is live whenever
the canvas is open (`Passthrough`, default on). The filter is installed at
the `Effects` weight, which KWin inserts after its global-shortcut filter
and ahead of its own effects filter, so the Toggle chord still fires and
the effect's QML scene sees only what the plugin lets through. The effect
probes it over D-Bus on open (`org.kde.KWin`, `/KWinCanvas`,
`org.kde.kwin.canvas.Passthrough`); when it answers, the effect publishes
the camera to it on every change (view, zoom, current activity, the targets
as JSON) and switches it on. The filter maps each pointer event to the
plane, finds the topmost window the canvas draws there, and if the window's
input surface takes the point, delivers the event to the Wayland seat with
the window's own input transformation, so the client sees the same surface
coordinates it would at 1:1. A press inside a window raises it and starts
an implicit grab until the buttons are up; a press on the ground leaves the
gesture to the effect, and so does a press of a button in `planeNavButtons`
(`setNavButtons`), wherever it lands — the window under it never sees it, and
the canvas's QML owns the whole gesture, which is what lets a held button be a
portal into the canvas. Over the ground the pointer leaves the surface and
events fall through, so the effect pans and zooms as before. Every key goes
to the focused window, Esc included; the canvas's own keys work only when
the plugin is absent. The thumbnail grips only ever see title bars and
edges, since the plugin has taken the client areas, and a drag there moves
the window on the plane; selection, the marquee and the arrange menu start
from the title bar. Stepping in writes every entry once from its plane
position.

**Plane input** is the route that replaces pass-through: an LD_PRELOAD shim
for stock kwin_wayland 6.7.5 (`dev/spike/preload`, a spike) moves KWin's
pointer chain into plane coordinates, the contract a KWin patch for #3 would
provide:

```
plane = (screen - o) / s      s = zoom      o = (target(current) - view) * zoom
```

A plane point is a frame position on the current activity, so every KWin
filter and every client sees the pointer where the window really is, and
clicks, focus, keys and client-side moves work unmodified. A
`QuickSceneEffect` cannot share input by itself: `startInternal()` grabs the
keyboard and starts mouse interception for as long as it runs
(`effect/quickeffect.cpp`), `EffectsHandler::pointerMotion`, `pointerButton`
and `pointerAxis` consume every event while any effect intercepts
(`effect/effecthandler.cpp`), `InputRedirection::findToplevel` finds no
window and `CursorImage` shows the effect's cursor while
`isMouseInterception()` is true (`input.cpp`, `pointer_input.cpp`), and
nothing of this is reachable from QML. So the shim decides in-process, and
the effect tells it what the canvas owns:

- The shim finds the effect with `EffectsHandler::findEffect("kwin-canvas")`
  (the QML root object is the `Effect`), sets its `planeInput`, and reads
  `planeLive`, `planeScale`, `planeOffsetX` and `planeOffsetY` on every
  use. `planeLive` is `planeInput && canvasOpen`; the offsets are bindings
  on `zoom`, `view`, the current activity and `revision`, so every camera
  and target change is published by the binding itself and closing clears
  it. The transform is identity unless the effect object exists, is active
  (running, with views, screen not locked) and is live, so an unloaded,
  closed or failed effect leaves KWin stock at the next event, and within
  a second without one. The pass-through plugin stands down while
  `planeInput` is set.
- For each pointer event the shim asks `planeTakes(x, y, w)` with the
  screen point and the window KWin finds at the plane point. A press of a
  button in the effect's `planeNavButtons` (the PanHold buttons and the
  middle button) skips the question: it is the canvas's wherever it lands,
  client areas included, which is what makes a held button a portal into the
  canvas rather than something the window under it sees.
  The effect
  walks its scene with `childAt` from the view under the point: the pointer
  goes to the window only over a thumbnail's client area (an item with no
  handlers, `kwin-canvas-client`) with nothing of the canvas above it, when
  the thumbnail's window is on the current activity, sits where its entry
  says, and is the window KWin found there. Title bars, borders, the resize
  grips (6 screen px, over the client's edges), frames, tags, ground,
  toolbar and any open menu are the canvas's, as are windows of other
  activities, which KWin does not have on the plane. Where the canvas does
  not take the point, `isMouseInterception()` answers false and
  EffectsHandler passes the event on, so KWin's own chain routes it. A
  press latches the answer until every button is up. The effect sees every
  event it takes and every hover motion at screen positions, and
  `cursorScreen()` maps `Workspace.cursorPos` for the anchors that use it.
- Keyboard policy: `hasKeyboardGrab()` answers false while live, so every
  key goes to the focused window, Esc, Enter and Space included. The ways
  out are the Toggle chord (a global shortcut, which fires before any
  window sees the key), the toolbar's Enter and Cancel, and the hot corner.
  The canvas's own keys work only without the shim and the plugin. Touch
  stays the canvas's, at screen positions.
- KWin routes by real geometry, so while live a window of the current
  activity that moves on the canvas is written at once (`settle()`, after
  any revision): its entry takes the new frame position first and absorbs
  the write as no move, and a pending size from `requestSize()` is asked
  for again. Cancel puts every window it moved back (`unsettle()`); with
  `FramesCarryWindows` a frame drag moves the target and the windows
  together, so nothing is written and the transform follows.
- KWin's pointer position is a plane point. When the transform changes the
  shim warps it so it keeps its screen position; the cursor item is drawn
  at the screen position (`WorkspaceScene::updateCursor`), and screen edges
  and hot corners test the screen position, with the edge push-back warp
  mapped back to the plane. The item's position is the hotspot, with the
  image at `-hotspot` inside it, and the hardware cursor plane is an
  `ItemTreeView` of the same item (`compositor.cpp`), so the software and
  hardware cursors both follow.
- The shim uses KWin's headers for types only and links Qt Core alone. It
  resolves every libkwin function and variable with `dlsym` after checking
  the process is `kwin_wayland` and libkwin's build-id, so a KWin upgrade
  leaves it inert instead of failing to load. It disarms at
  `aboutToQuit`, and a gesture's owner is latched again at every first
  press.
- The closed-state activation rule never runs while the transform is live
  (the canvas is open then), so it always sees geometry as drawn.
- With `KWIN_CANVAS_PRELOAD_FILE=1` (the spike harness only) the file
  `$XDG_RUNTIME_DIR/kwin-canvas-preload` supplies the transform whenever the
  effect's does not. With `KWIN_CANVAS_PRELOAD_ATTACH=0` the shim loads and
  arms but never attaches, and KWin stays stock.
- Application popups (menus, combo lists, tooltips) are drawn while the
  transform is live. In 6.7.5 a Wayland popup is an `XdgPopupWindow`:
  `popupWindow` and `transient` true, `transientFor` its parent (a submenu's
  parent is the menu), `managed` true, and no type flag (`popupMenu`,
  `dropdownMenu`, `comboBox` and `tooltip` are X11 window types, read from
  `_NET_WM_WINDOW_TYPE` for override-redirect windows). `appPopups` holds
  every popup on the current activity and desktop whose chain of parents
  ends at a window shown there, in stacking order, refreshed by `resync()`
  (which `windowAdded` and `windowRemoved` schedule, as does the one-second
  timer). Popups are not entries, so nothing settles, snaps, arranges or
  commits them. KWin places a popup relative to its parent's real geometry,
  which `settle()` keeps at the parent's plane position, so each popup is
  drawn from its own real geometry with the plane transform (`s`, `o`),
  above the windows and the frame tags and below the toolbar and the
  canvas's menus (`canvasMenus`). Its drawn area is an item named
  `kwin-canvas-popup`, where `planeTakes()` hands the pointer to KWin when
  KWin finds that popup there.
- KWin constrains an xdg popup to its parent's output placement area. The
  shim hooks `Workspace::clientArea(option, window)`, which
  `XdgPopupWindow::updateRelativePlacement()` asks for that area, and
  `XdgPositioner::placement(bounds)`, which receives it relative to the
  parent, and hands the positioner the area's image in the plane, so a menu
  opens beside its parent wherever the parent is on the plane and stays
  within what the output shows. Bounds that do not match the last area
  pass through.
- While an application popup holds a grab, a press the canvas would take
  goes on to KWin (`Window::hasPopupGrab()` over `Workspace::windows()`),
  whose popup filter, after the effects filter, dismisses the popup and
  consumes the press, as a press outside a menu does at 1:1. The wheel
  stays the canvas's.
- Without the shim no popup is drawn: with the pass-through plugin KWin
  places popups at the window's real position, which the canvas does not
  keep at the drawn one, and nothing routes a click to them.

`endSlide` writes each shown window once, from its entry's canvas position
and its activity's final target, because writing a geometry makes the entry
absorb the change as a delta; windows the canvas does not show are shifted
by the slide as under a commit.

`shiftAll` moves every managed window on the current activity, or on all
activities, whether shown or not: minimized windows and other desktops'
windows keep their place on the plane under a pan, as they do under a
commit.

A touchpad swipe drives the same machinery live: the first progress value
opens quiet and records the base view, each progress value places the view
at `base - direction * step * progress`, and activation or cancellation
becomes a slide to the full step or back to the base. The fingers move the
content, so the camera goes the other way. Four `SwipeGestureHandler`s are
instantiated for the configured finger count, and re-instantiated only when
that count changes.

**Open (the overworld).** `open()` sets `zoom = 1`, records `entryView` and a copy of the
targets, snapshots every canvas window of the current desktop, on every
activity, in stacking order into `entries[] = {window, activity, x, y, width,
height}` with `x = frame.x + target(activity).x` and so on, then moves the camera to the
configured opening view (`OpenZoom`, default `1`: the current viewport, so the
overworld looks like the desktop until you move; `fit` frames every window
and frame). The per-screen delegate draws the ground, the frames with their wallpaper, the tags, the toolbar, and one live `WindowThumbnail`
per entry at `(entry - view) * zoom - screen.topLeft`. Pan changes `view`.
Zoom changes `zoom` and `view` together so the canvas point under the anchor
stays put:

```
c     = view + anchor / zoom
zoom  = z
view  = c - anchor / zoom
```

Dragging a thumbnail edits the entry in canvas units. Nothing touches KWin
geometry while the canvas is open.

Dragging a frame's name tag or edge band changes that activity's target.
With `FramesCarryWindows` (default on) every entry on that activity moves by
the same delta, snapped as one with the frames, so the group travels the
plane as a unit and its windows keep their frame geometry at commit; off,
the frames move over the windows and the windows' frame geometry changes.
The camera is never involved in what gets applied.

**Enter (step in).** The Toggle chord, Enter, or the toolbar's Enter
button enters the location under the screen centre: the frame under the
centre of the active screen names the activity, and that activity's target
is placed so the canvas point under the screen centre stays under it at
1:1, so the viewport is written where the camera is. A frame of another
activity requests the switch, and the write happens when KWin reports it;
the screen centre over no frame keeps the current activity. Then, for every entry, the activity whose frame overlaps the entry the
most wins: the window's `activities` list is set to that one if it differs
(a window on every activity stays on every activity), and
`frameGeometry = entry - target(that activity)`, with the entry taking the
new frame position first: a write in that shape is the entry's own
projection, not the user having moved the window, so it must never be read
back as a delta into the entry (the rule `settle()` states), or a second
commit after one of these writes — the chord, a stale click that lands
after the canvas hid, an activity switch — would find the entries shifted
by the first and write the window a delta off. An entry in no frame keeps
its activity. Windows not shown (minimized, hidden, other desktops) are
shifted by how much their activity's target moved, so they stay put on the
plane, and the targets the frames then sit relative to are snapshotted for
the next commit, so they are not shifted twice either. The camera is set to the current activity's target at zoom 1, the
ground offset is published, and the effect hides. `pick()` (double-click on
a window's title bar) enters that window's location: the activity whose
frame holds it, else the one it belongs to, with the target placed by
`FocusTarget`: `smart` (the default) keeps the window wholly in view and
picks, among the placements that do, the one that leaves the most window area
on screen — the offsets that keep it so are the ones that bring a neighbouring
window's edge onto the screen's, so `smartOffset()` evaluates those crossings
plus the corners and the centred placement, and a tie goes to the centred one,
which is what a window alone in view gets; `centre`
sets it to `window(centre) - screen(centre)`, so the window's centre comes
to the centre of the active screen — the frames, their windows and the
wallpaper slide together on screen, and nothing moves on the plane.
`window` sets it to `canvas(pointer) - pointer`, so the point clicked stays
under the pointer at 1:1, as a zoom-in there would, shifted the least it can
be when that would leave the window over an edge; `desktop` leaves the target
alone for a window inside a
frame and centres the active-screen frame on a window outside every frame,
which is what `centre` does for every window. A double-click on a frame
enters that location with its activity current. `cancel()` (Esc without the
plugin, the toolbar's Cancel) restores the targets and `entryView` and hides
without writing anything: back to where you were, nothing moved.

**Activity switch in a location.** `currentActivityChanged` sets `view` to the new
activity's target and republishes the ground, so the wallpaper scrolls to
where that activity's viewport sits on the plane.

**Activities.** KWin's `Workspace` exposes `activities` (ids), a writable
`currentActivity`, and `activitiesChanged` for single additions and
removals; the bulk load from the activity manager after startup arrives with
no signal, so the effect re-reads the list on every open, change, and debug
command. Names are not in the scripting API: one `DBusCall` per id asks
`org.kde.ActivityManager` for `ActivityName`, and `AddActivity` and
`RemoveActivity` back the tag's plus and trash buttons. `AddActivity`
answers asynchronously with the id, so "new activity at a window" parks the
window until the reply, then places the target, moves the window, makes the
activity current and applies. Activating a window on another activity does
not switch KWin to it. With activities disabled the list is empty and one
unnamed activity stands in.

## Why the ground has to be drawn twice

The ground must scroll with the plane at 1:1 and scale with it when zoomed.
No layer-shell wallpaper can do the first, because the client that draws it
has no idea the plane exists. So the effect draws the ground while it is open,
and a Plasma wallpaper plugin draws the same ground while it is closed. Both
use `shared/Ground.qml` with the same inputs, so the switch at open and close
is pixel-identical.

The wallpaper needs `view`, and neither a KWin effect nor a wallpaper can
export D-Bus. The effect calls `org.kde.PlasmaShell.evaluateScript` with a
Plasma script that writes `OffsetX/OffsetY` into the wallpaper's config group
on every desktop containment. That is one config write per commit, and the
wallpaper QML reads `configuration.OffsetX` live.

The ground itself is procedural: grid octaves at `base * factor^k`, each fading
in as its screen spacing crosses 14px and fully drawn by 72px, so there is
always a legible spacing at any zoom. Coordinate labels at the intersections
of the coarser octaves make each region unique. The axes through canvas (0,0)
are the one landmark that never repeats. Alternatively a tile image, mipmapped
and scaled with the view.

## KWin API facts this rests on

Verified against the 6.7.5 source, in `src/`:

- A QML effect is a KPackage of type `KWin/Effect` with
  `X-Plasma-API: declarativescript`, loaded from
  `~/.local/share/kwin/effects/<id>/contents/ui/main.qml`
  (`effect/effectloader.cpp`). The root must be `SceneEffect` from
  `org.kde.kwin`.
- `SceneEffect.visible` starts and stops the effect. The delegate is
  instantiated once per screen with `SceneView.screen` attached
  (`scripting/scriptedquicksceneeffect.h`, `effect/quickeffect.h`).
- Pointer and wheel events are forwarded to the delegate's QML scene, so
  `DragHandler`, `WheelHandler`, `TapHandler` and `HoverHandler` work as
  normal. Keys arrive through `grabbedKeyboardEvent` and reach `Keys.onPressed`
  on the focused item.
- `Window.frameGeometry` is writable and calls `Window::moveResize`
  (`window.h`). A JS object with `x, y, width, height` converts to `RectF`
  (`scripting/scripting.cpp`). No clamping happens on that path.
  `checkWorkspacePosition` runs on desktop send, output layout change, and
  placement, so those are the moments off-screen windows can be pulled back.
- `WindowThumbnail` takes `client` and `refOffscreenRendering()`s it, so
  windows that are off-screen or minimized still render live
  (`scripting/windowthumbnailitem.cpp`).
- The QML `Workspace` singleton is `DeclarativeScriptWorkspaceWrapper`. It has
  `stackingOrder`, `windows`, `activeWindow`, `cursorPos`, `activeScreen`,
  `virtualScreenGeometry`, `clientArea()`, and the `windowActivated` signal.
  It does **not** have `windowList()`; that exists only on the JS-script
  wrapper.
- `ShortcutHandler` registers a global shortcut; global shortcuts fire even
  while the effect holds the keyboard.
- Binary plugins (`plugin.h`) are `KWin::Plugin` subclasses from a
  `PluginFactory`, loaded from `kwin/plugins` for the exact KWin version in
  the factory's interface id. `InputEventFilter` (`input.h`) is exported with
  its weights (`InputFilterOrder`), and `installInputEventFilter` puts one in
  the chain. The seat (`wayland/seat.h`) takes `notifyPointerEnter` with a
  transformation matrix, `notifyPointerMotion`, `notifyPointerButton`,
  `notifyPointerAxis` and `notifyPointerFrame`; `Window::inputTransformation`
  is the global-to-surface matrix KWin itself uses, and
  `SurfaceInterface::mapToInputSurface` finds the subsurface that takes input
  at a point. `Workspace::activateWindow` raises and focuses. The scripting
  `Workspace` has no stacking-order signal; `windowActivated` serves.
- `SwipeGestureHandler` and `PinchGestureHandler` (`scripting/gesturehandler.h`)
  register touchpad or touchscreen gestures from QML: `direction`,
  `fingerCount`, `deviceType`, a live `progress` from 0 to 1, and `activated`
  and `cancelled` signals. Every gesture registered for a finger count and
  direction fires, KWin's own included, so a count KWin uses fires both.
  Pointer axis shortcuts (`Meta+wheel`) are registered from C++ only.
- `DBusCall` from `org.kde.kwin` makes an async call with `arguments` and
  `call()`.
- `org.kde.KWin /Effects reconfigureEffect <id>` reparses kwinrc and calls the
  effect's `reconfigure()`. The plain `/KWin reconfigure` does not reach
  effects.
- The QML engine caches components by URL. An edited `main.qml` does not load
  on `unloadEffect` + `loadEffect`; restart KWin.

## Layers

Back to front inside each screen's view: the plane's base, the backdrop, the
dim, the ground, the monitor frames, the windows in KWin's stacking order, the
frame tags, the HUD. A frame's interior
is a `DesktopBackground` item for its output, the current desktop and the
frame's activity, which is the real Plasma wallpaper. Plasmashell keeps one
desktop window per screen, on every activity, and swaps its containment on
an activity switch, so every frame shows the current activity's wallpaper;
the other activities' wallpapers appear only at 1:1 after switching. A faint
tint in the activity's colour sits over it so the frame reads as a sheet
even with no background window, as in the nest.

`DesktopBackground` with an empty `activity` crashes KWin 6.7 when activities
are disabled (null dereference in `updateWindow`), so the effect always
passes a non-empty activity.

**The backdrop** is the same item again, as the plane's own floor rather than
the frames' interior: `Backdrop=wallpaper` (the default) puts one
`DesktopBackground` per output at that output's place on the current
activity's frames, and tiles the wallpaper outward from there at
primary-screen steps (`BackdropReach`, 0 to 4, default 2), each padding tile
wearing the wallpaper of the output nearest its centre. At 1:1 the tile that
covers the real desktop is that desktop's own wallpaper, pixel for pixel, so
a slide draws what the screen was showing; beyond the arrangement the plane
reads as the desktop continuing instead of a grid fading into void.
`BackdropDim` (0.45) is a rect of `Background` over the tiles, so the desks
and the windows stay the subject - and it is 0 while the canvas is quiet,
where the plane and the desktop have to be the same thing. `Backdrop=grid`
is the plane as it was: no tiles, the ground's own background, the grid.
Tiles ride the same `revision` bindings the frames do, so a camera move or a
drag never rebuilds the model; `screensRev` (a hotplug, a resolution change,
a rearrange, a virtual output coming or going) does, and so does switching
activity. KWin renders one offscreen per (view, window) and shares it
between every item that shows it, so the tiles cost draw calls, not renders.

## Keys

All keys come from config. The global chords are `ShortcutHandler` sequences
(`ToggleShortcut`, `HomeShortcut`, and `PanLeftShortcut`
through `PanDownShortcut`; the pan chords default to nothing). The keys the open canvas listens for are
comma-separated Qt key names (`KeyApply` = `Return,Enter` and so on), parsed
into key codes at load and on every reconfigure by looking up `Qt["Key_" +
name]`, and the legend is rendered from the same entries. A misspelt name is
logged and skipped.

## Arranging a selection

`arrange(mode, rows, cols)` acts on the selection, or on the window the menu
was opened on: horizontal and vertical lay windows out from the selection's
bounding-box corner with `ArrangeGap` between them, cascade steps them by 40,
and tile or grid split the bounding box into cells and command each window to
its cell through `requestSize`. The menu is a `PC3.Menu` opened at the pointer
by the `MouseContextMenu` gesture, the first gesture spec to carry a button.
Attached properties inside a `Connections` handler resolve against the
`Connections` object, so the handler reads the screen through the view.

## Snapping

Drags keep unsnapped positions (`dragRaw`, `targetRaw`) and snap the moving
set's bounding box as one, so a drag can always pull away. Candidates are
every other window and every activity's frames that are not hidden. Edges snap per axis, corners
only when both axes meet the same candidate, the grid rounds left and top to
`SnapGridSize`; the nearest within `SnapDistance` screen pixels wins. Resize
grips snap the edge being dragged through `snapEdge1D`. The three toggles
start from config on each open and live in the toolbar.

## Send to

`sendTo(activity)` translates each selected window by the difference between
its current frame's target and the destination's, so it keeps its place on
screen in the new activity. `sendTo(null)` parks the set's bounding box at the
nearest of a few spots around the union of all frames, the origin first.
Activity colours come from `palettes[Palette]`; okabe-ito, tol and ibm are
published colour-blind safe sets, mono is luminance only, and tag text
picks black or white by luminance.

## Navigating

`PanHold` (default `RightButton`) is the navigate button: held down, the
canvas is being navigated, and the button is a portal into it. The middle
button is one too, with nothing to configure, so a hold of either pans the
same way. A drag of the held button pans from anywhere on the screen, because
the pan handler sits on each screen's root item, so every press on that screen
is on its delivery path — over a control, which takes the same buttons and does
what the left button would have done with it (a window body moves the window, a
frame tag or edge moves its frames, a resize grip resizes), or over the ground,
which pans. The middle button is a pan everywhere. Over a window's client area
the app would otherwise have taken the press: with the plugin or the shim live,
a button in `planeNavButtons` never reaches it, which is what turns a held
button into a portal. The hold
itself is a `TapHandler` with no policy of its own: it takes
a passive grab for the configured buttons and the middle button, so it knows
the press the moment it lands and the release the moment it lifts, whether or
not the pointer ever moves. A pointer parked at a screen edge is the whole
gesture, so the edge pans with no drag at all. The Screen Edges handlers ask
for the same hold before they toggle the canvas, so a pointer pushed into a
corner on purpose pans instead of closing it.

`edgePanStep(sg, dt)` is one tick of the edge screen's own 16 ms `Timer`,
running while a
button is held and the pointer is inside an edge band
`EdgePanMargin` screen pixels wide:
the depth in the band times `EdgePanSpeed` screen pixels per second, signed
like the drag it continues — content follows the pointer, so a pointer at the
right edge keeps the canvas moving right. A pointer off `sg` does nothing, so a
hold that walks onto another screen hands over to that screen's view. A window
in hand rides the pan — `edgeDrag()` adds the camera's own step to it, the
other way on the plane, so its screen position does not change and it keeps its
place under the pointer — which is how a window is carried past a screen edge
and into a frame that was never on screen. `EdgePan` turns the whole thing off,
and `EdgePanSpeed` 0 with it.

The wheel is not part of this: it zooms at the cursor, a notch up in and a
notch down out, with or without a button held. What the button does change is
the screen edges: `navHeld` on the effect (a count of the views being navigated
- a held button, a pan drag, or a drag a portal button is holding on a control)
stops a screen edge handler from toggling the canvas, since a pointer
pushed into a border to pan is not a push meant to leave.

## Motion

The camera is not a timeline. `viewX`, `viewY` and `zoom` are the state, a set
of velocities (`camVX`, `camVY`, `camVZoom`) is what moves them, and one
`FrameAnimation` integrates while anything is live (`camLive()`), so any motion
can be taken over mid-flight by a hand, a new destination or a commit without a
jolt and without a queue. A `Timer` and not a `FrameAnimation`: the frame
animation advances with the frames the compositor draws for the effect, so the
first step of a gesture would wait for damage the gesture has not caused yet —
the wheel sets a goal, nothing on screen has moved, no frame is drawn, and the
spring would never start. The timer steps from the event loop, and the step it
takes is what damages the scene, so the motion keeps its own frames coming. Its
dt is the interval rather than what the event loop actually took, so a busy loop
slows the camera rather than lengthening the steps an explicit Euler spring is
only stable for a fraction of a period of. Two motions fall out of
that.

**A glide** is a pan the hand let go of: `camFling(dx, dy, ms)` from the pan
handler's own record of the drag takes the hand's average velocity in canvas
units a second - under 140 screen px/s, or a slow drag, is not a throw - caps
it at a screen and a half a second, and lets `PanFriction` (3/s) fade it. The
integral of that fade is a third of the flick's speed again in distance, which
is what makes a flick feel like it carries. The pan handler only calls it when
the last motion was within 120 ms of the release, so a drag that pauses before
letting go - the way a careful placement ends - lands exactly where it was put.

**A spring** is anything with a destination: a wheel notch, a fit, an edge
opening the canvas, `camGo(zoom, x, y, [gx, gy])`. It is critically damped
(`k = w²`, `c = 2w`, `w = CamSpring` in 1/s, 14 by default, about a third of a
second) so it arrives as fast as it can without overshooting, the same easing
family KWin's own Overview uses but interruptible. When a screen point is
pinned (`camAnchored`) the anchor owns the position - the canvas point under
the screen point when the zoom started stays under it, recomputed as
`anchor.x - gx / zoom` every step - and only the scale springs, which is what a
wheel at the cursor and a pinch both are; a pinch without that jumps. The wheel
compounds from the *goal* rather than from mid-step, so a burst of notches
rides as one motion. `SmoothZoom` off makes every camera move land at once,
which is what the scenarios measure the canvas with.

**A dragged window's weight** is drawn and never measured. The entries, and so
the committed geometry, follow the pointer exactly; `noteDrag()` turns the
hand's velocity into an offset along the direction of travel (`dragLagX`/`Y`,
up to 26 screen px), a lean about the centre (`dragLean`, up to 2.2°) and a
lift, and Qt's `SpringAnimation` settles each when the hand stops, so the
picture trails and leans and then settles rather than following a curve. With
`WindowPhysics` off there is no weight at all: the velocity, the offset and the
lean are zero, so what the state reports is what the screen shows. Everything
is one per drag, not per window, which is what makes a group drag read as one
piece of paper.

## Screen edges

`X-KWin-Border-Activate` in the metadata puts the effect into the Screen
Edges settings page, which writes the chosen edges into `BorderActivate` in
the effect's config group as ElectricBorder numbers (top is 0, clockwise to
top-left at 7, the same order as `ScreenEdgeHandler.Edge`). The effect
instantiates one `ScreenEdgeHandler` per number and toggles on activation.
`TouchBorderActivate` does the same for touch edges.

KWin arms a pointer edge only after two motion events inside it that are
`ElectricBorderDelay` (75 ms by default) apart, and only re-arms it once
`ElectricBorderCooldown` (350 ms) has passed, so a push that keeps going for
longer than that toggles twice - open, then into the location. The wait
between the two events has to fall inside that window: an event that arrives
later than the cooldown is the first event of a new attempt, not the
confirmation of the old one, which is why a pointer that glides into a corner
and stops on the pixel never fires at all - it leaves one event there. A
mouse that keeps pressing fires, because KWin warps the pointer
`ElectricBorderPushbackPixels` (1) inward on the first event and the next
step of the hand lands on the pixel again.

What a border owns is KWin's geometry, not the effect's. A corner is a
`TouchTarget` (8 px) square at the intersection of its two screen sides; an
edge is a `TouchTarget`-wide band along its side that stops `cornerOffset`
(40 px) short of either end. The two never overlap, so the pixel in the very
corner matches the corner and neither of the edges meeting there: with all
eight borders reserved a push into a corner is still one toggle, which is
what the scenario checks. The scenarios push in with two events on the
border's own pixel and then stop - `push_border` in `tests/lib.sh`, one
border at a time through `set_borders`.

An edge or corner opens the canvas around the screen that was pushed, not on
the desktop it was showing: `BorderZoom` (0.8 by default, `fit`, `1`, or any
zoom) goes to `open()` as the view spec in place of `OpenZoom`, and it is
anchored at *that screen's* centre. The anchor matters on more than one
output: at 1:1 on its frames the canvas point under the pushed screen's centre
is the target plus half that screen, and pinning it puts the camera a quarter
of that centre short of the frames - `-240,-135` on a single 1920x1080 output,
and a quarter of the pushed screen's own centre on any other, so `-720` in x
for the second output of two 1920-wide ones side by side. Because the chord
uses
the same anchor on the same output, the point the push left under the centre is
the point applying comes back to, and the viewport, the frames and every window
end where the push found them.

## Several outputs

Every activity has one frame, and one wallpaper tile, per output, at that
output's place in Display Configuration, so the plane is the whole
arrangement. An activity's frame group is therefore as wide as the
arrangement, and the next activity's target stands a whole virtual screen
(plus `ActivityGap`) beyond it - two screens and a gap apart on two 1920x1080
outputs side by side. A hidden frame is a
(activity, output) pair: hidden on one output, the frame is still drawn and
still takes windows on the other, and the config records it as
`activity|screenName`.

Nothing the effect decides from "the current screen" uses
`Workspace.activeScreen`, which is the *focused window's* screen - wrong half
the time on two monitors. `actionScreen()` asks `screenAt()` for the screen
under the cursor and falls back to the active screen only when there is no
pointer: it is what a fit, a focus, an enter and a border open all use. The
pointer is also why a corner works on every output while an edge only works on
the arrangement's outer sides: KWin builds the four corner zones on every
screen (`ElectricBorderAllScreenCorner`), and no edge band in the middle of
the desktop.

A pointer a KVM switch (Deskflow, a network KVM, a remote session) drops onto
a border pixel is not a push. KWin wants two motion events on that pixel
between `ElectricBorderDelay` and `ElectricBorderCooldown`, so a single
placement - and the move away the user makes next - leaves one event there and
never arms the border. A fast traverse across a border is not a push either:
the two events have to be within `DISTANCE_RESET` (30 px) of each other, so a
pointer crossing at speed passes through. Both are what the KVM case needs, and
`kvm_drop_on_border` in `tests/lib.sh` is the placement the scenario replays.

## HUD

A Plasma toolbar (`org.kde.plasma.components`, Kirigami theme colours) on
the primary display only, which is the first output in
`Workspace.screenOrder`, the order plasmashell sets. `HudPosition` picks an
edge or corner, and `HudShape` the flow: one `GridLayout` whose flow, rows
and columns follow the shape, with the label spanning the square's width and
the separators hidden there. It shows the current activity and zoom, one swatch per activity, the camera
actions, Enter and Cancel, a help panel rendered from the binding config, and a menu that opens
the settings pages through `KCMLauncher.openSystemSettings`, as Overview does.

## Known limits

- **Frames are not editable.** They are the outputs in KDE's display
  arrangement, read from `Workspace.screens`; changing that layout is
  Display Configuration's job and the frames follow.
- **Frames share one wallpaper.** Plasmashell has one desktop window per
  screen, so every frame shows the current activity's wallpaper.
- **Activity changes are asynchronous.** Adding, removing or switching goes
  through the activity manager; the canvas follows when KWin reports it.

- **No interaction in the overworld** without the plugin or the shim: the
  canvas is then a navigation view. With either the overworld is
  interactive, pointer and keys, and Esc belongs to the focused window. With
  the plugin a window's popups are not drawn: they open at the window's
  real position, off screen if the window is. Under the shim they are
  drawn, from their real geometry; a popup of a window on another activity
  or desktop never opens, since KWin does not show that window.
- **Output changes.** Hotplug or resolution change runs
  `checkWorkspacePosition` on every window and may pull far-off windows
  toward the new layout. The effect re-derives from geometry so nothing is
  lost, but positions can shift.
- **X11 windows** have 16-bit coordinates. Beyond about ±32k canvas pixels
  they cannot be placed.
- **Persistence.** `view` lives in the effect object and resets to (0,0) when
  KWin restarts. Window positions survive since they are real geometry, but
  the ground offset does not until the next commit.
- **Stock Zoom effect** binds Meta+wheel. Disable it or rebind.
- **Untested live.** The `evaluateScript` handoff and the wallpaper plugin have
  been rendered in isolation but not yet run inside a live plasmashell.

## Next

- Snap `zoom` to 1 with a short animation on commit.
- Drawing limits: a drawn sheet boundary that only grows, and `ZoomMin` from
  it rather than a constant.
- Pan on a screen edge push at 1:1: the edge handlers fire once per push, so
  each push would be one step.
- Auto-pan when dragging a window to the screen edge at 1:1. The move is
  KWin's; the effect can watch `Window.move` and shift the plane on a timer.
- Bookmarks, and a minimap while the canvas is open.
- Persist `view` in the effect's config on commit.
