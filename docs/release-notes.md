Unreleased:

- Floated windows behave when the camera has left them behind. Taking one by
  the hand no longer throws its picture away to its coordinates (and turns
  the press into a pan); stepping into one (Enter, a double-click, the
  switcher) enters where you are instead of flying to where it is parked, and
  it lands on screen, also from a zoomed-out view; a marquee takes it by its
  picture; a window that grows at the edge glides in instead of jumping; and
  on two outputs it stays on the output it is on instead of being pulled to
  the pointer's.
- `PinnedWindows` is no longer read (a float is KWin's on-all-desktops flag);
  the key stays declared so an old config loads.

- The window an auto fly lands on is raised. With focus following the mouse,
  raise on hover and click-raise off, KWin raises a window only after the
  pointer has rested on it, and the pointer never moves when a window slides
  under it, so the flown-to window could stay under its neighbours. The fly
  now raises it.
- Flies are snappier and more elegant: they leap off at once and land with a
  hair of carry (instead of starting slowly), and a short hop is quicker than a
  long flight.

- The idle bob is gone. Zoomed out, every window used to drift a couple of
  pixels on its own phase, which recomputed every window and rebuilt the
  cluster threads 60 times a second while nothing happened: about a fifth of a
  CPU core at rest (21%, measured in the nest). Without it, and with the
  frame tick skipping its window walks when nothing floats or glides, an open
  canvas idles at 0.8%. The motion that stays is the motion your hand causes.

- A captioned tutorial GIF leads the README: one activity, eight steps, from
  the desktop to the hold's map and back. `make tutorial` regenerates it in a
  hidden nest. The README opens with what the canvas is, a feature list and a
  three-line quick start; issue templates and a security note are new.

- An open canvas sitting still costs almost nothing. The floating windows'
  clock advanced every frame even with nothing floating, so every window's
  position was recomputed 60 times a second at rest; measured in the nest,
  an idle open canvas went from 2.6% of a CPU core to under 0.1%.

- Snapping is a magnet. When a dragged window catches an edge, it no longer
  jumps the last few pixels: the picture springs onto the edge with a small
  overshoot. The window's real position is exact either way. Part of
  WindowPhysics.

- Windows can be thrown. Let go of a window in the canvas while still moving
  it fast and it keeps going on the hand's momentum, easing to rest a short
  way on (at most 360 screen px). A window set down after a pause stays exactly
  where you put it. Part of WindowPhysics; off with it.

- Float and "pin on all desktops" are one flag. KWin holds it, so the canvas,
  the title-bar pill, the panel applet, a window rule and KDE's own window menu
  always agree: a rule that puts a window on all desktops floats it on the
  canvas, and clearing it from anywhere unfloats it. Keep above and keep below
  stay separate flags with their own buttons; the float never touches them.

- The end of a fly no longer flashes a stale frame. The canvas closed in the
  same moment the camera, the targets and the real windows jumped to the
  destination, and the compositor could draw the scene's frame from before
  that - the slide's last position with black where its frame had left. The
  scene now stays one more paint (32 ms) at the destination before it goes.

- Reaching for a dock or panel no longer pans the canvas. A pause over a
  window on the way down to the panel counted as a hover and the camera
  fetched that window into view; within a hand's reach of a panel (120 px)
  the hover's fetch now stands back. Everywhere else it behaves as before.

- A second corner push, with the camera left where the first push put it,
  now goes back to where you began. It used to enter "the location under the
  screen centre", which at a zoom-to-fit view is the middle of the plane, so
  entry and exit landed at places nobody asked for. After you navigate, the
  second push still enters where you are looking.

- A tiled or maximized window is part of a room: take one by the hand in the
  canvas and every tiled or maximized window of its cluster comes with it, so
  a KWin tile layout or a KZones layout moves as one. A free window still
  moves alone.

- Un-maximizing or un-tiling a window after the view has slid puts it back
  where the plane has it. KWin keeps a window's restore spot in screen
  coordinates, and the canvas moves the real windows when it slides, so the
  window used to come back as far from its neighbours as the view had moved.
  Works for KWin tiles and maximize; KZones is untested.

- Bookmarks. In the open canvas Ctrl+1..9 keeps the view you are looking at
  (or flying to) in that slot, and Alt+1..9 flies back to it on the camera's
  own spring - the place and how far out. The slots are kept across restarts.
  An empty slot says so and moves nothing. The help card lists the keys.

- The first frame of a fly no longer flashes black over a video wallpaper: the
  scene starts by showing the desktop's own window and only hands over to
  Plasma's wallpaper item once it knows the wallpaper is a picture.

- A fly no longer shows black behind the sliding view: the wallpaper is drawn
  under the plane whenever the canvas is up, not only below 1:1. Late in a
  slide up to a third of the screen was black, where the monitor frame had
  moved away, until the landing snapped back to the desktop.

- The grasp's sphere map draws again: the chip in the bottom-right corner that
  shows where the sweep will land had been built inside the corner lens,
  which hides itself the moment a grasp begins, so it never appeared.

- A commit asked for twice no longer puts the layout on the undo stack twice:
  the second ask, after the canvas has closed, does nothing.

- A window you dragged glides again when arrange, tidy or undo moves it: the
  drag's bookkeeping was never cleared, so the effect left that window to a
  hand that had let go.

- A click on a window no longer pans the camera after the canvas has closed:
  committing, cancelling or ending a slide inside the double-click wait drops
  the pending pan.

- The smart landing counts the neighbours it can bring into view on a screen
  that is not at the desk's origin, as it does on the first screen.

- The ground wallpaper follows the camera again: the check that it is the
  active wallpaper always read empty, so since the wallpaper-write change
  nothing reached it - not the camera, not the grid knobs.

- The Alt+Tab-style switcher keeps waiting while its modifier is held: the
  re-arm of its settle beat threw an error on every poll, so the switcher
  could enter a window while the chord was still down.

- The rest cue along a window's edge fills again after the first time it is
  cancelled, and Space no longer stays "held" across a close and reopen,
  which left the canvas unresponsive until Space was pressed once more.

- The cluster chip and the cluster switcher centre the cluster on the
  screen under the pointer, not only on a screen at the desk's origin.

- The decor applet's tooltips name their own button, its lit states clear
  when no window has focus, and it falls back to KDE's stock titlebar
  button layout when none is configured.

- The pass-through plugin no longer lets a window caption containing a bar
  scramble the applet's state, writes the shader's state file atomically,
  and reads the GPU load through one NVML session instead of opening one
  per poll.

- The 1:1 hold shows only the desktop: while a grasp (or a quiet slide)
  is in hand the canvas draws none of itself - the lit threads fade out
  at 1:1 and the ground's grid no longer draws over the wallpaper.

- The canvas modifier (hold MB4) opens the canvas wherever the pointer is
  now - over a window as well as the bare desktop. A quick press still goes
  to the window as its own click (a game's back button keeps working), and
  inside the open canvas the hold stays navigation-only.

- The canvas's automatic camera moves wait for the hand now: a rest on a
  half-hidden window fetches it after half of the pass-through's own pause
  (**HoverDelay**, 900 ms by default), so the move lands before the pointer
  changes hands, and it glides gently rather than snatching; the edge pan's
  ramp is even from the moment it starts - no late surge toward the edge.

- A drag moves the plane exactly with the hand, at every zoom - no
  acceleration, no drift from the pointer.

- The wheel behaves everywhere on the canvas now: a wheel with a canvas
  button held zooms the canvas instead of nothing, and the zoom door no
  longer eats a wheel over an already-open canvas.

- The settings gained **ShowLabels**: the ground's coordinate labels can
  be turned off, and the same choice reaches the ground wallpaper.

- A tiled ground whose image cannot be loaded now falls back to the grid
  instead of leaving the plane blank.

- The camera and the moves feel the work they do. A far flight runs a
  stiffer spring and settles as promptly as a nudge, so big jumps never
  feel like waiting; a thrown window glides longer and lands with a
  deeper bounce while a short move settles quietly; and the arrange,
  tidy and send-to land their windows in a wave instead of a lockstep.

- The cluster web stays in the overworld. The threads of the cluster
  under the pointer no longer light at 1:1 - the web fades with the
  zoom like the rest of the overworld's chrome, so a normal pan over
  the desktop is the desktop alone.

- The plane hangs in the valley's sky. Far back above the ridges, the
  whole canvas is compressed into a band: the windows are its outlined
  sheets, the rooms are the glow-gatherings among them, and every one
  of them sits at its true place - the geography is the canvas's own,
  drifting with the camera.

- The canvas floor is a mountain valley at dusk. The scenery stands on
  its own: the ridges fold into the haze, the sun goes down behind
  them, the valley floor breathes its mist, and the camera's view
  drifts the ridges so the desktop carries the memory of where the
  plane has been. The canvas is the weather - the rooms are the
  villages, warm clusters of light on the slopes, each breathing on its
  own beat; the windows are the lanterns left along it; and the pointer
  is a torch in the dusk. The state's
  coordinates are scaled from the logical plane to the physical screen
  and flipped to the shader's space, so every light lands where its
  window is.

- The canvas floor is an open ocean. The whole scene is alive, and
  every part of it is the canvas: the clusters are the islands - each
  room a sand-ringed landmass with breaking foam and a lighthouse whose
  beam sweeps on the room's own beat - the windows are the boats with
  their lanterns spilling light down the water, and the pointer is the
  one thing that falls in, spreading its ripple and brightening the glitter. The
  sun sits high, its path of light rides the crests, and the islands
  break the swell and shadow the water away from it.

- The night sea's rooms always show. The saved view can sit far from
  the clusters - the plane's truth - and the shoals used to sit off
  the screen with it, leaving the desktop empty.
  Now an off-screen shoal pulls itself to the nearest edge, so the
  desktop always shows where the rooms are.

- The canvas floor is a night sea, and everything in it glows with one
  light: the bioluminescence. The water is a near-black blue-green, and
  the whole image answers one question - what glows in the dark. The
  rooms are the shoals: where a cluster sits, the plankton have
  gathered in a wide soft bloom that breathes on the room's own beat.
  The windows are the lanterns of the boats, each spilling its light
  down the water. The pointer is the thing that falls in: its press sends the ripple and lights the
  plankton around it. And everywhere, a few scattered sparks drift and
  twinkle. The state's coordinates are flipped to the shader's space,
  so every glow lands where its window really is.

- The canvas floor is a place of light. The starter's grid
  read as graph paper, so it is gone: the floor is a deep flowing
  field - the domain-warped fbm breathing in the canvas's own blues -
  and the canvas's state is the light in it: the rooms glow where the
  clusters sit, each on its own slow beat, the real windows cast their
  faint light where they stand, and the pointer's light follows the
  hand, aligned to the screen it is on.

- The shader contract is compiled, not trusted. make lint-shader
  concatenates the shader wallpaper engine's header with every
  shaders/*.frag and compiles the result with glslangValidator, so a
  uniform declared twice (the fork's header and the shader's own) or any
  GLSL break fails the lint - and a CI job - instead of a user's
  desktop. The fork's rules (the header never declares the canvas
  uniforms, the engine only uploads them, and System Settings must be
  relaunched after an engine reinstall) are written down in
  docs/shader-integration.md.

- The canvas feeds the shader wallpaper. Every commit writes the plane's
  remembered state - the saved view, the ground's own knobs (the grid
  spacing, the octaves, the line and background colours), the clusters
  - to kwin-canvas-state.txt, with the clusters screen-projected, as plain
  lines a shader
  wallpaper's engine can hand to a fragment shader as uniforms. The
  starter shader ships at shaders/canvas-floor.frag: the astronaut
  scene - the deep dusk, the great planet overhead, the calm dark ocean -
  where the saved view drifts the stars and the water and each cluster is
  a faint warm light low in the sky. The contract between the file and the shader is documented in
  docs/shader-integration.md; the engine fork (reading the file into the
  uniforms) is the one piece that lives outside this tree.

- Every move plays. The tidy, the arrange, the send-to and the undo
  glide the windows to their new spots instead of teleporting them, and
  the commit hands the landed layout to the desktop - so a layout change
  reads as the windows walking themselves, and Ctrl+Z plays the move in
  reverse. The MovesGlide knob turns the glide off for the
  physics-averse, and the state line carries the live glide count as
  moves=.

- The pill wears every button the system gives it. The decoration's
  pill and the panel applet now draw the whole native titlebar
  configuration: the close, the minimize, the maximize, the float, the
  window menu, the keep-above and the keep-below (each lit by the
  window's real state), the help, and a configured spacer as a gap.
  The panel applet also draws the exclude-from-capture glyph and acts
  through the plugin's new keep-above, keep-below and capture
  actions. One honest gap stays: the decoration cannot draw the
  capture glyph because this KWin's decoration bridge predates that
  button and drops it, and the panel cannot act on the menu or the
  help because the window API has no such call - the decoration's own
  pill does both natively.

- The float is the system's own pin. The canvas's float was living on
  KWin's "keep above" flag; it now lives on "on all desktops" - the
  pin's true home - and the pill and the panel applet wear it as the
  up-arrow glyph, drawn only when the native titlebar buttons ask for
  it and lit when the window floats. The title-bar menu's pin entry,
  the canvas's pin and the glyphs now agree on one flag.

- The panel wears the pill. A new applet, Canvas Window Decor
  (org.kde.kwin.canvas.decor), sits in the panel and shows the focused
  window's caption and the pill's own glyphs - close, minimize,
  maximize, float - in the same native button order, with the same
  hover and press pops and the same state accents. The glyphs act
  through the pass-through plugin's new windowAction channel, so they
  work with the canvas closed too - including on maximized windows,
  where the decoration's pill stays tucked away. The plugin's state
  names the focused window (its win= line), so the panel always
  follows the window the user is on.

- The pill wears the native buttons, and sits on the left. System
  Settings' titlebar-buttons configuration now decides which glyphs the
  pill shows and in what order - the left set first, then the right -
  so dragging the buttons between the sides reshapes the pill without a
  re-login; the pill itself moved from the top edge's centre to its
  left end. The close, minimize, maximize and float buttons have a
  glyph; the rest are left out.

- The pill tucks away for maximized windows, and a maximized window is
  full-bleed: no band, no reserved strip - the client runs to the
  screen's top edge, so nothing transparent shows above it. The normal
  window keeps its invisible band (the drag handle and the pill's
  hover surface).

- The effect's pill is gone; the decoration's pill is the chrome
  again. The effect-side window decor - the pointer-following pill
  riding any edge through the quiet seam - is removed, and the window
  chrome is the decoration's own pill: the focused window's top edge,
  the close, minimize, maximize and float glyphs, the state accents,
  the native route. One system, no double.

- The pill travels its edge, never covers a window, and the grab lets
  go. The one pill now rides its edge to stay nearest the pointer, so
  it is always where the hand is, and it glides there instead of
  jumping. It never paints over another window: a stretch of the edge
  that another window covers stays bare, and the pill slides past it.
  Dragging a window by the grip dots hides the pill while the window
  rides the hand, and the release ends the drag cleanly - the pill
  stands down on the grabbed window's own edge until the pointer
  leaves it, while every other edge keeps working. And the seam no
  longer churns: walking the pointer across windows opens the canvas
  once and closes it a beat after the pill is gone, instead of
  flickering in and out per window.

- The canvas has its own window chrome: one pill, wherever the pointer
  rides. Approach any edge of any window - top, bottom, left or right,
  over the closed desktop too - and the pill appears there, one glass
  capsule hugging that edge: an empty stretch with three grip dots
  that drags the window with the hand, then close, minimize, maximize
  and float, each a real window action. The pill stands down during
  the hold, so the grasp's drags and pans always get their releases,
  and it leaves the desktop clean when the pointer is elsewhere. The
  decoration's per-window pill stays for the edge cases the effect
  cannot see; this one is the canvas's.

- The window wears nothing but the pill. The Canvas decoration is now
  a window with no frame at all - no border, no shadow - and one glass
  pill (close, minimize, maximize, float) sitting on the top edge,
  always visible and always the same size. Each glyph answers the
  pointer: it swells on the hover and sinks on the press, and its
  glass fills in as the pointer lands. The whole top edge remains the invisible drag handle, and the
  resize edges stay invisible too, so a window is exactly its content.
  The pill wears the canvas's glass with a drawn refraction: the QML
  decoration API has no real backdrop blur, so the lens is painted.
  The glyphs use the standard decoration requests - the compositor's
  own way.

- The trail is a ribbon, not a scribble. The camera's path used to
  keep every wiggle the hand made; it now keeps only the real turns -
  the jitter on a straight run collapses away - and the samples land a
  little further apart, so the day's path reads as a clean line through
  the places you actually went.

- The scene tree hot-reloads. The canvas's look - everything the eye
  sees - now lives in its own file, ui.qml, loaded through a
  version-stamped URL: `make hot` bumps the revision and the running
  session recompiles the scene on the spot, no re-login, no cache
  dance. The effect's logic still lives in main.qml and still needs a
  compositor restart, but a polish edit - a colour, a fade, a spacing -
  lands in the moment.

- The plane remembers the day. The open canvas draws a faint fading
  trail on the ground where the camera has travelled this session - a
  smooth comet of a line in the threads' own white, bright at the head
  and dissolving behind it, every pan and zoom leaving it behind. The
  oldest part is gone after about ten minutes, and the whole trail
  lives in the zoomed-out world, out of the 1:1 seam, so the normal
  desktop never changes. The DayTrail knob turns it off.

- The hover steps forward into the light. When the pointer settles on a
  window in the overworld, the rest of the plane - the ground, the
  frames, the threads, the windows behind it - dims under a whisper of
  the house dark, and the light comes back when the hand leaves. The
  hovered window alone keeps the full light. The spotlight rides the
  same gates as the glow: only the deliberate rest brings it, never a
  press, never a pass-through handoff, never the quiet seam, never the
  switcher's own light, and never below the ladder's top rung.

- The cluster badges never read a stale list. A delegate that outlived
  the cluster list it was built for by a frame - a fast window churn, a
  game launching - could read past the new list's end and throw; the
  badges and the chips now read a stale index as nothing instead of
  throwing.

- The wheel is the door. With the canvas closed, the wheel over the bare
  ground zooms the world out of the location - the canvas opens at the
  1:1 seam, pixel for pixel, and the wheel keeps zooming into the
  overworld; zooming back in to 1:1 flies the camera home and re-enters
  the location on the arrival. Over a window the wheel stays that
  window's, so games and apps keep their scroll. The WheelDoor knob
  turns it off; it needs the pass-through plugin to see the wheel while
  the canvas is closed.

- The window wears the hand. The pass-through's rest cue no longer cuts
  at the handoff: the line completes, hands the pointer over, and fades
  into the window's own glow. And while the pass-through owns the input,
  the line stays full along that window's top edge - the engaged window
  is visible at a glance, wherever the pointer sits.

- The tour draws its path. A flight leaves a thin fading trace from
  where the camera came - the plane keeps its spatial history until the
  arrival erases it, and a settled canvas never carries it.

- The ladder sheds in the eye's order, not the cost's. The standing
  shadows and the depth go first (the quiet-night rung - the pile
  flattens, the world stays legible), the cluster web and the blur
  next, the live pictures last. The motion is never degraded.

- The windows glide to the spots the plane gives them: the tidy lays the
  desk out with a straight 220 ms glide per window instead of a
  teleport, and a commit never catches a window mid-flight.

- The tour's smart placement pulls the neighbours in. When a hop lands
  on a cluster's window, the camera now keeps the focused window
  completely inside while bringing as many of the windows around it at
  least partially into view - the least displacement that does it,
  scoped to the windows within a screen's reach, so a window across the
  plane never tugs the camera. The sweep is the optimum for the count:
  the visible set only changes at a window's edge, and the candidates
  are exactly the points between the edges.

- Every commit is a checkpoint. Ctrl+Z in the open canvas steps the
  layout back one commit - the windows' spots, the activities they sat
  in, and the real frames alike - and steps back up to twenty times,
  the session's own history. The debug channel's undo verb is the same
  step.

- The clusters are rooms now. The tour - the side button, the brackets -
  is a workspace switch: every hop lands the camera and the focus on the
  next cluster's most-recently-focused window, smart-placed, every time.
  The digits 1-9 return to the spot each room was left at, the rooms
  survive the session, and a room can wear a name (the debug channel's
  clustername, shown on its badge and its chip). The old invisible
  bookmarks are retired - the digits belonged to the rooms all along.

- The flights leave no pop behind. The camera's spring used to push
  itself a few percent of the way in its first frame - a snap the eye
  read as a cut - and the quiet slide used to lurch off the mark. The
  spring now starts from rest with its full acceleration and builds into
  one unbroken glide, and the slide eases in and out of its motion, so a
  step in, a step out and an activation fly are one continuous motion
  from the first frame to the seam.

- The cluster tour lands where the hand left off. MB5 in the grasp, the
  side button in the overworld and the bracket keys now fly to the
  cluster's last-focused window - the one the hand actually used there,
  the way a desktop remembers its own window - instead of its geometric
  centre, and the landing is a pick's placement: the least pan that
  brings the window wholly on screen, padded. A cluster no one has
  focused yet still falls back to its centre, and the toast names the
  window it landed on.

- The grasp's hint names the release. Its last word flips at the exact
  boundary the release uses: zoomed in, it says "release to land"; past
  the widen point it says "release to open the world". The two outcomes
  of the hold - the location it lands on, or the overworld it opens -
  are now written on the plane while the hand is still down, not guessed
  after the release. The debug channel's state line carries the same
  word as `outcome=`.

- The seam's ground is proven. The effect's ground knobs - the grid's
  spacing, its octaves, its colours, its labels - now reach the
  wallpaper plugin too, so the closed desktop and the canvas's ground
  draw the same picture (they always should have; the knobs had only
  ever reached the effect). A new scenario measures the actual seam: the
  ground continues across the frame's edge at 1:1 within the noise of
  the label's antialiasing, and a knob change shows up on both sides.

- Hold the grasp and tap the side button, and the camera hops to the
  next cluster - the plane's desktops - and the release opens the
  location there. Clusters were always the plane's answer to virtual
  desktops; the travel between them is now the grasp's own gesture,
  and the hop is brisker everywhere (the bracket keys' tour rides the
  same quick flight). The old side-button swap between recent windows
  is gone with it: the clusters won the button.

- The switcher's enter cannot be missed. The settle's beat now arms on
  every chord event - the open, each step, each poll of the seat's
  modifier keys - and the poll keeps the beat at bay while the chord is
  held, so whatever link of the release chain survives, the pick settles
  for its moment and the canvas steps in by itself. A dead modifiers
  channel (an older plugin) is treated as the release rather than a
  stuck switcher.

- The cue and the glow take turns. The pass-through's rest cue owns the
  hover delay, and the canvas's own hover glow now waits for the handoff
  instead of lighting up halfway through the cue - the two no longer
  duel, and the glow reads as the engagement that follows the handover.

- The grasp's ring lands on the window, not the screen. The ring that
  marked the screen centre is gone - the release's spot was not what the
  hand needed - and the window under the pointer keeps its landing ring
  through the hold, so the one a click would fly to is marked, and the
  release still lands.

- The handoff is anticipated, and the grasp shows its destinations. While
  the pointer rests out the hover delay over a window, a thin line fills
  along its top edge - the pass-through's handover reads before it happens
  instead of surprising the pointer - and during the hold a soft ring
  marks the window under the pointer as the one a click would fly to.
  The hold's two outcomes are legible before it ends.

- The toolbar says what the canvas is doing. The fidelity ladder's
  current rung now shows as a quiet dot in the toolbar - amber for
  reduced, orange for minimal, red for bare - appearing only when the
  canvas has stepped down, and its hover names the rung. The zoom
  readout and the hand dot were already there; the three together make
  the toolbar the canvas's own status line.

- The ladder asks twice before it moves, and it says so. A launch spike
  can no longer flash the canvas down, a single breath cannot flash it
  back up - both directions wait for two consecutive samples - and a
  step down to the bare rungs announces itself with a toast instead of
  reading as a broken desktop.

- The cluster the eye is on never fully dissolves: its thread keeps a
  floor of strength no matter how scattered the desk. A re-sort of the
  pile no longer replays a window's entrance fade, and the switcher
  asks the scene for its keyboard focus through a proper channel
  instead of an exception.

- The switcher's release no longer waits on a key-up the scene may
  never see. The chord's end is read from the seat itself - the
  pass-through plugin reports the live modifier keys, and the moment
  the chord's modifier clears, the switcher settles on the pick for its
  beat and steps in. A re-tap of the chord mid-hold can never arm the
  release, and the scene's own key-up remains the fast path.

- The switcher wears its pick. While the chord is held, a glass card
  under the toolbar names the chosen window, shows it live, and says
  which cluster it belongs to - riding the same rise the windows ride,
  and gone with the switcher. The chord now opens the switcher from the
  open overworld too, not only from the closed location: wherever the
  chord fires, the plane fits and the card steps with the selection.

- The demo tour matches the canvas again: the refreshed capture walks
  the step-out, the double-click fly, the web, the switcher's snap with
  its pick card, the hold's wheel descent and the landing.

- Alt+Tab is the cluster switcher now. Meta+Tab keeps sweeping the whole
  plane; Alt+Tab steps only among the windows of the cluster the eye is
  on, and opens fitted to that cluster instead of the whole world - the
  quick switch among neighbours at 1:1, where a cluster of one falls
  back to the plane-wide fit. Bind both over KWin's own switcher and
  they are the two scopes of the same gesture.

- The physics live at real time. The camera spring and the float physics
  used to step on a fixed 16 ms timer, so on a fast display every flight
  and bounce rendered on a 62.5 Hz grid regardless of the panel's own
  rate; they now integrate the real time that passed, clamped for the
  spring's stability, on a finer tick - flights and floats glide instead
  of stepping, and a slow frame slows the motion rather than lengthening
  its steps. And a window that enters the open overworld fades and grows
  in gently instead of popping, while the quiet seam and the closed
  desktop stay pixel-exact.

- The switcher opens as a snap, not a wait: the fit to the whole plane
  rides a brisker flight, and the windows rise in z at the same moment
  - the pile's depth comes up on its own quick ramp instead of waiting
  for the zoom-out to reveal it. Each step also pops the pick to the
  top of the pile, so the cycle reads in the shadows and the size, not
  just the outline.

- The switcher reads a held chord as a hold. The chord refired on every
  key repeat of a held Tab, so holding Alt+Tab machine-gunned the cycle;
  a single gate now passes one step per deliberate re-tap and swallows
  the repeats. And a plain tap - a release with nothing picked - lands
  on the next window, the way Alt+Tab behaves everywhere else, instead
  of entering the window you were already on and closing without a
  trace. Release still enters the pick, Tab and Shift+Tab still step it,
  and Esc still steps out.

- The toolbar wears the canvas's own glass. Its colours had followed
  the machine's mutable colour scheme, so the same build rendered two
  different toolbars across sessions; the glass, the borders and the
  hand dot are now fixed house colours.

- The minimap's camera rectangle stays inside the lens. Panned past the
  world's edge it hugs the chip's border instead of sliding off it, and
  a view bigger than the world fills the chip exactly.

- The fidelity ladder reads the memory too. The machine's used share
  joins the CPU and the GPU as a third channel, and whichever channel
  sees the worse pressure sets the step - a browser hoarding gigabytes
  degrades the canvas even while the chips idle. The three Mem
  thresholds are hidden knobs beside their CPU and GPU twins.

- Tidy this activity: the Arrange menu's action packs the activity's
  windows into rows - sorted, laid left to right from the frame's
  top-left with the tidy gap, wrapping like text. TidyGap sets the
  gap. Nothing is written until the commit, like every arrange.

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
