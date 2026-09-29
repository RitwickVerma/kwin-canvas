Unreleased:

- Pin a window and it follows you everywhere: a pinned window is screen-fixed
  - it rides the camera and never leaves the screen, this model's "on all
  desktops" - and it bounces with real physics when pushed past a screen
  edge, overshooting and settling back into view. Pin and unpin from a
  window's arrange menu; the pin survives restarts, by caption, in
  `PinnedWindows`.

- Clicks focus. A click on a window's title bar activates the window - with
  the pass-through plugin a client-area click already activates it natively,
  so a click anywhere on a window now means the same thing - and the hover
  makes a window the canvas's focus: the settled hover wears a soft glow in
  the activity's colour and Enter applies with it, so the keyboard always
  knows which window is yours. A click with a few pixels of hand noise no
  longer grabs the window: the drag, and the lift that announces it, both
  wait for a real drag.

- Opening over a fullscreen app steps out a little (`FullscreenZoom`, 0.85 by
  default; 1 keeps the ordinary opening): a fullscreen app at 1:1 is exactly
  the desktop, so the step out would have been invisible. The chord and the
  canvas modifier both use it, and the modifier's release springs back to 1:1
  at the committed viewport.

- The glass: the hovered window wears a soft glow in the activity's colour,
  and the toolbar reads as glass instead of a slab.

- The capture lifecycle is airtight. A lingering hover over a window pans the
  camera the least that fits it wholly into view. The hover navigation
  shipped with a bug the nest never caught: the thumbs restarted the hover
  timer through an id, which is not a property an outer scope can reach, so
  every hover in a live session threw - the hover is now polled in the effect
  itself, which also makes it work over a window's client area where the
  pass-through plugin consumes the pointer, and it waits out a grace period
  after any gesture so it never fights the hand that just dragged a window.
  A close asked for while a gesture is in hand - the chord mid-drag,
  releasing the modifier before the window - parks itself and runs the moment
  the buttons come up, so the canvas never hands a still-held button to the
  desktop, where its motion would be a native drag on whatever is under the
  pointer.

- Stepping in and out is flickerless. A close asked for while the chrome is
  still up - stepping in from 1:1, a cancel with nothing to fly back from -
  fades the frames, the tags and the toolbar out before the canvas hides,
  instead of cutting them in one frame.

- The modifier is a hold, not a press: MB4 must stay down for a moment
  (300 ms) before the canvas opens, and a quicker press passes through as
  the window's own click - the button stays usable in games, browsers and
  every app that binds it.

- The edge pan scrolls the natural way: a pointer parked at a screen edge
  pans the view toward the edge, revealing what lies beyond it, the same
  direction as dragging the desk away - it used to move the content the
  other way.

- Releasing the modifier commits to where the hand left off: a pan during
  the hold becomes the location's new viewport, so the release enters the
  screen at that coordinate instead of snapping back.

- The nest harness waits until the effect answers its first command: KWin
  reports the effect loaded before its QML completes, and a command sent in
  that window was lost, which is what the intermittent empty-state flakes
  were. The effect also runs a pending command at completion, so a nest's
  first command is never swallowed.

- Everything that focuses a window flies to it through the canvas. Activating
  a window from the task manager - Alt-Tab, an application grabbing focus,
  anything - slides the whole desktop until the window is wholly on screen,
  centred in its placement area, and a window hanging half off the screen
  counts as not visible: a focused window is never left outside the scene.

- The canvas modifier: holding MB4 (`CanvasHold`, the back side button)
  anywhere on the normal desktop makes the location itself the canvas at 1:1
  - nothing visibly changes - and the overworld's gestures work: the middle
  button grabs and pans, a drag on a window moves it on the plane, the wheel
  zooms, an edge keeps panning. Releasing applies the moves and closes:
  hold, arrange, let go, done. Needs the pass-through plugin (or the shim),
  which now sees the press while the canvas is closed and consumes it.

- MB5 while the modifier is held (`SwapButton`) flies between the two most
  recent windows, an Alt-Tab on the plane: the camera springs to the other
  window, the focus follows, and releasing opens the location there, focused
  on it. The last two activated windows are the swap's pair.

