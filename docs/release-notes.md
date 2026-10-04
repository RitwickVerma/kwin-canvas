Unreleased:

- The overworld shows every desktop, not just the one you are on. Each
  virtual desktop appears as its island on the plane: the current one
  live, the rest as dimmed named tiles with their windows' outlines -
  and a click on a tile switches to that desktop. The switcher's fit
  now frames every island too, so stepping out of a three-desktop
  session sees the whole place at once.

- Desktops are islands on the plane. Every virtual desktop is a place: its
  windows live at the desktop's own offset, a row of islands laid out below
  one another, and switching desktops flies the camera to the new island -
  or quietly slides there at 1:1. Pills in the overworld name each island
  and a click on one jumps straight to it, and the 1:1 seam holds on every
  desktop, because the windows and the camera sit at the same offset. The
  Arrange menu's "Desktop from this cluster" promotes a cluster into a real
  KWin desktop: the derived grouping becomes declared workspace state,
  visible in the pager and the taskbar, surviving restarts, and the new
  desktop keeps its island. `make switcher-free` unbinds KWin's own TabBox
  chords so Meta+Tab and Alt+Tab drive the canvas switcher, and the panel
  button's tooltip now carries the cluster and desktop count.

- The dock, the panels and the applets' dropdowns own their pixels. A
  click, a hover or a rest on the system's own chrome no longer focuses
  the window drawn under it, no longer flies the canvas to it - not in
  the closed location, not in the open overworld, not during the hold -
  and resting the pointer on the dock during a hold no longer keeps the
  canvas edge-panning underneath it. The chrome gets every pointer event
  natively, exactly as it does when the canvas is closed.

- The canvas sheds its finery as the system loads up. It watches the
  machine's real CPU and GPU load and steps down a ladder - reduced (the
  backdrop blur, the unlit constellation and the lens's edge blur go),
  minimal (the whole cluster web, the standing shadows, the z-depth and the
  float bob go), then bare (the live window pictures become named
  rectangles) - and climbs back up when the machine breathes, two calm
  samples at a time so it never flutters. Whichever channel sees the worse
  pressure sets the step: a game saturating the GPU degrades the canvas
  even while the CPU idles. Panning, zooming, clicking and the
  pass-through never degrade; only the eye candy does. The QualityMode
  knob holds a step, and the six thresholds are hidden knobs.

- The overlay is gone: the world is the map. Zooming out during the hold
  turns the windows themselves into the map's sheets, the cluster chips
  float on the plane where their clusters live, and a click on a window
  flies it to 1:1 - the release lands there. The grasp still teaches
  itself, with the hint strip sitting on the world. The switcher opens
  fitted to the whole plane, and the corner lens in the overworld stays.