- The pointer navigates: a click on a window, or a hover that rests on one
  for a moment, pans the camera the least that brings the window wholly into
  view, so what the eye lands on is what the screen shows.

- The in-canvas pan keys are WASD (the arrows are still there to bind), and
  `KeyFit` is F alone - W is the pan key now.

- The haze fades instead of switching: the blurred wallpaper softens away as
  the desk fills the view on the step in and back on the step out, and at
  rest under the desk it is gone and costs nothing.

- The settings form was rewritten for people: groups in the order of use,
  combo boxes for the fixed choices, one plain sentence per knob, and the
  canvas modifier and the swap get their own group.

- Stepping in and out is a flight, not a cut. Every step in - the chord, the
  Enter key, a double-click on a window or a frame, the toolbar's Enter -
  springs the camera to the location's viewport at 1:1 and only then writes
  the windows, where the thumbnails and the real windows already agree, so
  nothing on screen ever jumps from the overworld into a location. Cancel
  flies back the same way. The overworld's chrome (frame borders and tint,
  tags, toolbar, help) fades on the way in and back in if a grab interrupts
  the flight, and a drag, a wheel or another camera move mid-flight simply
  cancels the step in: the canvas stays open where the hand left it. With
  `SmoothZoom` off every step lands at once, as before. Home, the canvas
  origin and the activity swatches take the same spring, and a spring starts
  moving on the frame it is asked for rather than the one after.

- Stepping out fades in: the chrome fades in on open, and when the opening
  view moves the camera (fit, `BorderZoom`, a numeric `OpenZoom`) the windows
  fade in after it, so a step out to fit draws its subjects in instead of
  popping them. An open at 1:1 is still the desktop, and a quiet slide is
  still the desktop exactly - neither fades.

- The plane beyond the desks is the wallpaper in a haze instead of repeated
  tiles. `Backdrop=wallpaper` (the default) keeps the desktop's own wallpaper
  exact on the frames and draws it once per output, screen-fixed, blurred
  (`BackdropBlur`, 48 px by default) and dimmed (`BackdropDim`, 0.45), with
  the ground grid over it - the desktop dissolving into a haze, live (a
  slideshow or a picture of the day keeps going in it), and costing nothing
  while the camera sits at 1:1 on the desk, where the blur would be invisible
  anyway. `BackdropReach` and the tiling are gone; `Backdrop=grid` is the old
  plane.

- `BorderSlide` makes the screen edges a route around the plane instead of a
  door in and out of it: a push into a configured edge or corner pans the
  plane one step toward the pushed side - a slide at 1:1, a springing camera
  step in the open canvas - and a push while a slide runs chains another
  step. The chord, the toolbar and the panel button still open the canvas.

- The open canvas is navigable from the keyboard, with defaults nothing else
  uses: WASD pan the camera one step, Tab and Shift+Tab step the
  selection through the windows with the camera following to keep the chosen
  window in view, and Enter with a window selected steps into it focused -
  the overview's Tab-then-Enter pattern on a canvas - while a bare Enter
  enters the location under the screen centre as it always has.

- `PanHold` defaults to empty - the middle button always navigates, and the
  canvas modifier and the swap take the side buttons. The effect names the
  buttons
  the way KWin delivers them: MB5 arrives as Qt's ExtraButton3, not
  ForwardButton, so both values are in the mask the plane-input shim and the
  pass-through plugin compare against.

- The camera can carry an arrival callback: the step in and the cancel leave
  their landing there, so the commit or the restore runs the moment the
  camera arrives and is dropped by any takeover. `make test` grows three
  scenarios for the flights, the border slide and the keyboard (100, 101,
  102), and the backdrop scenarios (91, 93) measure the haze.

- A PanHold button is now a portal into the open canvas rather than a pan that
  only works where the canvas already had the pointer. With the pass-through
  plugin or the plane-input shim live, a press of the button was handed to the
  window under it and never reached the canvas at all; the effect now publishes
  the mask (`planeNavButtons`; `setNavButtons` over D-Bus for the plugin) and
  both routes leave those buttons to the canvas wherever they land, client
  areas included. Held, a drag on the ground pans, a drag on a window moves
  that window on the plane — by its client area too — and a drag on a tag or a
  frame edge does what it does with the left button. A click still opens the
  arrange menu, and the middle button still pans from anywhere. `BackButton`
  and `ForwardButton` (a mouse's side buttons) are accepted in `PanHold` for
  anyone who wants the portal off the right button.

- An edge pan with a window in hand takes the window along: hold a navigate
  button (`PanHold`, the right button by default) on a window, push the pointer
  to a screen edge and the canvas keeps panning with the window riding it. The
  camera's step
  is added to the window the other way on the plane, so its screen position
  does not change — it stays under the pointer while the desk, frames included,
  travels under it — and it can be pushed past a screen edge and into a frame
  that was never on screen.

- `FocusTarget=smart`, now the default, is where a double-click on a window
  lands the desk: the window comes wholly into view, and among the placements
  that keep it so, the one that leaves the most of the other windows on screen
  wins, so stepping back to a window no longer throws its neighbours off the
  screen. The offsets that change what is in view are the ones that bring a
  neighbouring window's edge onto the screen's, so those crossings, the corners
  and the centred placement are what gets compared, once per gesture, by the
  same target the other modes move — no window is written, moved or restacked.
  Ties go to the centred placement, so a window alone in view lands exactly
  where `centre` has always put it, and `centre` itself is unchanged for anyone
  who wants it. `window` now also shifts the least it can when pinning the
  clicked point would leave the window hanging over a screen edge.

- The open canvas is navigable by holding a button: `PanHold` (the right
  button by default) pans on drag from anywhere on the screen, windows and tags
  included, and a pointer parked at a screen edge keeps panning that way
  (`EdgePan`, `EdgePanMargin`, `EdgePanSpeed`), with the wheel zooming at the
  cursor throughout. The middle button navigates the same way with nothing
  configured — held or dragged, a drag or a parked pointer at an edge alike.
  A navigate button held at a screen edge no longer toggles the canvas through
  the Screen Edges handlers.

- The plane is the desktop's own wallpaper. `Backdrop=wallpaper` (the default)
  puts one `DesktopBackground` per output at that output's place on the current
  activity's frames and tiles it outward from there at primary-screen steps
  (`BackdropReach`, 0 to 4, default 2), so what lies beyond the desks is the
  wallpaper continuing rather than a grid into void, and a slide at 1:1 draws
  the desktop that was on screen. `BackdropDim` (0.45) keeps the desks and the
  windows on top of it, and is 0 while the canvas slides at 1:1, where the
  plane and the desktop have to be the same thing. `Backdrop=grid` is the plane
  as it was.
- The camera moves under physics instead of a timeline. A wheel notch, a fit or
  a border opening the canvas springs to its destination with the point under
  the cursor pinned (`SmoothZoom`, `CamSpring` 14/s, critically damped, so it
  arrives without overshooting and can be taken over mid-flight); a flicked pan
  keeps going and slows under `PanFriction` (`PanInertia`), while a drag that
  pauses before letting go still lands exactly where it was put. `SmoothZoom`
  off is the old instant camera.
- A dragged window carries weight (`WindowPhysics`): it lifts, trails in the
  direction of travel and leans with the hand, and settles on Qt's springs when
  the hand stops. Drawn only - the entries and the committed geometry are exact
  either way, so what the canvas commits does not depend on how it looked while
  the hand was moving.
- A screen edge or corner opens the canvas stepped out around the screen that
  was pushed (`BorderZoom`, 0.8 by default; `fit`, or `1` for the desktop
  exactly as it was), anchored at that screen's centre, so a push shows the
  desks around that monitor rather than the desktop already on it. The chord
  enters the point the push came from, on the same screen.
- Multi-monitor correctness. Nothing asks `Workspace.activeScreen` - the
  focused window's screen - for "the current screen" any more: a fit, a focus,
  an enter and a border open all follow the screen the pointer is on. Every
  activity has a frame, and the backdrop a wallpaper tile, per output; a hidden
  frame is hidden per output; and the frames and the tiles re-derive on a
  hotplug, a resolution change, a rearrange, or a virtual output coming or
  going. A pointer a KVM switch (Deskflow, a network KVM, a remote session)
  drops onto a border pixel no longer opens the canvas, and neither does a fast
  traverse across one: KWin wants two events on the pixel between its delay and
  its cooldown.
- `make test-two-outputs` runs a two-output nest (`NEST_OUTPUTS=2`), where
  `91-two-outputs` covers the per-output frames, the fit, the corner push and
  the enter on the far output; `93-backdrop` covers the wallpaper tiles, their
  reach and the dim, and `94-physics` covers the springs, the glide and the
  window's weight. `dev/nest.sh` seeds the motion knobs off so the other
  scenarios measure the canvas rather than the spring, and `tests/lib.sh` grows
  `setcfg`, `screenrect`, `screenname`, `push_border_on` and
  `kvm_drop_on_border`.

- With the spike shim of `dev/spike/preload` preloaded into kwin_wayland
  6.7.5, KWin's pointer chain works in plane coordinates and the open
  canvas shares input with the windows it draws: pointer over a window's
  client area goes to the window, every key to the focused window; title
  bars, edges, frames, tags, ground and toolbar stay the canvas's. The
  effect publishes its transform as properties the shim reads in-process,
  and KWin runs stock whenever the canvas is closed, quiet or unloaded.
  The cursor is drawn at the screen point and screen edges stay on the
  screen. The pass-through plugin stands down under the shim. `make
  test-shim` runs the shim scenario; see docs/testing.md.
- A window raised while the canvas is open restacks at once, and a drag or
  resize follows the window it started on when the stack changes under it.
- Application popups in the overworld under the shim: menus, submenus,
  combo lists and tooltips of the current activity's windows are drawn
  where KWin has them, above the windows and below the toolbar, and take
  the pointer. A menu opens beside its window wherever the window is on
  the plane, kept within what the screen shows. A click outside an open
  menu closes it, as at 1:1. Without the shim popups are still not drawn.
- The nest harness keeps the nest's D-Bus daemons (portals, the activity
  manager, the secret service) off the live session's compositor and X
  display, `down` stops them (it used to miss them, so they outlived every
  nest as clients of the live session), and every call that needs the
  nest's bus fails when it is missing instead of reaching the session bus.
  A nest runs niced at idle I/O priority with its compositor off SCHED_RR,
  launches the fixture apps one at a time, keeps its caches under its own
  state directory, and no longer lets kded's GTK module write
  `~/.gtkrc-2.0`.