- The switcher is TabBox-style: hold Meta+Tab or Alt+Tab (bind them over
  KWin's own task switcher) and the canvas opens fitted to the whole
  plane; tapping the chord again steps the selection through the windows
  with the camera following, releasing the chord or pressing Enter steps
  into the chosen window, and Esc steps back out. The minimap's corner
  chip also steps clear of the toolbar now instead of covering it.

- The camera is NaN-proof: a diverged spring, a poisoned pan or a bad
  zoom request can no longer write a non-finite position into KWin's
  window geometries. The commit and the slide refuse a non-finite camera
  (and reset it), and a NaN zoom request keeps the current zoom instead
  of poisoning every calculation downstream. A stress scenario hammers
  the camera with spring flights, pan bursts and a mid-flight grasp to
  prove it stays finite and answering.

- Camera motion no longer re-weaves the threads: the cluster threads
  are now clipped in the plane's own coordinates once per layout change,
  and the camera is a single cheap transform per frame, so a fly or a
  zoom no longer re-runs the weave for every window pair on every frame.
  The camera rectangle's blur pass switches itself off the moment it
  has nothing to blur.

- A step in retires the skin across the whole flight: the threads, the
  frames and the rest fade out evenly with the flight's own progress
  instead of blinking out in the spring's last frames, and the unlit
  constellation dissolves between 0.45 and 0.5 instead of cutting out at
  half zoom. Stepping out still brings the skin in fast, full by 0.75, so
  the reveal stays quick while the goodbye is gentle.

- The whole interface wears one skin: the chrome - the frames, the tags,
  the standing shadows, the glow, the cluster badges and the web - reveals
  with the zoom on every path, instead of the chord's overworld wearing
  everything at 1:1 while the grasp's keyhole wore nothing. Stepping out
  now lands on the same calm desktop the location was, and the skin comes
  out as the camera leaves, whether the canvas opened through the chord or
  the hold. (A transient slide still wears nothing, so the fly stays the
  seamless desktop it is.)

- The toolbar shows whose hand is on the pointer: a dot beside the
  activity swatches that fills when the pass-through has handed the
  pointer to a window, and stays hollow while the canvas holds it.

- The bookmarks are surfaced: the help panel lists every saved spot with
  its name, so the digits are discoverable instead of secret.

- The cluster threads are now real depth: each thread travels the z
  between its two windows - over the lower, under the higher - and ducks
  under any window that covers a stretch of it, the way a line through
  the stack should. A thread no longer sails over a window that happens
  to sit on top of its path; the constellation re-weaves live with every
  hover and restack.

- The seams no longer fade through black: KWin composites the canvas's
  scene over black, not over the desktop, so the earlier crossfade was
  really a fade-to-black, and the black was the flash. The quiet scene at
  1:1 paints the same pixels as the desktop it covers - the thumbnails sit
  over the real windows at the same place - so the seams are now instant
  swaps, invisible where the pictures match, and a fade only remains where
  the picture genuinely jumps (a close from a zoomed-out overworld). The
  quiet slide opens opaque and glides after the first paint has warmed the
  thumbnails; it writes the geometries and closes the moment it arrives.
  The chrome stays up through a flight too - the frames, the tags and the
  toolbar no longer wink out when the camera sets off and back when it
  lands.

- The hover that hands the pointer over is now a knob - HoverDelay, a
  deliberate 900 ms by default: a quicker pass-over stays the canvas's,
  so sweeping across the overworld never activates a window by accident;
  only a real pause lets the pointer through to the window under it.
  (The wheel is held to the same rule: a wheel over a window during the
  rest stays the canvas's instead of zooming it.) Underneath, the delay
  knobs had been silently dead - QML numbers are doubles and QDBus does
  not demote them to the plugin's integer slots - and now they land.

- The stacking is now visible: every window wears its height in the stack
  as a standing shadow and a hair of size - the higher a window sits, the
  deeper its shadow falls on what is below and the larger it reads - and
  the stack re-settles live as the eye moves, since the hover that raises
  a window for real slides the whole pile up with it. The quiet slide is
  untouched: at 1:1 the shadows and the size stay off, so the fly remains
  the seamless desktop it is.

- The grasp's overlay now waits for its business: it steps in only while
  the hold has zoomed out and there is more than one cluster to navigate
  - with one cluster the plane is a single hop, so the map stays out of
  the way. A hold in the open overworld brings the map back the same way,
  and releasing it returns to the overworld where it started.
- The map is the navigation surface: a drag that starts on a sheet or the
  map's empty ground pans the camera - it never falls through to the
  window drawn underneath and grabs it - and the camera rectangle's drag
  counts as a gesture, so a release mid-drag defers the close like every
  other hold. Only a left click flies a sheet; right and middle are for
  the windows' own menus, not for jumps.
- The canvas can narrate itself: the `verbose` debug command (or the
  `Verbose` knob) writes every decision - opens, commits, cancels, hold
  branches, map clicks - to KWin's log as a `[canvas]` line with the
  state it left behind, and the pass-through plugin's own
  `canvas-passthrough:` lines follow the hold, the hover and the click
  replay.

- The cluster web is overworld chrome: the threads fade out as the camera
  returns toward 1:1 and are gone by the time the location itself is
  showing, so the normal-mode flights - hover nudges, pick steps, Tab
  travel - are a plain canvas slide with no threads, no badge and no
  overworld dressing around the windows. (At 1:1 the lit web was painting
  white lines straight over the desktop.)
- The camera spring's rate is capped at 32: above that the spring's
  stepping becomes unstable (measured: a CamSpring of 30 on a flight
  diverged the view to 2.7e253), so the knob is honest about the cap in
  its description.

- The cluster threads now weave through the windows: each thread renders
  at the z between its two windows, so the web passes over the lower and
  under the higher - and re-threads live as the eye moves, since a hover
  lifts its window above the whole web and the threads to it ride up with
  it. (The web's z was previously inert, so the threads sat under every
  window; the hover's raise also makes the canvas z order exactly the
  desktop's.)

- A pointer parked on the desk's outer seam - where deskflow and its kin
  leave the mouse while another machine has it - no longer hovers the
  window under it: the seam is a dead band for hover, in the canvas and
  in the pass-through alike, so a shared mouse never glows a window or
  pans the camera by itself.
- The fly's landing no longer flickers: the quiet slide fades out over the
  desktop it slid to (and in when it opens), so the inactive windows'
  decorations, the panel and the shadows step back in under a fade instead
  of a one-frame cut.
- A hover in the overworld now raises the window for real: the rest that
  focuses a window puts it on top of the canvas and of KWin's stacking
  together, and the raise survives the step back in - what was on top in
  the overworld is on top in the location.

- The map wears real glass: the overlay's sheets frost the live windows
  behind them as they sharpen in, and the corner lens keeps its blur - one
  glass riding both homes through the morph, at half resolution so it costs
  a quarter of the pixels.
- The plane transform (screen-to-canvas, the zoom anchor, the fit) moved
  into logic.js, the unit-tested pure half.

- An applet's dropdown no longer flies the desktop: special overlays join
  panels, docks and popups on the never-fly list, so clicking around the
  panel leaves the camera alone.
- The pass-through is regression-tested at zoom: a new scenario proves the
  handoff and the click land at the picture's own place when the overworld
  is zoomed out.

- The float follows the window's own screen on several outputs: a floated
  window bounces against the bounds of the monitor it lives on, not the
  pointer's.

- The micro-feel: a single click pans after a beat instead of waiting out
  the whole double-click window (the second tap still cancels it), the
  camera lands instead of crawling its last pixels, the hover glow fades
  in and out instead of popping, and the idle handover publishes itself,
  so the canvas and the tests can see whose the input is.

- The pass-through engages on a rest: the pointer must hold still on a
  window for a beat before the window takes the input - sweeping across
  the overworld stays the canvas's, and only a deliberate rest hands it
  over. A click is the intent itself and takes the window at once.

- The switcher: the hold's map as a toggle - `SwitcherShortcut`
  (Meta+Tab; bind it over KWin's own Tabbox in the shortcut settings) -
  the whole plane appears, Tab and Shift+Tab step the highlighted
  window, Enter enters it, Esc or the chord steps back out. The window
  switcher the plane deserves.

- The camera's rectangle is an instrument: drag it across the map and
  the view follows.

- Every fly is smart: the swap, the grasp's map jump and every path that
  moves the canvas to include a window now take the least movement that
  keeps the most of the desk in view, and a fly slides to a fresh
  destination - it never chains onto a previous fly's half-travelled
  slide, which is what had windows ending up past the screen when two
  activations came close together.

- The web is tethered: the threads ride the windows' own bob, so the
  lines weave with the float instead of hanging where the centres were.

- The pass-through is heavily scoped: the keys belong to the window only
  while the pointer hovers one - the moment the cursor is over the
  ground, the frames or the gaps, the canvas has the keys back - on top
  of the idle release.

- The hold's overlay is the essentials: no shroud, just the floating
  window chips and the viewport, the desktop showing through untouched.

- The windows float: as the camera steps out of the location the
  windows hover in Z, each bobbing gently at its own phase, the depth
  ramping in with the zoom-out - and the cluster web rides the middle of
  the float, weaving over some windows and under others as they bob, so
  the overworld feels alive. The hold's sheets share the phases, and the
  keyhole widens into the overworld only on a deeper zoom-out, so a
  slight step back still commits the location.

- The threads are a web: plain thin lines behind the windows, every
  window in a cluster joined to every other - the constellation reads in
  the gaps, never over the glass.

- The hold's sheets are visible again, redesigned rather than diluted:
  soft glass fills with clear hairlines, the hovered one brighter and
  named - present without the busyness, since the frames' outlines and
  the shroud stay gone.

- The swap is fixed: MB5 during the hold flies once (its own flight
  suppresses the activation's, so the windows no longer jump), and in
  the overworld MB5 reaches the canvas through the plugin and tours the
  clusters.

- The camera's rectangle floats: a soft halo under a rounded glass chip,
  it melts away when the view dominates the map - the full zoom-out no
  longer paints a huge slab - and the moment a step in begins it expands
  to take the whole map while the map's content fades with the chrome:
  the world's window becoming the screen. The minimap's dark region
  bleeds into the plane instead of ending at a line.

- The pass-through lets go on its own: after four seconds with no input
  the canvas takes the input back - the keys, the wheel and the clicks
  are the canvas's, the Esc the user reaches for is the canvas's cancel,
  not the window's - and the pointer's next touch takes the pass-through
  back. Typing and scrolling never wake it; only the hand does.

- The thread whispers: thinner and fainter, a sparse dash drifting slowly
  along the curve over a soft halo - the constellation reads as light,
  not a drawing.

- The hold's map is quiet: the shroud is a whisper, the frames' outlines
  are the minimap's alone, and the windows are hairline sheets - the
  hovered one fills softly and names itself. The overlay sharpens out of
  a haze on the hold and dissolves back on the release, the slow blur
  transition.

- The pass-through waits for the aim: the first pointer motion after the
  overworld opens settles the filter, and until then buttons and the
  wheel belong to the canvas - the wheel right after opening zooms the
  canvas instead of scrolling the window under the pointer. The window's
  own area wears the open hand, so the title bar and the edges read as
  grabbable while the client area keeps the app's cursor.

- The float is the window's own "keep above": right-click any window and
  tick Keep Above Others, and it floats - the title-bar menu's
  always-visible entry and the canvas agree on what floats, and the
  canvas's Float/Unfloat toggles the same flag.

- Entering syncs a floated window to its picture: a hold that pans the
  camera off a floated window and releases commits the picture's clamped
  spot, so the window never lands off-screen.

- The map is one living picture with two homes, and the hold's release is
  the path between them: hold MB4, zoom out - the camera steps out of the
  location - and release, and the keyhole widens into the overworld: the
  chrome fades in and the full-screen sheet morphs down into the corner
  lens. Zoomed in, the release commits the location as it always has, so
  the zoom is the semantic: in, you arranged the desk; out, you stepped
  into the world.

- The modifier's hold is the switcher: while MB4 is down the whole plane
  appears as a translucent map over the screen - the frames as border-only
  outlines, the windows as shaded sheets, the hovered one named - and a
  click on a sheet flies the camera there, snappy; the release commits the
  location the camera landed on. Go to a window you know the place of,
  instantly.

- MB5 is the quick hop: during the hold it swaps to the last-used window
  at twice the casual camera rate - the speed of the click, still a
  flight - and held in the overworld it tours the clusters instead, the
  bracket keys' own travel at the thumb's speed.

- The step in and the cancel fly at twice the casual rate, so an enter
  snaps instead of arcing - fluid, but not a parade.

- The thread glows white: the constellation is a white thread over a soft
  blurred halo of the same curve, instead of the activity colour.

- The minimap lives: it redraws as the windows move, the frames travel and
  the camera pans or zooms - its bindings had missed their dependencies,
  so the map was a still with an empty rectangle.

- The minimap is a sheet of glass: bigger (a sixth of the screen), the
  view behind it shows through blurred and a touch magnified - a lens -
  the frames are tinted swatches with hairlines, the windows white specks,
  the camera a bright rectangle, and the whole sheet springs in with the
  zoom and grows under the pointer.

- The map is one living picture with two homes: the modifier's hold and
  the overworld share the same map, and it morphs between them - the
  full-screen sheet of the hold springs down into the corner lens as the
  overworld opens, and back, the glass fading in on the way.

- The minimap: a small map of the whole plane in the overworld's corner -
  the frames as swatches, the windows as specks, the camera as the white
  rectangle - and a click on it flies the camera there. It is the plane's
  navigation seen from above, the same picture the bracket keys tour.

- A cluster drags whole: a hand on its badge moves every window in it
  across the plane together, their geometry kept.

- A fullscreen - a screen-sized window - flies margin-free: the activation
  fly used to align the window's edge at the margin, which pushed a
  fullscreen 24 px off-centre; a window that is the screen now lands
  exactly on it. The same fix covers the task bar's click on a fullscreen
  app.

- The hover settles quicker for a plain rest (200 ms, and the 600 ms grace
  now only follows a drag the hand made), so resting the pointer feels
  immediate without ever fighting the hand.

- The keyhole grows the toolbar: at full reveal the modifier's hold shows
  the overworld's controls too.

- The viewport survives the session: the commit writes `ViewX`/`ViewY`,
  and the canvas comes back where the eye left it.

- The placement logic joined the unit tests (`fitRange`, `smartPan`), and
  the harness's state dump names the clusters' members.

- The keyhole and the overworld are one space. Holding MB4 opens the canvas
  quietly - the desktop looks like itself, as it must - and the canvas's
  skin (the frames' tint and outlines, the tags, the threads, the hover
  glow) fades in as the camera departs from the location, so by the time
  you are zoomed out the keyhole and the overworld are the same picture.
  One space, one skin, one physics.

- A double-click always places its window. The first click of a
  double-click used to pan the camera at once (the click-fit), moving the
  window under the pointer mid-tap, which reset the double-click's
  detection - a fullscreen game double-clicked during the modifier's hold
  ended up at the wrong coordinates. The click-fit now waits out the
  double-click interval, and the double-click's placement anchors on the
  camera's destination, never a mid-flight view.

- The fly covers every window the user can click: a utility window (a
  Steam helper, a chat) flies like any other, instead of falling back to
  KWin's own keep-visible rule, which moved the window alone.

- The modifier's hold is tunable: `HoldDelay` is how long MB4 must stay
  down before it opens the canvas (300 ms by default; raise it and a fast
  game click - cycling grenades on the same button - always stays the
  game's). Quicker presses have always replayed as the window's own
  clicks, and rapid ones now do too, over a fullscreen game as anywhere.

- The pure logic - the clustering, the dynamic gap, the float's physics -
  lives in `effect/contents/ui/logic.js`, unit-tested by
  `tests/unit/logic.test.js` (`make unit`, 26 assertions in milliseconds);
  the nest scenarios then verify the wiring.

- The float obeys physics and stays at rest. A floated window's coordinates
  on the plane never change - only the hand moves them, in the canvas and
  at 1:1 alike - and while the window sits fully inside the screen its
  picture is the window, exactly, under any camera or zoom. Only when the
  camera pushes it partly off the screen does the picture float at the
  edge, and pushed there fast it bounces off the edge - the carried
  velocity reflects, damped, then a critically damped spring settles it
  back against the edge - scaling with the zoom, the zoom's own motion
  left out of the bounce. Move the camera back and the picture is the
  window again, at the same coordinates.

- Releasing the canvas modifier after a zoom-out lands where the eye was
  looking: the release springs back to 1:1 keeping the screen's centre,
  instead of committing the zoom anchor's drift to arbitrary coordinates.

- Clusters: windows that sit near each other on the plane are one cluster,
  formed automatically as they are dragged together and parted as they are
  dragged apart. How near counts is dynamic: by default the gap is half the
  pair's own scale - the average of the two windows' smaller sides - so a
  cluster reads the same on a laptop and an ultrawide; `ClusterGap` sets a
  fixed gap in pixels instead. Membership has hysteresis (a pair stays until
  half again as far), and across that band the thread visibly dissolves
  rather than snapping off. The thread is a smooth curve through the
  windows in a stable order - it never re-routes while the hand only moves
  windows - its dashes march so it reads as flowing, it rides every camera
  move with the windows, and the bracket keys fly the camera between
  clusters in reading order, the toast naming the stop. Everything is
  derived: nothing is stored, so a cluster follows its windows.

- The pin is a float. A floating window keeps its coordinates on the plane -
  pinning never moves it - and only its picture is special: whenever the
  camera would push it partly off the screen, the picture floats at the
  screen's edge, bouncing off the edge with real physics when pushed there
  fast, and the window's position follows the picture, so it is always on
  screen in the canvas and at 1:1 alike; move the camera back and the
  window is exactly its coordinates again. The flag is KWin's own "on all
  desktops" - repurposed, so the title-bar menu and the canvas agree on
  what floats, and a floating window follows you across virtual desktops
  too. The menu says Float / Unfloat.

- A click flies even when the window is already active: the plugin publishes
  the window under a completed click, and the canvas flies to it on the
  release whether or not an activation fired - a click on an off-screen
  window always brings it wholly into view, and the fly waits one event-loop
  turn so the release reaches the window first, never grabbing the click
  that caused it.

- The hover glow works everywhere: the glow, the shadow and the lift follow
  the effect's own pointer poll, which sees the hover over a window's client
  area where the pass-through plugin owns the pointer - hovering a window's
  content now reads the same as hovering its title bar.

- The right-click menu is legible: the Plasma menu background assumes the
  desktop blur behind it, and over the canvas there is none, so the canvas
  draws its menus opaque.

- A malformed harness command can no longer write NaN into a window's
  position: the geometry-writing debug commands check their numbers.

- The nest pins the fixture apps' look - Breeze Dark, the dark icon theme,
  the Breeze widget style and decoration - and resets the apps' own configs
  before each run, so a golden screenshot means the same pixels every day
  instead of following the host's theme and the apps' leftover window state.

- The modifier's release lands again: releasing after a zoom-out could leave
  the canvas stuck open because the spring back was asked for after the
  camera timer had already been told to stop. The blur renders at half
  resolution for a quarter of the GPU cost, and the plugin reads the hold
  mask from the config itself, so a missed publish at login cannot leave
  MB4 dead.

- The plane's desks: the digit keys jump to saved views and Ctrl+digit saves
  the current one - named camera positions, the feature virtual desktops had
  that the plane lacked. A glass toast names what just happened.

- The focus fly is minimal and never grabs: an activated window slides the
  least that brings it wholly on screen (its edge ends at the margin, so the
  rest of the desk stays in view), and the fly waits until the hand lets go
  of the pointer - the canvas never grabs the gesture that caused it. A
  double-click during the modifier's hold now animates like any step in.

- The edge pan is radial: past the resting zone the pan follows the pointer's
  direction from the screen centre and speeds up toward the edge, so corners
  pan diagonally and the very edge flies.

- The glass: hovered and lifted windows wear a soft shadow and the hovered
  one a glow in the activity's colour, and the toolbar reads as glass.

- The nest harness no longer flakes: the compositor's log is line-buffered
  (the intermittent empty state reads), a nest whose effect never answers is
  restarted up to three times, and the plugin retries its D-Bus registration
  while the session bus is still starting. fakeinput's digit keys now send
  the digit keys, not their code values.

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