0.4.0 is the overworld: one chord out and back in, and the open canvas is
a live desktop.

- Two places. A location is an activity's screens at 1:1 with the canvas
  closed: stock Plasma, nothing of ours running, so games and fullscreen
  apps get KWin's native path. The overworld is the open canvas: every
  window live on the plane, the frames with their wallpaper, tags and the
  toolbar.
- One chord steps out and back in. Toggle Canvas now defaults to
  Meta+Ctrl+Alt+Space (was Meta+Space); KDE keeps an existing binding in
  kglobalshortcutsrc, so rebind by hand if you want the new one. Stepping
  out opens at the current viewport at 1:1 (`OpenZoom` default is now `1`;
  `fit` is still there). Stepping in enters the location under the screen
  centre, switching activity if that is another activity's frame, and
  writes the viewport where the camera is. Double-click a window's title
  bar or a frame to enter that location.
- Pass-through is live whenever the canvas is open, with the plugin loaded:
  pointer over a window's client area goes to the window, every key goes to
  the focused window, Esc included. Title bars, edges, frames, tags, ground
  and toolbar stay the canvas's; select windows from the title bar. Setting
  `Passthrough`, default on.
- Pan mode is gone. The slide stays: pan chords, the touchpad swipe,
  `PanStep`, `PanDuration` and activation-follow move the viewport within a
  location.
- Toolbar: Apply is now Enter; Cancel is back to where you were, nothing
  moved.
- `kwin-canvas`, a terminal CLI: `exit`, `cancel`, `open`, `toggle`,
  `status`. Works from a virtual terminal, the fallback when the chord does
  not reach the open canvas, and the way to toggle from a script or start
  in the overworld at login (`open` waits for the effect; an autostart
  entry is in docs/install.md, `AutoActivate` is the other route). `make
  install` puts it in `~/.local/bin`; the package in `/usr/bin`
  (`qt6-tools` is now a dependency).
- A Plasma applet, `kwin-canvas-toggle`: a panel button that fires the
  Toggle Canvas chord.

0.3.1 fixes where the pass-through plugin installs: Qt 6's plugin directory
(`/usr/lib/qt6/plugins/kwin/plugins`), which KWin searches; 0.3.0's package
put it under Qt 5's. Nothing else changed.

0.3.0 is about moving at 1:1 and reaching into windows from the canvas.

- Panning at 1:1 is a slide: the effect opens for a moment with no chrome,
  this activity's windows glide, their new positions are written once. Pan
  chords (Canvas Pan Left, Right, Up, Down; no default chord) step half a
  screen; a three-finger touchpad swipe follows the fingers.
- Pan mode: hold a chord (Canvas Pan Mode; no default chord) and drag the
  desktop with the mouse as often as you like, wheel to zoom out and see the
  whole plane, let go to settle with the point under the pointer kept, Esc
  to slide back.
- The pass-through plugin, `kwin-canvas-passthrough`, optional and built
  against your KWin: in pan mode, clicks, drags and the wheel reach the
  real windows, a click raises, title bars and edges move windows on the
  plane. Its own AUR package; rebuild it after a KWin upgrade.
- Double-click a window: the window's activity takes the viewport, the
  window comes to the centre of the screen and it takes the focus; a window
  in another activity's frame takes you there. `FocusTarget` chooses where
  the viewport goes: `centre` (default) brings the window's centre to the
  screen centre, `window` keeps the point you clicked under the pointer at
  1:1, `desktop` leaves a frame put and only centres a window outside every
  frame.
- Dragging an activity's frames carries its windows along
  (`FramesCarryWindows`, on by default).
- Activation-follow moves minimized and other-desktop windows of the
  activity too, so the plane stays whole under a pan.
- The test nest renders to KWin's virtual backend, so the scenarios keep
  their timing when the nest is not on screen.

0.2.0 makes activities the frame axis and adds a short install path.

- Every activity is a group of monitor frames on the plane, in KDE's output
  layout. Drag windows into an activity's frames, drag frames over windows,
  apply. Switching activities at 1:1 switches viewport. Virtual desktops
  stay ordinary desktops; the canvas shows the current one.
- Frame tags: add an activity, remove one, and an eye that hides that frame
  for that activity and display. A hidden frame is not drawn and takes no
  windows.
- Selection (click, Shift+click, Ctrl+click, Shift+drag marquee), group
  drag with geometry kept, and an arrange menu on right-click: horizontal,
  vertical, tile, grid, cascade, send to an activity or to the plane.
- Snapping to edges, corners and the grid, with toolbar toggles.
- Colour-blind safe palettes for the frame colours.
- `configure.sh install | uninstall | enable | disable | status | try`, one
  Makefile target each, and `make install-system` with DESTDIR for distro
  packages. Enabling now loads the effect by name; KWin's plain reconfigure
  never did.

Install from a checkout with `./configure.sh install`, or:

```
kpackagetool6 --type KWin/Effect --install kwin-canvas-0.2.0.kwineffect.tar.gz
kpackagetool6 --type Plasma/Wallpaper --install kwin-canvas-ground-0.2.0.tar.gz
```

then enable "Canvas" in System Settings → Desktop Effects. KWin keeps the
effect it compiled at login, so after an upgrade log out and in once.
Tested on Plasma 6.7.5. Alpha: the effect moves real windows; try it in a
nested session first (`make play` from a checkout).
