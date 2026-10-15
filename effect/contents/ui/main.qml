/*
    SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
/*
    kwin-canvas: an infinite canvas for KWin, built on the public scripting API.

    At 1:1 there is no effect running. Windows are ordinary KWin windows at
    ordinary positions, some of them off-screen. The screen is a 1:1 viewport
    onto one shared plane.

    Every activity is a viewport onto that same plane: a rigid group of
    monitor frames, one per output in the layout KDE knows, placed somewhere on
    the canvas. Switching activities is switching viewport. Dragging a window
    into another activity's frame moves it to that activity. Virtual desktops
    stay ordinary KWin desktops; the canvas shows the current one.

    Opening the canvas snapshots every window into canvas coordinates and shows
    them as live thumbnails on a ground grid, with the frames drawn over them.
    Pan, zoom, drag windows, drag frames. Apply writes positions back as plain
    window geometry relative to the frame they sit in.

    Coordinate spaces:
      canvas   the plane windows live on; unbounded
      global   KWin's coordinate space across all outputs
      view     (viewX, viewY) is the canvas point the camera puts at global (0,0)
      target   per activity: the canvas point at global (0,0) when that
               activity is shown. Its frames are drawn at target + output.geometry.

      global = (canvas - view) * zoom
      canvas = view + global / zoom
      frame geometry = canvas - target(activity of the window)

    While the canvas is closed, view == target(current activity).
*/
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import "logic.js" as Logic
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kwin as KWin
import org.kde.plasma.components as PC3

KWin.SceneEffect {
    id: effect

    // The hot-reload revision: the ui.qml Loader appends this to its URL,
    // so bumping it (make hot) gives the QML engine a new cache key and the
    // scene tree recompiles without a compositor restart. The logic above
    // this delegate - the properties and functions - is this component and
    // still needs a restart to change.
    property int hotRev: 0

    // ---- camera ------------------------------------------------------------
    property real viewX: 0
    property real viewY: 0
    property real zoom: 1.0
    property real entryViewX: 0
    property real entryViewY: 0

    // ---- targets: activity id -> {x, y} ------------------------------------
    property var targets: ({})
    property var entryTargets: ({})

    // ---- model -------------------------------------------------------------
    // Each entry: { window, activity, x, y, width, height } in canvas units, bottom to top.
    property var entries: []
    property int revision: 0
    property bool helpOpen: false
    // Quiet: open at 1:1 for a slide, with no frames, tags, toolbar or input.
    property bool quiet: false
    // The scene's own fade: a slide opens and closes the canvas at 1:1, the
    // grasp holds there, and the overworld opens and closes at 1:1, where
    // the canvas must be the desktop. The scene fades in over the desktop
    // when it opens and out over it when it lands, crossfading the two
    // instead of letting the cut flash every inactive title bar at once.
    property real sceneFade: 1
    // The one-frame warm-up: the quiet slide opens opaque (a fade-in here
    // would run through black - KWin composites the scene's framebuffer
    // over black, not over the desktop), and the glide waits one
    // event-loop turn so the scene's first paint warms the cold
    // thumbnails under their real selves.
    property bool slideWarm: false
    readonly property bool canvasOpen: visible && !quiet
    // Pass-through: the optional binary plugin is live while the canvas is
    // open. Every key, and every click, drag and wheel over a window, goes
    // to the real window; the ground, the decorations, the frame tags and
    // the toolbar stay the canvas's. Live once the plugin has answered the
    // probe for this opening; the camera is published to it on every change.
    readonly property bool passthrough: configuration.Passthrough !== false && !planeInput
    property bool passthroughLive: false
    // Whose hand is on the pointer right now: the plugin's state() reports a
    // hover or a grab, and the toolbar's dot fills in when either is the
    // window's. Polled while the overworld is open; the dot is the honest
    // answer to "will this click move the canvas or the window?"
    property bool handOnWindow: false
    onHandOnWindowChanged: effect.dbg("hand", "handOnWindow=" + effect.handOnWindow)
    // ---- fidelity under load --------------------------------------------------
    // The machine's busy share drives a ladder: 0 wears everything, 1 sheds
    // the blur and the faint constellation, 2 the whole web, the shadows and
    // the z-depth, 3 the thumbnails themselves - plain rectangles with names,
    // so a pegged system keeps a working canvas and not a pretty one. The
    // plugin's load() supplies the reading every couple of seconds while the
    // overworld is open; the ladder steps down the moment the machine gets
    // busy and back up only after two calm readings, so it never flutters.
    property int ql: 0
    property real cpuBusy: 0
    property real gpuBusy: 0
    property real memBusy: 0
    property int quietSamples: 0
    property int hotSamples: 0
    function qualityCap() {
        switch (String(configuration.QualityMode)) {
            case "Full": return 0;
            case "Reduced": return 1;
            case "Minimal": return 2;
            case "Bare": return 3;
            default: return 3; // Auto
        }
    }
    function qualityApply(cpu, gpu, mem) {
        // A reading outside [0, 100] is not a percentage at all - a stale
        // plugin still answering in kilobytes, or a dead channel - so it is
        // treated as absent rather than letting a huge number force the
        // canvas bare.
        const cc = Number.isFinite(cpu) && cpu >= 0 && cpu <= 100 ? cpu : 0;
        const gg = Number.isFinite(gpu) && gpu >= 0 && gpu <= 100 ? gpu : 0;
        const mm = Number.isFinite(mem) && mem >= 0 && mem <= 100 ? mem : 0;
        cpuBusy = cc;
        gpuBusy = gg;
        memBusy = mm;
        if (String(configuration.QualityMode) !== "Auto") {
            ql = qualityCap();
            quietSamples = 0;
            hotSamples = 0;
            return;
        }
        const cpuReduced = Number(configuration.CpuReduced);
        const cpuMinimal = Number(configuration.CpuMinimal);
        const cpuBare = Number(configuration.CpuBare);
        const cpuQl = Logic.qualityFor(cc, Number.isFinite(cpuReduced) ? cpuReduced : 60, Number.isFinite(cpuMinimal) ? cpuMinimal : 80, Number.isFinite(cpuBare) ? cpuBare : 95);
        const gpuReduced = Number(configuration.GpuReduced);
        const gpuMinimal = Number(configuration.GpuMinimal);
        const gpuBare = Number(configuration.GpuBare);
        const gpuQl = Logic.qualityFor(gg, Number.isFinite(gpuReduced) ? gpuReduced : 60, Number.isFinite(gpuMinimal) ? gpuMinimal : 80, Number.isFinite(gpuBare) ? gpuBare : 95);
        const memReduced = Number(configuration.MemReduced);
        const memMinimal = Number(configuration.MemMinimal);
        const memBare = Number(configuration.MemBare);
        const memQl = Logic.qualityFor(mm, Number.isFinite(memReduced) ? memReduced : 80, Number.isFinite(memMinimal) ? memMinimal : 90, Number.isFinite(memBare) ? memBare : 97);
        // The three channels race each other: whichever sees the worse
        // pressure sets the step, and a calm machine must clear ALL of them
        // before the ladder climbs back up.
        const target = Math.max(cpuQl, gpuQl, memQl);
        // Both directions wait for two consecutive samples: a launch spike
        // cannot flash the canvas down, and a single breath cannot flash it
        // up. A step down to the bare rungs announces itself, so it never
        // reads as a broken desktop.
        if (target > ql) {
            hotSamples++;
            quietSamples = 0;
            if (hotSamples >= 2) {
                if (target >= 2) toast("The canvas steps down to keep the machine yours");
                ql = target;
                hotSamples = 0;
            }
        } else if (target < ql) {
            quietSamples++;
            hotSamples = 0;
            if (quietSamples >= 2) { ql = target; quietSamples = 0; if (ql === 0) toast("The canvas is back to full"); }
        } else {
            quietSamples = 0;
            hotSamples = 0;
        }
    }
    // Plane input: under the preload shim (dev/spike/preload) KWin's pointer
    // chain works in plane coordinates, plane = (screen - o) / s, where a
    // plane point is a frame position on the current activity: s = zoom and
    // o = (target(current) - view) * zoom. The shim sets planeInput when it
    // attaches, reads the transform below while planeLive, and asks
    // planeTakes() where the canvas keeps the pointer. Everywhere else KWin
    // routes the pointer to the window there, and keys go to the focused
    // window. The pass-through plugin stands down.
    property bool planeInput: false
    // The shim takes a scale in (0.01, 100) only; outside it the transform is off.
    readonly property bool planeLive: planeInput && canvasOpen && zoom > 0.01 && zoom < 100
    readonly property real planeScale: zoom
    readonly property real planeOffsetX: { revision; return (peekTarget(currentActivity).x - viewX) * zoom; }
    readonly property real planeOffsetY: { revision; return (peekTarget(currentActivity).y - viewY) * zoom; }
    // The buttons the canvas owns while they are down: the PanHold buttons and
    // the middle button. The shim reads this and the plugin is told over D-Bus
    // (setNavButtons); both then hand the pointer to the canvas for those
    // buttons wherever it is, a window's client area included. That is what
    // makes a held button a portal into the canvas: the window under it never
    // sees the press, so a drag moves the window on the plane, a drag on the
    // ground pans, and the screen edge keeps panning with the window in hand
    // (edgePanStep). It is the same mask the pan handlers already take, so
    // there is one answer to "which buttons navigate the canvas".
    readonly property int planeNavButtons: (bindings.panHold || 0) | Qt.MiddleButton | (bindings.swap || 0)
    // The swap buttons: while the canvas modifier is held, a press tours
    // the clusters - the camera hops to the next one, the plane's own
    // desktops.
    readonly property int swapButtons: bindings.swap || 0
    // The buttons a drag on a control takes: the left button, and the PanHold
    // buttons. That is the set the pan handler acts on over the ground, so a
    // held portal button does what the left button would have done wherever
    // there is a control to take it - a window moves, a frame tag or edge moves
    // its frames, a resize grip resizes - and only the ground beside them pans.
    // The middle button is not among them: it pans from anywhere, controls
    // included, and that is a promise of its own.
    readonly property int gripButtons: Qt.LeftButton | (bindings.panHold || 0)
    // The buttons that make a held pointer a portal, without the left button
    // they share a grip drag with: a drag of one of these on a control is a
    // drag the canvas is being navigated by (see the view's navHeld), so the
    // edge pan runs with the window in hand and the screen edges stay off.
    readonly property int portalButtons: bindings.panHold || 0
    // The canvas's own open menus: while one is up the canvas takes the
    // whole pointer.
    property int canvasMenus: 0
    // Views with a pan button held down. There is one pointer, so at most one
    // screen's view holds it; counting them keeps two screens honest, and lets
    // the effect ask whether the canvas is being navigated (the screen edge
    // handlers do: pushing into a border to pan must not toggle the canvas).
    property int navHolds: 0
    readonly property bool navHeld: navHolds > 0
    // The canvas modifier (CanvasHold): a button that, held with the canvas
    // closed, makes the location itself the canvas. The pass-through plugin
    // (or the plane-input shim) sets this property on its press and release;
    // the press opens the canvas quietly at 1:1 - pixel-identical to the
    // desktop, no chrome - with input live, so the overworld's gestures work
    // as if it were open (the middle button pans, a drag on a window moves
    // it, the wheel zooms, an edge keeps panning), and the release commits
    // the moves and closes again. Held while the overworld is open it simply
    // counts as navigation, so the edge pan works under it there too.
    property bool canvasHold: false
    property bool grasp: false
    property var graspStartActive: null
    // The hold came down while the overworld was already open: it is the
    // grasp from the overworld's side, so the map comes back for it and the
    // release returns to the overworld, not to the location.
    property bool graspOverworld: false
    // The grasp's landing target: during the hold, the window under the
    // pointer is the one a click would fly to, so the scene rings it and
    // the state line names it - the gesture shows its destination before
    // the click lands.
    property var graspTarget: null
    // When each window last had the focus, keyed by internalId: the cluster
    // tour hops between the windows the hand actually used, like switching
    // desktops that remember their own window.
    property var focusAt: ({})
    function graspPick() {
        if (!grasp) return;
        const p = cursorScreen();
        const c = globalToCanvas(p.x, p.y);
        let e = null;
        for (let i = entries.length - 1; i >= 0; --i) {
            const en = entries[i];
            if (c.x >= en.x && c.x < en.x + en.width && c.y >= en.y && c.y < en.y + en.height) { e = en; break; }
        }
        if (e !== graspTarget) graspTarget = e;
    }
    Timer {
        interval: 100
        repeat: true
        running: effect.grasp
        onTriggered: effect.graspPick()
    }
    onCanvasHoldChanged: {
        if (canvasHold) {
            // Held while the overworld is open: the hold itself IS the
            // navigation - bring the grasp back, map and all.
            if (!visible) graspStart();
            else if (!grasp) {
                grasp = true;
                graspTarget = null;
                chipCount = clusters.length;
                graspOverworld = true;
                graspJumped = false;
                dbg("hold", "grasp from the open overworld");
            }
        } else if (grasp) {
            dbg("hold", "released");
            graspEnd();
        }
    }
    // The verbose trace: every decision the canvas takes, at the moment it
    // takes it, with the state it leaves behind. Toggled by the Verbose
    // knob or the debug channel's "verbose" command; the lines land in
    // KWin's log as "[canvas] tag: message zoom=... view=...".
    property bool verb: configuration.Verbose
    function dbg(tag, msg) {
        if (!verb) return;
        console.log("[canvas] " + tag + ": " + msg
            + " zoom=" + zoom.toFixed(4)
            + " view=(" + Math.round(viewX) + "," + Math.round(viewY) + ")"
            + " quiet=" + quiet + " grasp=" + grasp
            + " clusters=" + clusters.length);
    }
    // The map's home, mirrored out of the map item: the effect's own
    // functions read it, so logState can say whether the lens is up without
    // reaching into the scene tree.
    property bool mapMinimap: false
    // The world's chips are driven from the effect's own state rather than
    // a binding on the scene tree: during the quiet grasp the Repeater's
    // bindings freeze, so the grasp sets this and the model reads it.
    property int chipCount: 0
    function graspStart() {
        if (visible) return;
        dbg("graspStart", "hold from the location at 1:1");
        grasp = true;
        graspTarget = null;
        chipCount = clusters.length;
        graspStartActive = KWin.Workspace.activeWindow;
        open(true);
        // The camera never slides during a grasp, so endSlide()'s measured
        // distance is zero: what gets committed is the windows the hand
        // moved, and the camera returns to the location's viewport.
        slideToX = viewX;
        slideToY = viewY;
        // A fullscreen app at 1:1 is exactly the desktop: step out a little
        // so the grasp is visible, then the release springs back to 1:1 at
        // the committed viewport.
        if (fullscreenOpen()) fullscreenZoomTo();
    }
    function graspEnd() {
        if (!quiet || !grasp) { grasp = false; graspOverworld = false; graspTarget = null; chipCount = 0; return; }
        if (sceneGestures > 0) {
            deferredClose = graspEnd;
            deferredAt = Date.now();
            return;
        }
        grasp = false;
        chipCount = 0;
        dbg("graspEnd", "release, quiet at zoom " + zoom.toFixed(3));
        // The active window changed during the hold (a taskbar click, an
        // activation): the location opens where that window is, focused on
        // it, as a pick would place it - the frames, their windows and the
        // wallpaper slide to it and nothing else moves.
        const aw = KWin.Workspace.activeWindow;
        if (aw && !aw.deleted && aw !== graspStartActive) {
            const e = entryFor(aw);
            if (e) {
                const inFrame = activityAt(e);
                placeTarget(e, inFrame !== null ? inFrame : (e.activity || currentActivity));
            }
        } else {
            // No swap: what the hand left on screen is the location. A pan
            // during the hold becomes the new viewport - the release enters
            // the screen at that coordinate instead of snapping back - and a
            // hold that only moved windows keeps the viewport it started on.
            // A zoom has shifted viewX with its anchor, so the destination
            // keeps the screen's centre, the place the eye was looking,
            // instead of committing the anchor's drift.
            const g = actionScreen().geometry;
            const t = targetOf(currentActivity);
            if (zoom < 0.999) {
                t.x = viewX + (g.x + g.width / 2) / zoom - (g.x + g.width / 2);
                t.y = viewY + (g.y + g.height / 2) / zoom - (g.y + g.height / 2);
            } else {
                t.x = viewX;
                t.y = viewY;
            }
        }
        // The zoom decides where the release leaves you. Zoomed out, the
        // camera has stepped out of the location: the release keeps the
        // overworld - the keyhole widens into the whole canvas, the chrome
        // fades in, and the world itself is the map - the windows shrink
        // live into its sheets. Zoomed in, the release commits the
        // location, as it always has - a pan during the hold is the
        // location's new viewport.
        if (zoom < 0.72 && !graspJumped) {
            dbg("graspEnd", "widening into the overworld");
            quiet = false;
            chromeFade = 0;
            welcomeAnim.restart();
            thumbOpacity = 1;
            if (passthrough) probeCall.call();
            return;
        }
        dbg("graspEnd", "committing the location");
        commit(null);
    }

    // MB5 tours the clusters wherever it fires - the grasp's own travel
    // and the overworld's - at the speed of the click. Clusters are the
    // plane's desktops; the side button is the hop between them.
    function swapWindow() {
        if (!grasp && !canvasOpen) return;
        dbg("swap", "touring the clusters");
        clusterTravel(1);
    }
    // Frame positions at open, for cancel to put back what settle() wrote.
    property var openFrames: ({})
    property bool settled: false
    // Selection: window internalId -> true. selectionRev bumps on every change.
    property var selected: ({})
    property int selectionRev: 0

    function isSelected(e) { return e && selected[e.window.internalId] === true; }
    function selectOnly(e) { selected = {}; if (e) selected[e.window.internalId] = true; selectionRev++; }
    function selectAdd(e) { if (e) selected[e.window.internalId] = true; selectionRev++; }
    function selectToggle(e) {
        if (!e) return;
        if (selected[e.window.internalId]) delete selected[e.window.internalId]; else selected[e.window.internalId] = true;
        selectionRev++;
    }
    function clearSelection() { selected = {}; selectionRev++; }
    // Add every window whose canvas rect meets the rectangle.
    function selectInRect(x, y, w, h) {
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (e.x < x + w && e.x + e.width > x && e.y < y + h && e.y + e.height > y) selected[e.window.internalId] = true;
        }
        selectionRev++;
    }
    function activityColor(id) { return palette[activityIndex(id) % palette.length]; }

    // Keyboard navigation over the windows: Tab steps the selection through
    // the entries, wrapping, and brings the chosen window into view;
    // Shift+Tab steps the other way. Overview-like, on a canvas: the camera
    // follows the selection, so the next window is always where the eye goes.
    function cycleSelection(dir) {
        // The cluster switcher steps only among the windows of the cluster
        // the eye is on; the plain Tab cycle and the world switcher walk
        // every entry.
        const pool = (switcherActive && switcherCluster) ? switcherMembers() : entries;
        if (pool.length === 0) return;
        let idx = -1;
        for (let i = 0; i < pool.length; ++i) if (isSelected(pool[i])) { idx = i; break; }
        const n = idx < 0 ? (dir > 0 ? 0 : pool.length - 1) : (idx + dir + pool.length) % pool.length;
        selectOnly(pool[n]);
        dbg("sel", "cycle " + dir + " -> " + pool[n].window.caption);
        bringIntoView(pool[n]);
    }

    // The cluster the switcher scopes to: the active window's, or the
    // focus's, whichever the eye is on. A lone window's cluster (or none)
    // falls back to the whole plane - there is nothing to scope to.
    function switcherMembers() {
        const ci = clusterIndex();
        const c = ci >= 0 ? clusters[ci] : null;
        if (!c || !c.ids || c.ids.length < 2) return entries;
        const pool = [];
        for (let i = 0; i < c.ids.length; ++i) {
            const e = entries.find(en => en.window.internalId === c.ids[i]);
            if (e) pool.push(e);
        }
        return pool.length > 1 ? pool : entries;
    }

    // The switcher's pick: the selected window while the cycle runs, the
    // focused one before the first step - the card shows who lands.
    function switcherPick() {
        if (!switcherActive) return null;
        for (let i = 0; i < entries.length; ++i) if (isSelected(entries[i])) return entries[i];
        return focusEntry ? focusEntry : (entries.length ? entries[0] : null);
    }

    // Pan the camera the least that puts the window wholly on the screen the
    // pointer is on, and - among the pans that keep it so - the one that
    // leaves the most of the other windows in view. The natural stopping
    // points are the alignments that bring the window's edges, or a
    // neighbour's, onto the screen's; the least movement wins the ties.
    // The pointer is on, or within a hand's reach of, a dock or panel: the
    // approach zone. The margin is the distance a pointer covers in a
    // moment's reach, so a pause just short of the panel counts.
    function nearDock(px, py) {
        const margin = 120;
        const stack = KWin.Workspace.stackingOrder;
        for (let i = 0; i < stack.length; ++i) {
            const w = stack[i];
            if (!w || w.deleted || !w.dock) continue;
            const g = w.frameGeometry;
            if (px >= g.x - margin && px < g.x + g.width + margin && py >= g.y - margin && py < g.y + g.height + margin) return true;
        }
        return false;
    }
    function bringIntoView(e) {
        const others = [];
        for (let i = 0; i < entries.length; ++i) {
            if (entries[i] === e) continue;
            others.push({ x: entries[i].x, y: entries[i].y, width: entries[i].width, height: entries[i].height });
        }
        const d = smartPan({ x: e.x, y: e.y, width: e.width, height: e.height }, others, 24);
        // The hover's fetch is a suggestion, not a flight: it glides at a
        // lower rate than a choose-move, so a rest over a half-hidden window
        // slides it in instead of snatching it.
        if (d.dx !== 0 || d.dy !== 0) { dbg("camGo", "bringIntoView " + (e.window ? e.window.caption : "?") + " d=(" + Math.round(d.dx) + "," + Math.round(d.dy) + ")"); camGo(zoom, viewX + d.dx, viewY + d.dy, undefined, undefined, 0.55); }
    }

    // The best camera pan for a canvas rect: the least movement that keeps
    // it wholly inside the screen the pointer is on, with a margin. The
    // minimal pan is also the least disruption to the rest of the desk - the
    // other windows stay in view precisely because nothing moved more than
    // it had to. A rect larger than the screen is left- and top-aligned.
    function smartPan(rect, others, pad) {
        return Logic.smartPanNeighbourhood(rect, others, actionScreen().geometry, viewX, viewY, zoom, pad);
    }

    // Enter with a window selected steps into that window, as the double-
    // click does; with a window hovered it steps into that one; with neither
    // it enters the location under the screen centre, as the toolbar's Enter
    // does. The key is the overview pattern - Tab or a hover to the window,
    // Enter to go to it - on the canvas.
    function applyKey() {
        for (let i = 0; i < entries.length; ++i) {
            if (isSelected(entries[i])) { focusWindow(entries[i]); return; }
        }
        if (focusEntry && entries.indexOf(focusEntry) !== -1) { focusWindow(focusEntry); return; }
        enterHere();
    }

    // The debug channel's own replay sequence: the last DebugSeq seen, so
    // each reconfigure replays its command exactly once.
    property int lastDebugSeq: 0
    // There used to be an idle bob here: every window drifting 2.4 px on its
    // own phase while zoomed out. It re-evaluated every window's position and
    // rebuilt the cluster threads 60 times a second at rest (measured: 21% of
    // a core zoomed out, against 1.2% without it), for decoration only. The
    // motion that stays is the motion the hand causes.

    // The grasp's jump: the world is the map, so a window clicked while
    // the hold is zoomed out is the release's destination - the hold that
    // jumped commits the clicked location, whatever the zoom.
    property bool graspJumped: false
    // The grasp's jump flies to the window's location at 1:1, whatever the
    // hold's zoom: the destination is the location itself, and the release
    // commits it.
    function graspFly(e) {
        const others = [];
        for (let i = 0; i < entries.length; ++i) {
            if (entries[i] === e) continue;
            others.push({ x: entries[i].x, y: entries[i].y, width: entries[i].width, height: entries[i].height });
        }
        const d = Logic.smartPan({ x: e.x, y: e.y, width: e.width, height: e.height }, actionScreen().geometry, viewX, viewY, 1.0, 24);
        dbg("map", "flying to " + Math.round(viewX + d.dx) + "," + Math.round(viewY + d.dy) + " (" + Math.round(d.dx) + "," + Math.round(d.dy) + " delta)");
        camGo(1.0, viewX + d.dx, viewY + d.dy, undefined, undefined, 2.0);
    }
    function graspJumpTo(i) {
        if (i < 0 || i >= entries.length) return;
        dbg("map", "window " + i + " (" + entries[i].window.caption + ") jumped to");
        noteGesture();
        graspJumped = true;
        graspFly(entries[i]);
    }
    // The world's cluster chips fly the camera to fit the cluster: the hold
    // keeps its view (the fit never passes zoom 0.75), and the release
    // lands the overworld there.
    // The bounds of a cluster, over its live entries, for the switcher's
    // cluster fit and the chip flight. ids holds window internalIds, so
    // each one is looked up in the live entries rather than used as an
    // index.
    function clusterRect(ci) {
        const c = clusters[ci];
        if (!c || !c.ids || !c.ids.length) return null;
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (let i = 0; i < c.ids.length; ++i) {
            const e = entries.find(en => en.window.internalId === c.ids[i]);
            if (!e) continue;
            x0 = Math.min(x0, e.x); y0 = Math.min(y0, e.y);
            x1 = Math.max(x1, e.x + e.width); y1 = Math.max(y1, e.y + e.height);
        }
        if (x0 === Infinity) return null;
        return { x: x0, y: y0, width: x1 - x0, height: y1 - y0 };
    }

    function graspClusterTo(ci) {
        dbg("chip", "graspClusterTo ci=" + ci + " grasp=" + grasp + " n=" + clusters.length);
        if (!grasp || ci < 0 || ci >= clusters.length) return;
        const r = clusterRect(ci);
        if (!r) return;
        const w = r.width, h = r.height;
        const sg = actionScreen().geometry;
        const z = Math.min(0.75, Math.max(0.2, Math.min(sg.width / (w + 48), sg.height / (h + 48))));
        const cx = r.x + w / 2, cy = r.y + h / 2;
        dbg("map", "cluster " + (ci + 1) + " chip: flying to zoom " + z.toFixed(2) + " at (" + Math.round(cx) + "," + Math.round(cy) + ")");
        noteGesture();
        camGo(z, cx - (sg.x + sg.width / 2) / z, cy - (sg.y + sg.height / 2) / z, undefined, undefined, 2.0);
    }

    // ---- floating windows ----------------------------------------------------
    // A floating window's coordinates on the plane never change - only the
    // hand moves them. Its picture is what floats: whenever the camera
    // would push the window partly off the screen, the picture rides at the
    // screen's edge and, pushed there fast, bounces off the edge with real
    // physics before settling against it; move the camera back and the
    // picture is the window again, at its coordinates. The flag is KWin's
    // own "on all desktops", repurposed - the title-bar menu's pin entry
    // and the canvas agree on what floats - and the caption list
    // persists the choice.
    // One state, "pinned": the window stays with you. KWin holds it, so the
    // title bar's own menu, the pill, the panel applet and the canvas all read
    // the same thing and nothing here is stored. It is on whenever KWin has
    // the window on all desktops or kept above (set either from anywhere and
    // the canvas floats it), and the one toggle sets or clears both, and
    // clears keep-below, which would contradict it.
    property var pinned: ({})          // caption -> { sx, sy }, where the hand left it (this session)
    property var floatOf: ({})         // window internalId -> { x, y, vx, vy, wasInX, wasInY }, screen px
    property real floatRev: 0
    property real floatPrevViewX: 0
    property real lastFloatAt: 0
    property real floatPrevViewY: 0
    // How many entries are pinned, recounted on every resync and revision:
    // the frame tick skips the float walk when it is 0.
    readonly property int pinnedCount: { revision; let n = 0; for (let i = 0; i < entries.length; ++i) if (isPinnedEntry(entries[i])) n++; return n; }
    function floatHeld() { for (const id in floatOf) return true; return false; }
    function windowPinned(w) { return !!w && !w.deleted && (w.onAllDesktops || w.keepAbove); }
    function isPinnedEntry(e) { return !!e && windowPinned(e.window); }
    function setPinned(w, on) {
        if (!w || w.deleted) return;
        w.onAllDesktops = on;
        w.keepAbove = on;
        if (on) w.keepBelow = false;
    }
    function pinEntries(list) {
        for (let i = 0; i < list.length; ++i) if (list[i]) setPinned(list[i].window, true);
    }
    function unpinEntries(list) {
        for (let i = 0; i < list.length; ++i) {
            const e = list[i];
            if (!e) continue;
            setPinned(e.window, false);
            delete pinned[e.window.caption];
        }
    }
    // The screen spot that keeps the window wholly inside the screen the
    // pointer is on, with a margin. The anchor the pin holds, and the place
    // a bounced window settles. The optional tx/ty override reads a landing
    // spot instead of the entry's live one (the arrange and the send-to
    // clamp the destination while the window is still gliding to it).
    function clampScreen(e, tx, ty) {
        const g = actionScreen().geometry;
        const w = e.width * zoom, h = e.height * zoom;
        const m = 8;
        let sx = ((tx !== undefined ? tx : e.x) - viewX) * zoom;
        let sy = ((ty !== undefined ? ty : e.y) - viewY) * zoom;
        if (w < g.width - 2 * m) sx = Math.max(g.x + m, Math.min(g.x + g.width - w - m, sx));
        else sx = g.x + m;
        if (h < g.height - 2 * m) sy = Math.max(g.y + m, Math.min(g.y + g.height - h - m, sy));
        else sy = g.y + m;
        return { sx: sx, sy: sy };
    }
    function togglePin() {
        const list = arrangeTargets();
        if (list.length === 0) return;
        let allPinned = true;
        for (let i = 0; i < list.length; ++i) if (!isPinnedEntry(list[i])) { allPinned = false; break; }
        if (allPinned) unpinEntries(list); else pinEntries(list);
        revision++;
    }
    // The screen bounds a floating window's picture is kept inside, with a
    // margin, on the screen the pointer is on.
    function floatBounds(e) {
        const sg = (e.window && !e.window.deleted && e.window.screen) || actionScreen();
        const g = sg.geometry;
        const m = 8;
        const w = e.width * zoom, h = e.height * zoom;
        let l = g.x + m, r = g.x + g.width - w - m, t = g.y + m, b = g.y + g.height - h - m;
        if (w >= g.width - 2 * m) l = r = g.x + m;
        if (h >= g.height - 2 * m) t = b = g.y + m;
        return { l: l, r: r, t: t, b: b };
    }
    // One tick of the float. The picture sits exactly on the window while
    // the window is inside the screen - the coordinates never move, the
    // picture is at rest - carrying only the camera's own velocity, so a
    // fast push into an edge becomes a real bounce off it: the carried
    // velocity reflects, damped, and a critically damped spring settles the
    // picture back against the edge. The hand on a drag owns the picture
    // outright. The velocity is the camera's pan alone, the zoom's
    // contribution left out, so the physics scales with the zoom instead of
    // exploding under it. Runs while the canvas is visible, a slide at 1:1
    // included.
    function floatPinned(dt) {
        // After a stall the last camera position is stale: a fresh start
        // must not read a wild velocity out of it.
        const now = Date.now();
        if (now - lastFloatAt > 100) { floatPrevViewX = viewX; floatPrevViewY = viewY; }
        lastFloatAt = now;
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            const id = e.window.internalId;
            if (!isPinnedEntry(e)) { if (floatOf[id]) { delete floatOf[id]; floatRev++; } continue; }
            const b = floatBounds(e);
            const tx = (e.x - viewX) * zoom, ty = (e.y - viewY) * zoom;
            const cx = Math.max(b.l, Math.min(b.r, tx)), cy = Math.max(b.t, Math.min(b.b, ty));
            let f = floatOf[id];
            if (!f) { floatOf[id] = f = { x: tx, y: ty, vx: 0, vy: 0, wasInX: true, wasInY: true }; }
            const dragging = dragIndex >= 0 && dragRaw[id];
            const camVX = dt > 0.0001 ? -(viewX - floatPrevViewX) / dt * zoom : 0;
            const camVY = dt > 0.0001 ? -(viewY - floatPrevViewY) / dt * zoom : 0;
            Logic.floatStep(f, tx, ty, cx, cy, b.l, b.r, b.t, b.b, camVX, camVY, dragging, dt);
        }
        floatPrevViewX = viewX;
        floatPrevViewY = viewY;
        // Advances only while a window floats: its picture rides the camera.
        // Every thumbnail's position binds to floatRev, so advancing it with
        // nothing floating re-evaluated them all each frame for nothing.
        let floating = false;
        for (const fid in floatOf) { floating = true; break; }
        if (floating) floatRev += dt * 62.5;
    }
    // ---- hover navigation ----------------------------------------------------
    // The pointer rests on a window and the camera pans the least that brings
    // it wholly into view. Polled from the event loop rather than the scene's
    // handlers: with the pass-through plugin live, the plugin consumes the
    // pointer over a window's client area, so the scene never sees the hover
    // there - and it is exactly there that the hover should navigate. The
    // global pointer always carries the real screen position, whatever owns
    // the events. The hover never fights the hand: it waits out a grace
    // period after any gesture, so a window the hand just dragged off the
    // edge stays there, and it acts once per rest.
    property var hoverEntry: null
    property real hoverSince: 0
    // The overworld's z-order IS the real stacking order: a hover raises the
    // window for real the moment the eye has rested on it (the focus
    // settle), so the picture, the web and the desktop can never disagree,
    // and the raise survives the step back in. The restack comes back
    // through KWin's own stacking signal and the resync, so the canvas never
    // moves a window twice. A pass-over, a menu and a gesture never raise -
    // only the rest does.
    property int hoverRev: 0
    function noteHovered(e) {
        hoverRev++;
        const stack = KWin.Workspace.stackingOrder;
        if (stack.length === 0 || stack[stack.length - 1] === e.window) return;
        KWin.Workspace.raiseWindow(e.window);
    }
    property bool hoverBrought: false
    property real lastGestureAt: 0
    property bool handGesture: false

    // The seam: the desk's outer few pixels. A tool that shares the mouse
    // with another machine (deskflow, synergy) parks the pointer on the
    // screen border it hands the mouse over across, and there it sits - a
    // pointer the desk itself put there, not the hand. A hover that reads
    // the parked pointer would glow and pan to whatever window the seam
    // touches, so points inside this band hover nothing: a living hand
    // never rests in it.
    readonly property real seamMargin: 6
    property bool seamPark: false
    function screensAsRects() {
        const ss = KWin.Workspace.screens;
        const out = [];
        for (let i = 0; i < ss.length; ++i) {
            const g = ss[i].geometry;
            out.push({ x: g.x, y: g.y, width: g.width, height: g.height });
        }
        return out;
    }
    function seamAt(p) {
        return Logic.seamPoint(screensAsRects(), p.x, p.y, seamMargin);
    }

    // ---- clusters -------------------------------------------------------------
    // Windows that sit near each other on the plane are a cluster: formed
    // automatically as windows are dragged together, parted as they are
    // dragged apart. A cluster wears a fluid thread through its windows - a
    // constellation - and the bracket keys fly the camera between clusters in
    // reading order, the plane's own tour. Everything is derived: nothing is
    // stored, so a cluster follows its windows as they move.
    property var clusters: []          // [{ cx, cy, n, ids, co }], centroids in canvas px
    property var clusterOf: ({})       // entry window internalId -> cluster index
    property var threadRank: ({})      // internalId -> rank, the thread's stable order
    property int clusterRev: 0
    // The gap that makes one cluster and the clustering itself live in
    // logic.js - the pure, unit-tested half - and this is the wiring: the
    // entries become rects, the pure recluster runs, and the effect keeps
    // the results.
    function recluster() {
        const rects = [];
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            rects.push({ x: e.x, y: e.y, width: e.width, height: e.height, id: e.window.internalId });
        }
        const r = Logic.recluster(rects, clusterOf, threadRank, configuration.ClusterGap);
        clusters = r.clusters;
        clusterOf = r.clusterOf;
        threadRank = r.ranks;
        clusterRev++;
        // The chips' model freezes during the quiet grasp (the scene's
        // Repeater models do not re-evaluate then), so the count is kept
        // current HERE, while the model still answers: the delegates must
        // already exist when the hold begins. Their visibility gate runs
        // on the grasp's own state.
        chipCount = clusters.length;
    }

    // The cluster the eye is on: the hovered window's, else the selected
    // one's, else the focused window's. The travel starts from it, and the
    // travel's own destination becomes the anchor for the next step, so the
    // bracket keys walk the tour instead of ping-ponging back to whatever
    // window happens to be focused.
    property int travelCluster: -1
    function clusterIndexOfEntry(e) {
        if (!e || !e.window) return -1;
        const i = clusterOf[e.window.internalId];
        return i === undefined ? -1 : i;
    }
    function clusterIndex() {
        let i = clusterIndexOfEntry(focusEntry);
        if (i >= 0) return i;
        for (let k = 0; k < entries.length; ++k) {
            if (isSelected(entries[k])) {
                i = clusterIndexOfEntry(entries[k]);
                if (i >= 0) return i;
            }
        }
        if (travelCluster >= 0 && travelCluster < clusters.length) return travelCluster;
        const w = KWin.Workspace.activeWindow;
        if (w && !w.deleted) { const e = entryFor(w); if (e) return clusterIndexOfEntry(e); }
        return -1;
    }
    // Fly to cluster ci: a room remembers where you left it - the stored
    // home wins - else the camera springs to the cluster's last-focused
    // window (the one the hand left there), smart-placed, at the current
    // zoom; a cluster no one has focused falls back to its centre.
    function flyToCluster(ci, preferHome) {
        if (ci < 0 || ci >= clusters.length) return;
        const c = clusters[ci];
        const fp = clusterFingerprint(c);
        const g = actionScreen().geometry;
        // The switch's focus: the most-recently-focused window of the
        // cluster being arrived at - like switching a workspace, the
        // arrival lands on the window the hand last used there, and the
        // glow, the pick and the next step all point at it.
        let dest = null;
        let bestAt = 0;
        for (const id of c.ids) {
            const at = focusAt[id] || 0;
            if (at > bestAt) { bestAt = at; dest = id; }
        }
        const destEntry = dest !== null ? entries.find(function (en) { return en.window.internalId === dest; }) : null;
        if (destEntry) focusEntry = destEntry;
        // The remembered spot: the digit jumps return to it (the room's
        // place), the tour never does - a hop is a switch, and it lands on
        // the window the hand last used there.
        if (preferHome !== false) {
            const home = clusterHomes[fp];
            if (home && Number.isFinite(home.x) && Number.isFinite(home.y) && home.z > 0) {
                camGo(home.z, home.x, home.y, undefined, undefined, 3.0);
                toast(clusterNames[fp] ? ("Back to " + clusterNames[fp]) : ("Back to cluster " + (ci + 1)));
                return;
            }
        }
        // Smart placement: pan the least that brings the window wholly on
        // screen, padded, then pull the neighbours in - the focused window
        // stays completely inside while as many of the windows around it
        // as possible come at least partially into view. A cluster no one
        // has focused falls back to its centre.
        let dx, dy;
        if (destEntry) {
            const others = [];
            for (let i = 0; i < entries.length; ++i) {
                if (entries[i] !== destEntry) {
                    others.push({ x: entries[i].x, y: entries[i].y, width: entries[i].width, height: entries[i].height });
                }
            }
            const d = smartPan({ x: destEntry.x, y: destEntry.y, width: destEntry.width, height: destEntry.height }, others, 24);
            dx = d.dx;
            dy = d.dy;
        } else {
            dx = c.cx - (g.x + g.width / 2) / zoom - viewX;
            dy = c.cy - (g.y + g.height / 2) / zoom - viewY;
        }
        camGo(zoom, viewX + dx, viewY + dy, undefined, undefined, 3.0);
        toast(destEntry ? destEntry.window.caption : ("Cluster " + (ci + 1) + " of " + clusters.length));
    }
    // Fly to the next or previous cluster in reading order (top to bottom,
    // left to right), from the one the eye is on. A hop is a switch: it
    // lands on the next cluster's most-recently-focused window, smart-
    // placed, every time - the remembered spots belong to the digit
    // jumps. The room the flight leaves remembers the camera spot for
    // them. The toast names the stop.
    function clusterTravel(dir) {
        if (clusters.length === 0) return;
        const cur = clusterIndex();
        // The room we leave remembers where we left it.
        if (cur >= 0 && cur < clusters.length) {
            const fp = clusterFingerprint(clusters[cur]);
            clusterHomes[fp] = { x: viewX, y: viewY, z: zoom };
            saveClusterState();
        }
        const order = [];
        for (let i = 0; i < clusters.length; ++i) order.push(i);
        order.sort(function (p, q) { return (clusters[p].cy - clusters[q].cy) || (clusters[p].cx - clusters[q].cx); });
        let k = 0;
        if (cur >= 0) {
            const pos = order.indexOf(cur);
            k = (pos + dir + order.length) % order.length;
        } else if (dir < 0) k = order.length - 1;
        travelCluster = order[k];
        // The jump leaves the old hover behind: the tour anchors to the
        // destination until the eye settles on something new.
        hoverEntry = null;
        focusEntry = null;
        flyToCluster(order[k], false);
    }
    // The digit keys: jump straight to cluster N (the badge's number), the
    // absolute travel - no walk, no order step. The room it leaves
    // remembers the spot, like the tour's departure.
    function clusterJumpTo(n) {
        dbg("jump", "digit " + n + " of " + clusters.length);
        if (n < 1 || n > clusters.length) return;
        const cur = clusterIndex();
        if (cur >= 0 && cur < clusters.length && cur !== n - 1) {
            const fp = clusterFingerprint(clusters[cur]);
            clusterHomes[fp] = { x: viewX, y: viewY, z: zoom };
            saveClusterState();
        }
        const ci = n - 1;
        hoverEntry = null;
        focusEntry = null;
        travelCluster = ci;
        flyToCluster(ci);
    }
    // The undo stack: every commit leaves its layout behind - the targets,
    // the windows' spots, the activities they ended on - and Ctrl+Z (or the
    // debug channel's undo) steps the plane back to the one beneath the
    // last. The stack holds up to twenty layouts, in the session only.
    property var undoStack: []
    // The windows glide to the spots the plane gives them: the tidy (and
    // whatever else moves entries without the hand) animates the travel
    // instead of teleporting it. Each anim is a straight 220 ms glide in
    // the physics tick; the commit finishes them instantly so a geometry
    // write never catches a window mid-flight.
    // The moves are physical. A window that the hand drops keeps the throw's
    // momentum and coasts to a stop; a batch move (the arrange, the tidy,
    // the undo, the commit) cascades through its windows with a springy
    // landing; and while a window travels it leaves a fading afterimage at
    // the spot it left - the move is visible, not a cut.
    property var entryAnims: ({})
    property var entryGhosts: ({})
    property int moveRev: 0
    function animateEntry(e, tx, ty, delay, vx, vy) {
        if (!e || !e.window) return;
        if (configuration.MovesGlide === false) { e.x = tx; e.y = ty; return; } // the knob: the instant writes
        const id = e.window.internalId;
        if (dragRaw && dragRaw[id] !== undefined) return; // the hand moves its own
        // The glide's pace and bounce follow the move itself: a far throw
        // flies longer and overshoots harder, a nudge settles quick with
        // barely a bounce. The batch waves keep the small overshoot.
        const dist = Math.hypot(tx - e.x, ty - e.y) / Math.max(0.25, zoom);
        const spd = Math.hypot(vx || 0, vy || 0) / Math.max(0.25, zoom);
        entryAnims[id] = { sx: e.x, sy: e.y, tx: tx, ty: ty, t0: Date.now() + (delay || 0), vx: vx || 0, vy: vy || 0,
            dur: Math.min(320, Math.max(150, 150 + dist * 0.28)), amp: Math.min(3.4, 2.2 + spd * 0.0006) };
        entryGhosts[id] = { x: e.x, y: e.y, w: e.width, h: e.height, born: Date.now() };
        moveRev++;
    }
    function stepEntryAnims() {
        const now = Date.now();
        let any = false;
        for (const id in entryAnims) {
            const a = entryAnims[id];
            const e = entries.find(function (en) { return String(en.window.internalId) === id; });
            if (!e) { delete entryAnims[id]; delete entryGhosts[id]; any = true; continue; }
            const dur = a.dur || 240;
            const p = Math.min(1, (now - a.t0) / dur);
            if (p >= 1) {
                e.x = a.tx;
                e.y = a.ty;
                delete entryAnims[id];
                delete entryGhosts[id];
            } else if (p <= 0) {
                e.x = a.sx;
                e.y = a.sy;
            } else {
                const amp = a.amp || 2.4; // the overshoot: the harder the throw, the deeper the bounce
                const out = 1 + amp * Math.pow(p - 1, 3) + amp * 0.5 * Math.pow(p - 1, 2); // the OutBack: the springy landing with the little overshoot
                const h3 = p * p * (3 - 2 * p); // the Hermite for the throw: the velocity eases to rest
                const qx = a.vx ? h3 + a.vx * dur / Math.max(1, Math.abs(a.tx - a.sx)) * (p - 2 * p * p + p * p * p) : out;
                const qy = a.vy ? h3 + a.vy * dur / Math.max(1, Math.abs(a.ty - a.sy)) * (p - 2 * p * p + p * p * p) : out;
                e.x = a.sx + (a.tx - a.sx) * Math.max(0, Math.min(2, qx));
                e.y = a.sy + (a.ty - a.sy) * Math.max(0, Math.min(2, qy));
            }
            any = true;
        }
        if (any) moveRev++;
    }
    function finishEntryAnims() {
        const keys = Object.keys(entryAnims);
        for (let i = 0; i < keys.length; ++i) {
            const a = entryAnims[keys[i]];
            const e = entries.find(function (en) { return String(en.window.internalId) === keys[i]; });
            if (e) {
                e.x = a.tx;
                e.y = a.ty;
            }
        }
        entryAnims = {};
        entryGhosts = {};
        if (keys.length) moveRev++;
    }
    function restoreLayout(back) {
        if (!back) return;
        targets = copyTargets(back.targets);
        const byId = {};
        for (const p of back.layout) byId[p.internalId] = p;
        for (const e of entries) {
            const p = byId[e.window.internalId];
            if (!p) continue;
            animateEntry(e, p.x, p.y); // the undo glides home - the reverse of the move
            e.activity = p.activity;
            if (p.activity && e.window.activities.length > 0 && e.window.activities.indexOf(p.activity) === -1)
                e.window.activities = [p.activity];
        }
        for (const e of entries) {
            if (e.window.deleted) continue;
            const p = byId[e.window.internalId];
            if (!p) continue;
            const t = targetOf(e.activity);
            const fx = Math.round(p.x - t.x), fy = Math.round(p.y - t.y);
            e.frameX = fx;
            e.frameY = fy;
            e.window.frameGeometry = Qt.rect(fx, fy, e.width, e.height);
        }
        revision++;
        toast("Stepped the layout back");
    }
    function undo() {
        // The top of the stack is the commit just made; the undo restores
        // the layout beneath it. The first commit ever made leaves nothing
        // to step back to.
        if (undoStack.length < 2) { toast("Nothing to undo"); return; }
        undoStack.pop();
        restoreLayout(undoStack[undoStack.length - 1]);
    }
    // A window's z in the overworld: the stacking order itself - the entries
    // are KWin's order, so the index IS the z - with the hovered window
    // lifted above the whole web. The hover has just raised that window for
    // real, so the picture and the desktop keep the same order. The threads
    // travel the depth between their two windows - each stretch of a thread
    // carries the mix of the two endpoints' z at that point - so the
    // constellation weaves over the lower, under the higher, and ducks under
    // any window in the way, re-threading live as the eye moves.
    function windowZ(e) {
        return e === focusEntry ? 2000 : 1000 + entries.indexOf(e);
    }
    // The cluster webs, flattened: every pair of windows in every cluster,
    // in this screen's coordinates, one entry per thread. The z only counts
    // at the view level - a child's z cannot lift it out of its parent - so
    // the threads are one flat list, not nested under the clusters. Each
    // thread is cut at every window crossing and each stretch carries the z
    // the thread has at that point - the linear mix of its two windows' z -
    // so the web weaves over the lower, under the higher, and ducks under
    // any window that covers a middle stretch. The geometry lives in the
    // plane's own coordinates: the camera is a uniform transform and the
    // segment-rect cuts are invariant under it, so the O(N^2) clipping runs
    // only when the layout changes (the stack, the clusters, the float, the
    // hover) and the delegates apply the camera per frame.
    function clusterThreads() {
        if (quiet) return [];
        // The windows as occlusion rects in the plane's coordinates (the
        // float's picture included, since that is what the eye sees), each
        // at its stack z: the threads cross them like a wire through the
        // stack, above the lower and beneath the higher.
        const rects = [];
        for (let k = 0; k < entries.length; ++k) {
            const e = entries[k];
            const f = floatOf[e.window.internalId];
            rects.push({
                // The float's picture is stored in screen coordinates, so it
                // is translated back onto the plane before it occludes: a
                // window clamped at the screen's edge must cut the threads
                // where the eye sees its picture, not where its old canvas
                // spot was.
                x: f ? viewX + f.x / zoom : e.x,
                y: f ? viewY + f.y / zoom : e.y,
                w: e.width,
                h: e.height
            });
        }
        const out = [];
        for (let i = 0; i < clusters.length; ++i) {
            const c = clusters[i];
            if (!c || c.n < 2) continue;
            const lit = clusterIndex() === i;
            const pts = [];
            for (let k = 0; k < c.ids.length; ++k) {
                const e = entryById(c.ids[k]);
                if (!e) continue;
                const idx = entries.indexOf(e);
                    pts.push({
                    x: e.x + e.width / 2,
                    y: e.y + e.height / 2,
                    z: windowZ(e)
                });
            }
            for (let a = 0; a < pts.length; ++a) {
                for (let b = a + 1; b < pts.length; ++b) {
                    const spans = Logic.threadSpans(pts[a].x, pts[a].y, pts[b].x, pts[b].y, pts[a].z, pts[b].z, rects);
                    for (let s = 0; s < spans.length; ++s) {
                        const sp = spans[s];
                        out.push({ x1: sp.x1, y1: sp.y1, x2: sp.x2, y2: sp.y2,
                                   z: sp.z, lit: lit, co: c.co });
                    }
                }
            }
        }
        return out;
    }
    function entryById(id) {
        for (let i = 0; i < entries.length; ++i) if (entries[i].window.internalId === id) return entries[i];
        return null;
    }

    // ---- cluster workspaces ----------------------------------------------------
    // Clusters are the plane's rooms: each keeps its own camera home and a
    // name the hand can give it. The key is the cluster's fingerprint - its
    // members' ids, sorted - which survives reclusters and re-orders. The
    // tour leaves a room at the camera spot it had, and returns there the
    // next time; the digit keys jump straight to a room.
    property var clusterHomes: ({})   // fingerprint -> { x, y, z }
    property var clusterNames: ({})   // fingerprint -> name
    function clusterFingerprint(c) {
        if (!c || !c.ids || c.ids.length === 0) return "";
        return c.ids.slice().sort().join(",");
    }
    function loadClusterState() {
        let h = {};
        let n = {};
        try { h = JSON.parse(configuration.ClusterHomes || "{}"); } catch (err) { h = {}; }
        try { n = JSON.parse(configuration.ClusterNames || "{}"); } catch (err) { n = {}; }
        clusterHomes = h;
        clusterNames = n;
    }
    function saveClusterState() {
        configuration.ClusterHomes = JSON.stringify(clusterHomes);
        configuration.ClusterNames = JSON.stringify(clusterNames);
        configuration.writeConfig();
    }
    // ---- states KWin keeps in screen coordinates ------------------------------
    // A maximized or tiled window has a restore rectangle that KWin keeps in
    // screen coordinates, which a script can neither read nor write. The
    // canvas moves the real windows when the view slides, so after a slide
    // that rectangle is stale: unmaximize put the window where the plane no
    // longer had it (measured: 300 and 200 px off after a slide of that
    // size). The plane is the truth. Note where the window sat on it as it
    // leaves the free state, and as it comes back put it at that place
    // under the view as it now is. Only with the canvas closed: an open
    // canvas absorbs a window's own geometry changes into the plane.
    property var planeRestore: ({})
    property var holdTrack: ({})
    property var watchedWindows: ({})
    property var dirtyWindows: ({})
    property var restoreQueue: []
    function windowFree(w) { return !w.maximizeMode && !w.tile && !w.fullScreen; }
    // While a window is free its plane spot is kept, sampled once its
    // geometry has settled (a plane coordinate, so the canvas's own slides
    // leave it true). The sample waits because KWin changes the geometry
    // before it flips the maximized or tiled flag: read on the change itself
    // and the maximized rectangle would be taken for the free spot. Settled,
    // the window is no longer free and the last free spot is the one kept.
    function trackFree(w) {
        if (!w || w.deleted || holdTrack[w.internalId] || !windowFree(w)) return;
        const t = targetOf(activityOf(w)), g = w.frameGeometry;
        planeRestore[w.internalId] = { x: g.x + t.x, y: g.y + t.y };
    }
    function markDirty(w) {
        dirtyWindows[w.internalId] = w;
        sampleTimer.restart();
    }
    Timer {
        id: sampleTimer
        interval: 120
        repeat: false
        onTriggered: {
            const d = effect.dirtyWindows;
            effect.dirtyWindows = ({});
            for (const id in d) effect.trackFree(d[id]);
        }
    }
    function noteReturnedFree(w) {
        if (!w || w.deleted || !windowFree(w)) return;
        const id = w.internalId, r = planeRestore[id];
        if (!r || holdTrack[id]) return;
        // Hold the sampler: KWin is about to put the window at its own
        // restore spot, and that must not overwrite the plane's.
        holdTrack[id] = true;
        restoreQueue.push({ w: w, r: r });
        restoreTimer.restart();
    }
    function restoreToPlane(w, r) {
        if (!w || w.deleted) return;
        delete holdTrack[w.internalId];
        if (!visible && windowFree(w)) {
            const t = targetOf(activityOf(w)), g = w.frameGeometry;
            const fx = Math.round(r.x - t.x), fy = Math.round(r.y - t.y);
            if (Math.abs(g.x - fx) >= 1 || Math.abs(g.y - fy) >= 1) {
                dbg("restore", "back to the plane: " + Math.round(g.x) + "," + Math.round(g.y) + " -> " + fx + "," + fy);
                w.frameGeometry = Qt.rect(fx, fy, g.width, g.height);
            }
        }
        trackFree(w);
    }
    Timer {
        id: restoreTimer
        interval: 150
        repeat: false
        onTriggered: {
            const q = effect.restoreQueue;
            effect.restoreQueue = [];
            for (let i = 0; i < q.length; ++i) effect.restoreToPlane(q[i].w, q[i].r);
        }
    }
    function watchWindow(w) {
        if (!w || watchedWindows[w.internalId]) return;
        watchedWindows[w.internalId] = true;
        trackFree(w);
        w.frameGeometryChanged.connect(function () { effect.markDirty(w); });
        w.maximizedChanged.connect(function () { effect.noteReturnedFree(w); });
        w.tileChanged.connect(function () { effect.noteReturnedFree(w); });
    }
    function watchAllWindows() {
        const all = KWin.Workspace.stackingOrder;
        for (let i = 0; i < all.length; ++i) watchWindow(all[i]);
    }

    // Bookmarks: nine named views. Ctrl+digit keeps where the camera is
    // looking (or is flying to) and how far out, Alt+digit flies back on the
    // camera's own spring. Per slot, kept in the config so a restart keeps them.
    property var bookmarks: ({})
    function loadBookmarks() {
        let b = {};
        try { b = JSON.parse(configuration.Bookmarks || "{}"); } catch (err) { b = {}; }
        bookmarks = b;
    }
    function bookmarkSet(n) {
        if (!(n >= 1 && n <= 9) || !visible) return;
        // A flight in progress is saved at where it is going: that is the
        // view the hand meant.
        const b = {
            x: camHasGoal ? camGoalX : viewX,
            y: camHasGoal ? camGoalY : viewY,
            z: camHasGoal ? camGoalZoom : zoom
        };
        if (!Number.isFinite(b.x) || !Number.isFinite(b.y) || !(b.z > 0)) return;
        const all = Object.assign({}, bookmarks);
        all[n] = b;
        bookmarks = all;
        configuration.Bookmarks = JSON.stringify(all);
        configuration.writeConfig();
        toast("Bookmark " + n + " saved");
    }
    function bookmarkGo(n) {
        if (!(n >= 1 && n <= 9) || !visible) return;
        const b = bookmarks[n];
        if (!b) { toast("No bookmark " + n); return; }
        noteGesture();
        camGo(b.z, b.x, b.y, undefined, undefined, 2.0);
    }
    // The toast: a brief glass chip naming what just happened.
    property string toastText: ""
    property int toastRev: 0
    function toast(text) { toastText = text; toastRev++; toastTimer.restart(); }
    Timer {
        id: toastTimer
        interval: 1500
        repeat: false
        onTriggered: { effect.toastText = ""; effect.toastRev++; }
    }
    // The window the pointer has settled on: the canvas's focus. Enter
    // applies with it, and it wears a glow, so the eye always knows which
    // window the canvas considers yours. Clicking, which also focuses the
    // window itself, is what hands the keyboard over.
    property var focusEntry: null
    function noteGesture(hand) { lastGestureAt = Date.now(); handGesture = !!hand; }
    function hoverTick() {
        if (closing || canvasMenus > 0 || camLive()) return;
        const p = cursorScreen();
        // The seam bookkeeping runs whenever the canvas is up, grasp
        // included: the grasp's grips read seamPark, and the tick that keeps
        // it honest must not stop just because the hold is quiet - a stale
        // "parked" would steal the drags from the hand for the whole hold.
        if (seamAt(p)) {
            if (hoverEntry !== null || focusEntry !== null || !seamPark) {
                hoverEntry = null;
                focusEntry = null;
                hoverSince = 0;
                hoverBrought = false;
                seamPark = true;
            }
            return;
        }
        seamPark = false;
        // The system's own chrome (a dock, a panel, a popup) owns its
        // pixels: a rest on it is not a hover on the window under it, so
        // nothing is focused, panned or raised there. The chrome flag is
        // published by the pass-through on every pointer event, grasp
        // included.
        if (chromeHover) {
            if (hoverEntry !== null || focusEntry !== null) {
                hoverEntry = null;
                focusEntry = null;
                hoverSince = 0;
                hoverBrought = false;
            }
            return;
        }
        // A pointer parked on the seam is not a hover: the desk put it there
        // (deskflow handing the mouse to another machine), not the hand.
        // The pass-through's own rest shows the cue while its clock runs;
        // the canvas's glow waits for the handoff instead of duelling
        // with that cue, so the two never overlap.
        // A parked close that has waited out its welcome is forced: a stuck gesture loses to the user's intent.
        if (deferredClose !== null && Date.now() - deferredAt > 5000) {
            const fn = deferredClose;
            deferredClose = null;
            deferredAt = 0;
            sceneGestures = 0;
            fn();
            return;
        }
        if (navHeld || quiet || pointerButtons !== Qt.NoButton || (restStart !== "" && passthroughLive)) return;
        const c = globalToCanvas(p.x, p.y);
        let e = null;
        for (let i = entries.length - 1; i >= 0; --i) {
            const en = entries[i];
            if (c.x >= en.x && c.x < en.x + en.width && c.y >= en.y && c.y < en.y + en.height) { e = en; break; }
        }
        const now = Date.now();
        if (e !== hoverEntry) {
            hoverEntry = e;
            hoverSince = now;
            hoverBrought = false;
            return;
        }
        // A drag the hand just let go of keeps the grace, so the hover never
        // un-pans a window the hand placed; a plain rest settles quicker.
        const grace = handGesture ? 600 : 320;
        if (now - lastGestureAt < grace) {
            hoverSince = now;
            return;
        }
        // The camera's fetch asks for the window on screen at HALF the
        // pointer's own handoff pause (HoverDelay): the move precedes the
        // handoff, so the window has settled into view before it changes
        // hands - the whole point of the hover. Never sooner than the old
        // 200 ms.
        const hoverRest = Math.max(200, Math.round(Number(configuration.HoverDelay) * 0.5));
        if (e && now - hoverSince >= hoverRest) {
            if (!hoverBrought) {
                hoverBrought = true;
                // A pause on the way to a dock or panel is a pointer in
                // transit, not an interest in the window it stopped over:
                // the fetch would drag the camera as the hand reaches for the
                // panel.
                if (!nearDock(p.x, p.y)) bringIntoView(e);
            }
            if (focusEntry !== e) {
                focusEntry = e;
                noteHovered(e);
            }
        } else if (!e && focusEntry) {
            focusEntry = null;
        }
    }
    Timer {
        interval: 100
        repeat: true
        running: effect.visible && !effect.closing
        onTriggered: effect.hoverTick()
    }

    // ---- key bindings, from config ------------------------------------------
    // Each entry is a list of Qt key codes parsed from a comma-separated list
    // of Qt key names without the Key_ prefix ("Return,Enter").
    property var bindings: ({})

    // "Meta+Tab" -> "Tab": the key whose release ends a chord hold, so the
    // release-enter's bound() lookup names the tail key, not the chord.
    function chordTail(spec) {
        const parts = String(spec || "").split("+");
        return parts[parts.length - 1].trim();
    }
    function keysFor(spec) {
        const out = [];
        const names = String(spec || "").split(",");
        for (let i = 0; i < names.length; ++i) {
            const n = names[i].trim();
            if (!n) continue;
            const code = Qt["Key_" + n];
            if (code === undefined) { console.warn("kwin-canvas: unknown key name", n); continue; }
            out.push(code);
        }
        return out;
    }

    // Mouse buttons that navigate while held down, as a mask: parsed from the
    // same comma-separated Qt button names as the keys ("RightButton" ->
    // Qt.RightButton). An unknown name is logged and skipped, as above.
    // The side buttons need both of their Qt names: KWin delivers a mouse's
    // MB5 as Qt::ExtraButton3 (TaskButton), not Qt::ForwardButton - its
    // button table maps BTN_FORWARD (0x115, the same code as BTN_EXTRA) to
    // ExtraButton3, which wins over the ExtraButton2 entry for that code -
    // and MB4 as ExtraButton1 (Qt::BackButton), while some devices report it
    // as BTN_BACK (0x116), ExtraButton4. The mask is what the plane-input
    // shim and the pass-through plugin compare against, so it has to name
    // the buttons KWin itself sees.
    function buttonsFor(spec) {
        let mask = 0;
        const names = String(spec || "").split(",");
        for (let i = 0; i < names.length; ++i) {
            const n = names[i].trim();
            if (!n) continue;
            const lower = n.toLowerCase();
            if (lower === "forwardbutton") {
                mask |= Qt.ForwardButton | Qt.ExtraButton3;   // 0x10 and 0x20: KWin sends MB5 as ExtraButton3
            } else if (lower === "backbutton") {
                mask |= Qt.BackButton | Qt.ExtraButton4;      // MB4 is ExtraButton1 (= BackButton), or ExtraButton4 as BTN_BACK
            } else {
                const code = Qt[n];
                if (typeof code !== "number") { console.warn("kwin-canvas: unknown mouse button", n); continue; }
                mask |= code;
            }
        }
        return mask;
    }

    // "RightButton, MiddleButton" -> "right button / middle button", for the legend.
    function holdLabel(spec) {
        const parts = String(spec || "").split(",");
        const out = [];
        for (let i = 0; i < parts.length; ++i) {
            const n = parts[i].trim().replace(/Button$/i, "").trim().toLowerCase();
            if (n) out.push(n + " button");
        }
        return out.join(" / ");
    }

    function rebuildBindings() {
        bindings = {
            apply: keysFor(configuration.KeyApply),
            cancel: keysFor(configuration.KeyCancel),
            home: keysFor(configuration.KeyHome),
            origin: keysFor(configuration.KeyOrigin),
            fit: keysFor(configuration.KeyFit),
            zoomIn: keysFor(configuration.KeyZoomIn),
            zoomOut: keysFor(configuration.KeyZoomOut),
            pan: keysFor(configuration.KeyPan),
            panLeft: keysFor(configuration.KeyPanLeft),
            panRight: keysFor(configuration.KeyPanRight),
            panUp: keysFor(configuration.KeyPanUp),
            panDown: keysFor(configuration.KeyPanDown),
            next: keysFor(configuration.KeyNext),
            prev: keysFor(configuration.KeyPrev),
            clusterNext: keysFor(configuration.ClusterNextKey),
            clusterPrev: keysFor(configuration.ClusterPrevKey),
            switcher: keysFor(chordTail(configuration.SwitcherShortcut)),
            panHold: buttonsFor(configuration.PanHold),
            hold: buttonsFor(configuration.CanvasHold),
            swap: buttonsFor(configuration.SwapButton),
        };
    }

    function bound(action, key) {
        const list = bindings[action];
        if (!list) return false;
        for (let i = 0; i < list.length; ++i) if (list[i] === key) return true;
        return false;
    }

    // Mouse gestures: "Shift+DoubleClick" -> { count: 2, mods: Qt.ShiftModifier }.
    function gestureFor(spec) {
        let count = 0, mods = 0, button = Qt.LeftButton;
        const parts = String(spec || "").split("+");
        for (let i = 0; i < parts.length; ++i) {
            const p = parts[i].trim().toLowerCase();
            if (p === "click") count = 1;
            else if (p === "doubleclick") count = 2;
            else if (p === "rightclick") { count = 1; button = Qt.RightButton; }
            else if (p === "middleclick") { count = 1; button = Qt.MiddleButton; }
            else if (p === "shift") mods |= Qt.ShiftModifier;
            else if (p === "ctrl" || p === "control") mods |= Qt.ControlModifier;
            else if (p === "alt") mods |= Qt.AltModifier;
            else if (p === "meta") mods |= Qt.MetaModifier;
            else if (p) console.warn("kwin-canvas: unknown gesture part", p);
        }
        return { count: count, mods: mods, button: button };
    }

    function gestureMatches(spec, count, modifiers, button) {
        const g = gestureFor(spec);
        if (g.count === 0 || count !== g.count) return false;
        if ((button || Qt.LeftButton) !== g.button) return false;
        const mask = Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier;
        return (modifiers & mask) === g.mods;
    }

    function gestureLabel(spec) {
        return String(spec || "").replace(/DoubleClick/i, "double-click").replace(/RightClick/i, "right-click").replace(/MiddleClick/i, "middle-click").replace(/Click/, "click").toLowerCase();
    }

    // Where the viewport goes when a window gesture applies with that window
    // focused, from the FocusTarget setting. The viewport is the activity's
    // target, so moving it slides the frames, the windows on them and the
    // wallpaper together and writes nothing: each of these is a placement of
    // the desk, not of a window.
    //   smart    the window wholly in view, at the offset that leaves the most
    //            of the rest of the desk in view (smartOffset).
    //   centre   the window's centre to the centre of the active screen,
    //            whatever that pushes off it.
    //   window   the point clicked stays under the pointer, then the least
    //            shift that brings the window wholly back into view.
    //   desktop  a window inside a frame leaves the frame where it is.
    // "center" is accepted for "centre"; anything else is the default, smart.
    function focusMode() {
        const m = String(configuration.FocusTarget || "").trim().toLowerCase();
        if (m === "window" || m === "desktop") return m;
        if (m === "centre" || m === "center") return "centre";
        return "smart";
    }

    // Legend text for the focus gesture: what the viewport does after applying.
    function focusHelp() {
        switch (focusMode()) {
        case "window":  return "apply with that point under the pointer, focused on it; in another activity's frame, go there";
        case "desktop": return "apply, focused on it; in another activity's frame, go there";
        case "centre":  return "apply with it centred on screen, focused on it; in another activity's frame, go there";
        default:        return "apply with it and the rest of the desk in view, focused on it; in another activity's frame, go there";
        }
    }

    // Legend text for an action: the configured names, lower-cased.
    function keyLabel(spec) {
        return String(spec || "").split(",").map(function (n) { return n.trim().toLowerCase(); }).join("/");
    }

    // The primary display: first in the order plasmashell set, else the first screen.
    readonly property var primaryScreen: KWin.Workspace.screenOrder.length > 0 ? KWin.Workspace.screenOrder[0] : KWin.Workspace.screens[0]

    readonly property real zoomMin: configuration.ZoomMin
    readonly property real zoomStep: configuration.ZoomStep
    // ---- hold to navigate ---------------------------------------------------
    // A PanHold button held down puts the canvas in navigation: the button pans
    // on drag from anywhere on the screen, and a pointer parked at a screen
    // edge pans on its own, faster the deeper it is in the band (EdgePan,
    // EdgePanMargin, EdgePanSpeed). The wheel zooms at the cursor throughout.
    // The middle button is a navigate button with nothing to configure: it is
    // one whether or not PanHold lists it, held or dragged.
    readonly property int panHoldButtons: bindings.panHold || 0
    readonly property bool edgePan: configuration.EdgePan !== false
    readonly property int edgePanMargin: Math.max(1, Math.round(Number(configuration.EdgePanMargin) || 1))
    readonly property real edgePanSpeed: Math.max(0, Number(configuration.EdgePanSpeed) || 0)
    // The edge pan's own envelope: the motion gathers over ~120 ms and lets
    // go the same way, instead of snapping on at the band's lip.
    property real edgePanGain: 0
    // Activity colour schemes. The colour-blind safe ones are published sets:
    // Okabe & Ito (2008), Paul Tol's bright set, IBM's Carbon set. mono
    // differs by luminance only.
    readonly property var palettes: ({
        "default":   ["#4fa3ff", "#ff9f43", "#2ecc71", "#e056fd", "#f9ca24", "#ff6b6b", "#48dbfb", "#c8d6e5"],
        "okabe-ito": ["#0072B2", "#E69F00", "#009E73", "#CC79A7", "#56B4E9", "#D55E00", "#F0E442", "#999999"],
        "tol":       ["#4477AA", "#EE6677", "#228833", "#CCBB44", "#66CCEE", "#AA3377", "#BBBBBB"],
        "ibm":       ["#648FFF", "#FE6100", "#785EF0", "#FFB000", "#DC267F"],
        "mono":      ["#f2f2f2", "#b8b8b8", "#8a8a8a", "#5e5e5e", "#3a3a3a"]
    })
    readonly property var palette: palettes[String(configuration.Palette || "").toLowerCase()] || palettes["default"]

    // Text that reads on a swatch of the given colour.
    function textOn(c) {
        const col = Qt.color(c);
        return (0.299 * col.r + 0.587 * col.g + 0.114 * col.b) > 0.6 ? "#1a1a1a" : "#ffffff";
    }

    // ---- window filter -----------------------------------------------------
    // Windows of the current virtual desktop. anyActivity takes every
    // activity's windows (the canvas); otherwise the current activity's (1:1).
    function isCanvasWindow(w, anyActivity) {
        if (!w || w.deleted || !w.managed) return false;
        if (w.desktopWindow || w.dock || w.popupWindow || w.specialWindow) return false;
        if (w.minimized || w.hidden || !onDesktop(w)) return false;
        if (!anyActivity && !onActivity(w, currentActivity)) return false;
        return true;
    }

    // The desktop's own window (the live wallpaper surface) for a screen.
    // Wallpaper Engine and other non-KDE wallpapers exist only as the
    // desktop window's texture, which KWin.DesktopBackground does not draw,
    // so the backdrop asks the compositor for the real window instead.
    function desktopWindowFor(screen) {
        const stack = KWin.Workspace.stackingOrder;
        for (let i = stack.length - 1; i >= 0; --i) {
            const w = stack[i];
            if (!w || w.deleted || !w.desktopWindow) continue;
            if (screen && w.screen && w.screen !== screen) continue;
            return w;
        }
        return null;
    }

    // The bindable handle the scene tree binds to: refreshed whenever the
    // window set changes, so a video wallpaper's desktop window is picked
    // up the moment it arrives. A bare function call in the ui.qml cannot
    // bind, which is the QQmlExpression warning and the stale-null gray.
    property QtObject desktopWindow: null
    // One per output, by the output's name: the scene's layer binds to this
    // (reassigned whole, so the binding re-evaluates) and not to a call.
    property var desktopWindows: ({})
    function refreshDesktopWindow() {
        desktopWindow = desktopWindowFor(null);
        const m = {};
        const screens = KWin.Workspace.screens;
        for (let i = 0; i < screens.length; ++i) {
            const w = desktopWindowFor(screens[i]);
            if (w) m[screens[i].name] = w;
        }
        desktopWindows = m;
    }

    // A window the fly covers: every window the user can click, wider than
    // what the canvas draws - a utility window flies too. KWin's own
    // keep-visible rule must never be the thing that moves a window the
    // user clicked. Panels, docks, popups and the special overlays (an
    // applet's dropdown, a notification) never fly: clicking them must not
    // drag the desktop.
    function isFlyableWindow(w) {
        if (!w || w.deleted || !w.managed) return false;
        if (w.desktopWindow || w.dock || w.popupWindow || w.specialWindow || w.minimized || w.hidden) return false;
        return onDesktop(w);
    }

    function onDesktop(w) {
        if (w.onAllDesktops) return true;
        const cur = KWin.Workspace.currentDesktop;
        const ds = w.desktops;
        for (let i = 0; i < ds.length; ++i) if (ds[i] === cur) return true;
        return false;
    }

    // An application's popup (menu, combo list, tooltip) on this activity
    // and desktop, whose chain of parents ends at a window the canvas shows
    // here. Wayland popups carry popupWindow and transientFor and no type
    // flag; X11 override-redirect menus carry their type and may have no
    // parent.
    function isAppPopup(w) {
        if (!w || w.deleted || !w.popupWindow || w.minimized || w.hidden) return false;
        if (!onDesktop(w) || !onActivity(w, currentActivity)) return false;
        let p = w.transientFor;
        while (p && p.popupWindow) p = p.transientFor;
        return !p || isCanvasWindow(p, false);
    }

    // ---- activities and targets --------------------------------------------
    // KWin hands out activity ids only. With activities disabled the list is
    // empty and the current id is "", so one unnamed activity stands in.
    // The list is read explicitly: KWin announces single additions and
    // removals, and the bulk load from the activity manager after startup
    // arrives with no signal at all.
    property var activityIds: [""]
    readonly property string currentActivity: KWin.Workspace.currentActivity || ""
    function refreshActivities() {
        const a = KWin.Workspace.activities;
        const list = a && a.length > 0 ? Array.prototype.slice.call(a) : [""];
        if (list.join("\n") === activityIds.join("\n")) return false;
        activityIds = list;
        return true;
    }

    // Names come from the activity manager over D-Bus, one call per id,
    // refreshed on every open and whenever the list changes: bumping
    // namesReq re-instantiates the callers, and each calls once on creation.
    property var activityNames: ({})
    property int namesRev: 0
    property int namesReq: 0
    function refreshNames() { namesReq++; }
    function setActivityName(id, name) {
        if (activityNames[id] === name) return;
        activityNames[id] = name;
        namesRev++;
    }
    function labelOf(id) {
        namesRev;
        const n = activityNames[id];
        if (n) return n;
        return id ? "Activity " + (activityIndex(id) + 1) : "Activity";
    }

    Instantiator {
        model: { effect.namesReq; return effect.activityIds; }
        delegate: KWin.DBusCall {
            required property string modelData
            service: "org.kde.ActivityManager"
            path: "/ActivityManager/Activities"
            dbusInterface: "org.kde.ActivityManager.Activities"
            method: "ActivityName"
            arguments: [modelData]
            onFinished: (ret) => effect.setActivityName(modelData, ret && ret.length ? String(ret[0]) : "")
            Component.onCompleted: call()
        }
    }

    KWin.DBusCall {
        id: addActivityCall
        service: "org.kde.ActivityManager"
        path: "/ActivityManager/Activities"
        dbusInterface: "org.kde.ActivityManager.Activities"
        method: "AddActivity"
        onFinished: (ret) => effect.activityAdded(String(ret[0]))
    }
    KWin.DBusCall {
        id: removeActivityCall
        service: "org.kde.ActivityManager"
        path: "/ActivityManager/Activities"
        dbusInterface: "org.kde.ActivityManager.Activities"
        method: "RemoveActivity"
    }

    function onActivity(w, id) {
        const a = w.activities;
        if (!a || a.length === 0) return true;
        for (let i = 0; i < a.length; ++i) if (a[i] === id) return true;
        return false;
    }

    // The activity a window belongs to: the current one when it is there or
    // on every activity, else its first.
    function activityOf(w) {
        const a = w.activities;
        if (!a || a.length === 0 || onActivity(w, currentActivity)) return currentActivity;
        return a[0];
    }

    function targetOf(id) {
        let t = targets[id];
        if (!t) {
            t = { x: viewX, y: viewY };
            targets[id] = t;
        }
        return t;
    }

    // Read-only lookup for bindings, so drawing a frame never fixes a
    // target before ensureTargets() has laid the activity out.
    function peekTarget(id) {
        const t = targets[id];
        return t ? t : { x: viewX, y: viewY };
    }

    function activityIndex(id) {
        const ids = activityIds;
        for (let i = 0; i < ids.length; ++i) if (ids[i] === id) return i;
        return 0;
    }

    // ---- hidden frames -----------------------------------------------------
    // An activity used on one monitor need not carry frames for the others.
    // Keys are "activityId|outputName"; the set lives in HiddenFrames.
    property var hiddenFrames: ({})
    property int hiddenRev: 0
    function frameKey(id, screen) { return id + "|" + screen.name; }
    function isHidden(id, screen) { hiddenRev; return hiddenFrames[frameKey(id, screen)] === true; }
    function setHidden(id, screen, on) {
        const k = frameKey(id, screen);
        if (on) hiddenFrames[k] = true; else delete hiddenFrames[k];
        hiddenRev++;
        const list = [];
        for (const key in hiddenFrames) list.push(key);
        configuration.HiddenFrames = list;
        configuration.writeConfig();
        revision++;
    }
    function loadHiddenFrames() {
        const list = configuration.HiddenFrames || [];
        const set = {};
        for (let i = 0; i < list.length; ++i) if (list[i]) set[list[i]] = true;
        hiddenFrames = set;
        hiddenRev++;
    }
    // Every frame drawn: { id, screen, x, y, width, height } in canvas units.
    function frames() {
        const out = [];
        const ids = activityIds, screens = KWin.Workspace.screens;
        for (let i = 0; i < ids.length; ++i) {
            const t = peekTarget(ids[i]);
            for (let j = 0; j < screens.length; ++j) {
                if (isHidden(ids[i], screens[j])) continue;
                const g = screens[j].geometry;
                out.push({ id: ids[i], screen: screens[j], x: t.x + g.x, y: t.y + g.y, width: g.width, height: g.height });
            }
        }
        return out;
    }

    // The plane's bounds: the frames and the windows together, for the
    // minimap's fit. A sane screen-sized fallback when nothing is placed.
    function worldBounds() {
        let l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
        const fs = frames();
        for (let i = 0; i < fs.length; ++i) {
            l = Math.min(l, fs[i].x); t = Math.min(t, fs[i].y);
            r = Math.max(r, fs[i].x + fs[i].width); b = Math.max(b, fs[i].y + fs[i].height);
        }
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            l = Math.min(l, e.x); t = Math.min(t, e.y);
            r = Math.max(r, e.x + e.width); b = Math.max(b, e.y + e.height);
        }
        if (l === Infinity) { const g = actionScreen().geometry; return { x: 0, y: 0, width: g.width, height: g.height }; }
        return { x: l, y: t, width: Math.max(1, r - l), height: Math.max(1, b - t) };
    }

    // The current activity's target is the camera. Activities never placed get
    // laid out in a row beside it, which moves nothing: their windows' canvas
    // positions are derived from the target.
    function ensureTargets() {
        const ids = activityIds;
        const cur = currentActivity;
        const ci = activityIndex(cur);
        const base = targetOf(cur);
        const vs = KWin.Workspace.virtualScreenGeometry;
        const step = vs.width + configuration.ActivityGap;
        // Rightmost placed target, so later additions never overlap.
        let right = -Infinity;
        for (let i = 0; i < ids.length; ++i) {
            const t = targets[ids[i]];
            if (t) right = Math.max(right, t.x);
        }
        for (let i = 0; i < ids.length; ++i) {
            if (targets[ids[i]]) continue;
            const x = right === -Infinity ? base.x + (i - ci) * step : right + step;
            targets[ids[i]] = { x: x, y: base.y };
            right = Math.max(right, x);
        }
    }

    // An activity was added or removed. KWin re-homes the windows of a removed
    // activity; their geometry is unchanged, so they sit at the same screen
    // spot in their new activity's viewport.
    function activitiesChanged() {
        refreshActivities();
        ensureTargets();
        refreshNames();
        if (!visible) return;
        const ids = activityIds;
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (e.window.deleted) continue;
            const alive = ids.indexOf(e.activity) !== -1;
            const a = activityOf(e.window);
            if (alive && a === e.activity) continue;
            const t = targetOf(a);
            e.activity = a;
            e.x = e.frameX + t.x;
            e.y = e.frameY + t.y;
        }
        revision++;
    }

    // addActivity: a new activity named after its count; the manager answers
    // with the id, and the Workspace list follows. newActivityAt() parks the
    // window it should be centred on until then.
    property var pendingNewAt: null
    function addActivity() {
        addActivityCall.arguments = ["Activity " + (activityIds.length + 1)];
        addActivityCall.call();
    }

    function activityAdded(id) {
        if (!id) return;
        const entry = pendingNewAt;
        pendingNewAt = null;
        if (!entry) return;
        const g = actionScreen().geometry;
        targets[id] = { x: entry.x + entry.width / 2 - (g.x + g.width / 2),
                        y: entry.y + entry.height / 2 - (g.y + g.height / 2) };
        const t = targets[id];
        // The new activity's frame is centred on the window: fly there, then
        // move the window, make the activity current and apply, focused.
        flyEnter(id, t.x, t.y, function () {
            if (!entry.window.deleted) entry.window.activities = [id];
            entry.activity = id;
            revision++;
            // Activating a window on another activity does not switch to it.
            KWin.Workspace.currentActivity = id;
            commit(entry.window);
        });
    }

    function removeActivity(id) {
        if (activityIds.length <= 1 || !id) return;
        removeActivityCall.arguments = [id];
        removeActivityCall.call();
    }

    function copyTargets(src) {
        const out = {};
        for (const k in src) out[k] = { x: src[k].x, y: src[k].y };
        return out;
    }

    // The activity whose frames overlap a canvas rect the most, or null if none
    // touches it. A window straddling two frames goes to the larger share.
    function activityAt(rect) {
        const fs = frames();
        let best = null, bestArea = 0;
        for (let i = 0; i < fs.length; ++i) {
            const f = fs[i];
            const w = Math.min(rect.x + rect.width, f.x + f.width) - Math.max(rect.x, f.x);
            const h = Math.min(rect.y + rect.height, f.y + f.height) - Math.max(rect.y, f.y);
            if (w <= 0 || h <= 0) continue;
            if (w * h > bestArea) { bestArea = w * h; best = f.id; }
        }
        return best;
    }

    property var targetRaw: null
    // Drag an activity's frame group. With FramesCarryWindows the activity's
    // windows ride along, so the group moves on the plane as one and nothing
    // changes on screen at 1:1; off, the frames move over the windows.
    function dragTarget(id, dx, dy) {
        const t = targetOf(id);
        if (!targetRaw || targetRaw.id !== id) targetRaw = { id: id, x: t.x, y: t.y };
        targetRaw.x += dx / zoom; targetRaw.y += dy / zoom;
        const carry = configuration.FramesCarryWindows !== false;
        let riding = null;
        if (carry) {
            riding = {};
            for (let i = 0; i < entries.length; ++i) if (entries[i].activity === id) riding[entries[i].window.internalId] = true;
        }
        const vs = KWin.Workspace.virtualScreenGeometry;
        const box = { x: targetRaw.x + vs.x, y: targetRaw.y + vs.y, width: vs.width, height: vs.height };
        const s = snapDelta(box, snapCandidates(riding, id));
        const nx = targetRaw.x + s.dx, ny = targetRaw.y + s.dy;
        if (carry) {
            const ddx = nx - t.x, ddy = ny - t.y;
            for (let i = 0; i < entries.length; ++i) {
                const e = entries[i];
                if (e.activity !== id) continue;
                e.x += ddx;
                e.y += ddy;
            }
        }
        t.x = nx;
        t.y = ny;
        revision++;
    }

    function makeEntry(w) {
        const a = activityOf(w);
        const t = targetOf(a);
        const g = w.frameGeometry;
        return { window: w, activity: a, x: g.x + t.x, y: g.y + t.y, width: g.width, height: g.height,
                 frameX: g.x, frameY: g.y, anchorRight: false, anchorBottom: false, askW: 0, askH: 0 };
    }

    function snapshot() {
        const list = [];
        const stack = KWin.Workspace.stackingOrder;
        for (let i = 0; i < stack.length; ++i) {
            const w = stack[i];
            if (!isCanvasWindow(w, true)) continue;
            list.push(makeEntry(w));
        }
        entries = list;
        revision++;
    }

    // Follow the live state while the canvas is open: windows that appear,
    // close, restack, or change geometry on their own. Existing entries keep
    // their canvas position and absorb frame changes as deltas.
    function resync() {
        if (!visible) return;
        const byId = {};
        for (let i = 0; i < entries.length; ++i) byId[entries[i].window.internalId] = entries[i];
        const list = [];
        let changed = false;
        const stack = KWin.Workspace.stackingOrder;
        for (let i = 0; i < stack.length; ++i) {
            const w = stack[i];
            if (!isCanvasWindow(w, true)) continue;
            let e = byId[w.internalId];
            if (!e) { e = makeEntry(w); e.born = Date.now(); changed = true; }
            else if (syncEntry(e)) changed = true;
            list.push(e);
        }
        if (list.length !== entries.length) changed = true;
        else for (let i = 0; i < list.length; ++i) if (list[i] !== entries[i]) changed = true;
        if (changed) {
            entries = list;
            revision++;
        }
        refreshAppPopups();
    }

    // The app popups drawn in the overworld, bottom to top. Only while the
    // plane transform is live: KWin then places a popup relative to its
    // parent's real geometry, which settle() keeps at the parent's plane
    // position, so the popup's own real geometry is where to draw it and
    // where KWin routes the pointer to it. They are not entries: nothing
    // settles, snaps, arranges or commits them.
    property var appPopups: []
    function refreshAppPopups() {
        const list = [];
        if (planeLive) {
            const stack = KWin.Workspace.stackingOrder;
            for (let i = 0; i < stack.length; ++i) if (isAppPopup(stack[i])) list.push(stack[i]);
        }
        let same = list.length === appPopups.length;
        for (let i = 0; same && i < list.length; ++i) same = list[i] === appPopups[i];
        if (!same) appPopups = list;
    }
    onPlaneLiveChanged: refreshAppPopups()

    Timer {
        interval: 1000
        repeat: true
        running: effect.visible
        onTriggered: effect.resync()
    }

    // Views with a pointer gesture in hand: a pan, a window drag, a resize, a
    // frame drag. The canvas never hides while one is live - a close would
    // end the interception mid-press and hand the still-held button to the
    // desktop, where its motion is a native drag on whatever is under the
    // pointer. A close asked for mid-gesture is parked in deferredClose and
    // runs the moment the buttons come up.
    property int sceneGestures: 0
    property var deferredClose: null
    property real deferredAt: 0 // when the parked close was asked for; a stuck gesture loses after 5s
    onSceneGesturesChanged: {
        if (sceneGestures === 0 && deferredClose !== null) {
            const fn = deferredClose;
            deferredClose = null;
            fn();
        }
    }

    // The pointer's buttons, as the plugin publishes them: a focus fly must
    // wait until the hand lets go, or the opening canvas would grab the
    // gesture mid-click. The window under a completed click, also from the
    // plugin: a click on an already-active window raises no activation, so
    // the fly has to learn about the click this way too.
    property int pointerButtons: 0
    // The pass-through's resting hand: "internalId|delay" while the hover
    // clock waits its delay out over a window, empty otherwise. The scene
    // fills a cue along that window's edge while it lasts.
    property string restStart: ""
    // The window the pass-through currently hands the pointer to - its
    // internalId while the hover or the grab holds it. The engaged window
    // wears the hand: the cue's line stays full along its top edge.
    property string hoverId: ""
    // The zoom door: with the canvas closed, a wheel over the bare ground
    // zooms the world out of the location. The plugin publishes the step
    // and the effect opens at the seam, so the wheel is the same motion
    // in both places - out to the overworld, back in to the location.
    property int doorStep: 0
    onDoorStepChanged: {
        if (doorStep === 0 || configuration.WheelDoor === false || visible) {
            doorStep = 0;
            return;
        }
        const d = doorStep;
        doorStep = 0;
        if (d > 0) return; // the zoom-in while closed is the desktop's own
        open();
        camZoomTo(zoom / zoomStep, cursorScreen().x, cursorScreen().y);
    }
    // The passthrough has let go: after a while with no input the canvas
    // has the input again, until the pointer's next touch.
    property bool passthroughIdle: false
    // The pointer sits over the system's own chrome - a dock, a panel, a
    // popup, an applet's dropdown. Published by the pass-through on every
    // pointer event (active or not, so the quiet grasp sees it too). While
    // it is set, the scene's input handlers and the hover tick stand back:
    // the chrome gets the click natively, never the canvas and never the
    // window drawn under it.
    property bool chromeHover: false
    // How far the camera has left the location it opened from: 0 at the
    // seam, growing with the zoom-out and the pan. The skin - the frames,
    // the tags, the threads, the glow - fades in with it, so the keyhole
    // and the overworld are one space wearing one skin, and a transient
    // slide stays the seamless desktop it must be. The chord's overworld
    // measures from where it opened (entryView); the grasp's keyhole from
    // where the hold began (the activity's target). Both wear the same
    // curve, so one skin reveals on every path.
    readonly property real skinReveal: {
        effect.zoom; effect.viewX; effect.viewY; effect.revision;
        effect.quiet; effect.grasp; effect.currentActivity;
        effect.entryViewX; effect.entryViewY; effect.zoomRising; effect.camRate;
        effect.skinFromZoom;
        // The skin reveals fast (full by zoom 0.75, so a step out finds its
        // chrome almost at once) and retires across the whole way back: a
        // flight that started at skinFromZoom fades the skin evenly with its
        // own progress (full at the start, gone at the 1:1 arrival, no step
        // at either end), a casual wheel-in wears the straight 2 * (1 -
        // zoom) so consecutive wheel steps never saw-tooth the skin, and a
        // step in sees the threads leave across the whole flight instead of
        // blinking out in the spring's last few frames.
        const riseCurve = effect.camRate > 1
            ? (effect.skinFromZoom < 0.999
                ? (1 - effect.zoom) / (1 - effect.skinFromZoom)
                : (1 - effect.zoom) * 4)
            : (1 - effect.zoom) * 2;
        const zoomPart = Math.min(1, Math.max(0, effect.zoomRising ? riseCurve : (1 - effect.zoom) * 4));
        // A transient slide wears nothing: its windows must stay the
        // desktop's pixel for pixel while they glide.
        if (effect.quiet && !effect.grasp) return zoomPart;
        const ref = effect.quiet ? effect.targetOf(effect.currentActivity)
                                 : { x: effect.entryViewX, y: effect.entryViewY };
        const g = effect.actionScreen().geometry;
        const away = Math.hypot(effect.viewX - ref.x, effect.viewY - ref.y);
        return Math.min(1, Math.max(zoomPart, away / (Math.max(g.width, g.height) * 1.2)));
    }
    property var pendingFly: null
    // Set when the switcher opened from the chord (Meta+Tab / Alt+Tab), not
    // the debug verb, so the chord's release is the enter only for real holds.
    property bool switcherFromChord: false
    // The keyboard-focus request from the switcher to the view (an effect
    // function cannot name the view delegate's id - it bumps this instead).
    property int switcherFocusReq: 0
    // The cluster switcher: the alternate chord steps only among the
    // windows of the cluster the eye is on and fits that cluster, where
    // the primary chord sweeps the whole plane. Set by the chord that
    // opened the switcher, cleared when it closes.
    property bool switcherCluster: false
    // The switcher's z-rise: the windows come up in z the moment the
    // switcher opens, on this ramp, instead of waiting for the zoom-out
    // to reveal the depth - the switch-in reads as the pile rising to
    // meet the eye while the camera flies out.
    property real switcherRise: 0
    NumberAnimation {
        id: switcherRiseAnim
        target: effect
        property: "switcherRise"
        to: 1
        duration: 180
        easing.type: Easing.OutCubic
    }
    function endSwitcher() {
        switcherActive = false;
        switcherCluster = false;
        switcherRise = 0;
        switcherRiseAnim.stop();
        switcherSettle.stop();
    }
    // The beat the enter waits after the chord's release: the pick settles
    // under the eye for this long, then the canvas steps in by itself. A
    // re-tap of the chord during the beat steps on, and Esc steps out.
    // The settle arms on every chord event and the modifier poll keeps it
    // at bay while the chord is held, so the enter cannot be missed:
    // whatever link of the release chain works - the scene's key-up, the
    // seat's modifier poll, or nothing at all - the beat still fires and
    // the switcher steps in.
    Timer {
        id: switcherSettle
        interval: Math.max(100, Number(configuration.SwitcherSettleMs) || 450)
        repeat: false
        onTriggered: {
            if (effect.switcherActive) effect.applyKey();
        }
    }
    // The last time the switcher cycled. The chord refires on every key
    // repeat of a held Tab, and a deliberate re-tap is the only cycle
    // worth taking: the gate passes real re-taps and swallows auto-repeat
    // (and any double delivery of one press), so a hold never machine-guns.
    property real lastSwitchAt: 0
    // One cycle of the switcher, gated: whatever path the press took (the
    // chord's re-fire or the scene's key), at most one cycle lands per
    // 150 ms window.
    function switcherCycle(dir) {
        const now = Date.now();
        if (now - lastSwitchAt < 150) return;
        lastSwitchAt = now;
        cycleSelection(dir);
        // Every step re-arms the enter's beat: the settle fires a moment
        // after the last chord activity, whatever that activity was. The
        // plain Tab cycle (no chord) keeps the manual Enter instead.
        if (effect.switcherFromChord) switcherSettle.restart();
    }
    // The modifier mask the open chord held, and the release detection.
    // The scene cannot always see the release of a key the global
    // shortcut consumed - KWin feeds the chord's own key-ups back on
    // some setups and swallows them on others - so the effect asks the
    // pass-through plugin for the seat's live modifier mask instead:
    // while a chord-held switcher is up, a small poll watches the mask,
    // and the chord's end is the moment its modifier clears. The
    // scene's own key-up remains the fast path.
    property int switcherModMask: 0
    function modMaskOf(spec) {
        let m = 0;
        const parts = String(spec || "").split("+");
        for (let i = 0; i < parts.length; ++i) {
            const t = parts[i].trim().toLowerCase();
            if (t === "meta" || t === "super" || t === "win") m |= Qt.MetaModifier;
            else if (t === "alt") m |= Qt.AltModifier;
            else if (t === "ctrl" || t === "control") m |= Qt.ControlModifier;
            else if (t === "shift") m |= Qt.ShiftModifier;
        }
        return m;
    }
    // The release itself: a release with nothing picked lands on the
    // next window - the tabbox's plain Alt+Tab - and the settle beat
    // begins (the enter fires from the settle, not the release).
    function chordRelease() {
        if (!switcherActive) return;
        let picked = false;
        for (let i = 0; i < entries.length; ++i) {
            if (isSelected(entries[i])) { picked = true; break; }
        }
        if (!picked) switcherCycle(1);
        switcherSettle.restart();
    }
    Timer {
        interval: 80
        repeat: true
        running: effect.switcherActive && effect.switcherFromChord && effect.switcherModMask !== 0
        onTriggered: {
            if (effect.passthroughLive) modifiersCall.call();
        }
    }
    KWin.DBusCall {
        id: modifiersCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "modifiers"
        onFinished: (result) => {
            if (!effect.switcherActive || !effect.switcherFromChord || effect.switcherModMask === 0) return;
            const m = Number(result);
            if (isNaN(m)) {
                // The channel is gone (an older plugin without modifiers):
                // treat it as the release - the settle's beat is the only
                // path left, and it must never leave the switcher stuck.
                effect.chordRelease();
                return;
            }
            if ((m & effect.switcherModMask) === 0) effect.chordRelease();
            else switcherSettle.restart();
        }
    }
    // The switcher: the whole plane fitted to the screen. The chord opens
    // the canvas fitted to the world; Tab and Shift+Tab step the selection
    // - the camera and the map's highlight follow - Enter enters the chosen
    // window, Esc or the chord again steps back out.
    property bool switcherActive: false
    function switcherToggle() {
        if (switcherActive) {
            // A repeat of the chord while the switcher is up steps the
            // selection, the way Alt+Tab cycles while the key is held -
            // through the gate, so a held key's repeats are ignored and
            // only a deliberate re-tap moves it.
            switcherCycle(1);
            return;
        }
        if (effect.canvasHold) return;
        // The world is the map: the switcher opens the canvas fitted to
        // the whole plane, from the closed location or the open overworld
        // alike - the chord is the switcher wherever it fires, and only a
        // hold in progress stands it down. The selection cycle still rides
        // Tab and Enter to step in. The fit rides a brisk flight and the
        // windows rise in z at the same time, so the switch-in is a snap,
        // not a wait.
        if (!visible) open();
        switcherActive = true;
        switcherRiseAnim.restart();
        if (switcherCluster) {
            // The cluster switcher fits the cluster the eye is on, not the
            // whole plane: the pick is a short hop among neighbours. A
            // cluster of one (or none) has nothing to scope to - the world
            // fit stands in.
            const ci = clusterIndex();
            const r = ci >= 0 ? clusterRect(ci) : null;
            if (r && (r.width > 0 || r.height > 0)) {
                const sg = actionScreen().geometry;
                const z = Math.min(1.0, Math.max(0.2, Math.min(sg.width / (r.width + 48), sg.height / (r.height + 48))));
                camGo(z, r.x + r.width / 2 - (sg.x + sg.width / 2) / z, r.y + r.height / 2 - (sg.y + sg.height / 2) / z, undefined, undefined, 3.0);
            } else {
                zoomExtents(true, 3.0);
            }
        } else {
            zoomExtents(true, 3.0);
        }
        // The overworld's chrome can take the scene's keyboard focus (the
        // menus' focus scopes) - the switcher needs the keys, so the view
        // takes the focus back once the fit is on screen.
        switcherFocusReq++;
        clickPanEntry = null;
        clickPanTimer.stop();
        // The chord's own beat: the settle arms here, every step re-arms
        // it, and the modifier poll keeps it at bay while the chord is
        // held - so the enter always comes, whatever link of the release
        // chain survives. The debug channel's switch (no chord held)
        // keeps the manual Enter instead, so the scenarios drive it
        // deterministically.
        if (switcherFromChord) switcherSettle.restart();
    }
    property var clickedWindow: null
    onPointerButtonsChanged: {
        if (pointerButtons === 0) {
            // One event-loop turn later: the release finishes its delivery to
            // the window under the pointer first, and the click publication
            // from the plugin lands, so the fly never opens the canvas over a
            // still-completing press.
            Qt.callLater(function () {
                const w = pendingFly !== null ? pendingFly : clickedWindow;
                pendingFly = null;
                clickedWindow = null;
                if (!w || w.deleted || !isFlyableWindow(w)) return;
                const g = w.frameGeometry;
                const vs = KWin.Workspace.virtualScreenGeometry;
                if (g.x >= vs.x && g.y >= vs.y && g.x + g.width <= vs.x + vs.width && g.y + g.height <= vs.y + vs.height) return;
                flyToWindow(w);
            });
        }
    }

    // ---- camera ops --------------------------------------------------------
    function globalToCanvas(gx, gy) { const c = Logic.canvasOf(gx, gy, viewX, viewY, zoom); return Qt.point(c.x, c.y); }

    function clampZoom(z) {
        if (!Number.isFinite(Number(z))) return zoom;
        return Math.max(zoomMin, Math.min(1.0, Number(z)));
    }

    // Zoom while holding the canvas point under `anchor` (global px) fixed on screen.
    function setZoom(z, anchor) {
        z = clampZoom(z);
        const c = Logic.canvasOf(anchor.x, anchor.y, viewX, viewY, zoom);
        const v = Logic.zoomView(c, anchor.x, anchor.y, z);
        zoom = z;
        viewX = v.x;
        viewY = v.y;
    }

    // The pan is the torch: the camera sits at the centre of a sphere and
    // the plane is its inside surface. Dragging turns the torch by a fixed
    // angle per pointer pixel, so the same hand movement sweeps more plane
    // the further from home the view sits - the plane displacement is
    // R * tan(theta): 1:1 near the home, accelerating toward the edges.
    // The sphere's radius grows with the windows' spread (the furthest
    // window must stay inside the torch's reach) plus a margin, so the
    // plane can keep growing before the sphere follows it.
    function panBy(dx, dy) {
        effect.dbg("pan", "panBy dx=" + dx + " dy=" + dy);
        // The hand moves the plane exactly, at every zoom: the eye and the
        // hand agree everywhere. (The arc - the camera riding a sphere the
        // tan accelerated - left with the sphere.)
        viewX -= dx / zoom;
        viewY -= dy / zoom;
    }

    // ---- camera physics ------------------------------------------------------
    // The camera moves under physics, not a timeline, so it can always be taken
    // over mid-flight and never arrives with a jolt. Two motions, one 16 ms
    // step: a pan the hand lets go of is a glide that friction takes away, and
    // anything with a destination (a wheel notch, a fit, an edge opening the
    // canvas) is a spring. Critically damped - the damping is twice the square
    // root of the rate - so it arrives as fast as it can without overshooting,
    // which is what a camera wants, and the same easing family KWin's own
    // Overview uses; the difference is that a drag or a new destination can
    // interrupt this one mid-flight. Units are canvas pixels per second.
    property real camVX: 0
    property real camVY: 0
    property real camVZoom: 0
    property bool camHasGoal: false
    property real camGoalX: 0
    property real camGoalY: 0
    property real camGoalZoom: 1.0
    // The tour's trace: the flight's start and how much of its path is
    // left, so the plane can draw the way the camera came until the
    // arrival erases it.
    property real camFromX: 0
    property real camFromY: 0
    property real camFromZoom: 1.0
    property real camTraceFade: 0
    // A zoom can pin a point: the canvas point under a screen point when the
    // zoom starts is under it at every step, as a pinch and a wheel at the
    // cursor both do. The anchor owns the position while it is live and only
    // the scale springs.
    property bool camAnchored: false
    property real camAnchorX: 0
    property real camAnchorY: 0
    property real camAnchorGX: 0
    property real camAnchorGY: 0
    // Run once when the spring arrives: the step-in and the cancel flight
    // leave their landing here (flyEnter, cancel). Any camera takeover -
    // a drag, a wheel, a new goal - runs camStop(), which clears it, so a
    // flight interrupted mid-way is simply over and the canvas stays open.
    property var camOnArrive: null
    readonly property bool panInertia: configuration.PanInertia !== false
    readonly property bool smoothZoom: configuration.SmoothZoom !== false
    readonly property real panFriction: Math.max(0.1, Number(configuration.PanFriction) || 3)
    readonly property real camSpring: Math.max(1, Number(configuration.CamSpring) || 14)
    // A glide is over below this many screen pixels a second: below it the eye
    // cannot see the difference, and stopping is what ends the timer.
    readonly property real camRest: 8

    function camLive() {
        return camHasGoal || Math.abs(camVX) > 0.001 || Math.abs(camVY) > 0.001 || Math.abs(camVZoom) > 0.0001;
    }

    function camStop() {
        camHasGoal = false;
        camAnchored = false;
        camVX = 0; camVY = 0; camVZoom = 0;
        camOnArrive = null;
        camRate = 1.0;
        lastZoom = zoom;
        zoomRising = false;
        camTraceFade = 0;
    }

    // A pan the hand let go of: keep the plane moving the way it was, under
    // friction. dx, dy are the screen pixels the drag covered and ms how long
    // it took, so this is the hand's average velocity - negated, because the
    // pan moved the view the other way (content follows the pointer) - and a
    // flick carries while a slow drag settles at once. The caller has already
    // refused a drag that paused before the release (see the pan handler),
    // which is what lets "drag it where you want it and let go" land exactly
    // where it was put.
    // How long the current flick has been coasting: the decay eases in over
    // the first ~120 ms, so a throw keeps its own beat before the friction
    // takes over.
    property real flingAge: 0
    function camFling(dx, dy, ms) {
        camStop();
        if (!panInertia || ms <= 0) return;
        let vx = -dx / (ms / 1000) / zoom;
        let vy = -dy / (ms / 1000) / zoom;
        const speed = Math.sqrt(vx * vx + vy * vy);
        if (speed * zoom < 140) return;          // a careful drag releases to a still canvas
        const maxSpeed = 5200 / zoom;            // a screen and a half a second, at most
        if (speed > maxSpeed) { vx *= maxSpeed / speed; vy *= maxSpeed / speed; }
        camVX = vx;
        camVY = vy;
        flingAge = 0;
    }

    // Spring the camera to a scale, and - unless a screen point is given to pin
    // - to a place. Instant when SmoothZoom is off, so a script or a still hand
    // gets exactly what it asked for.
    // The rate the current spring runs at: a multiple of camSpring. The
    // flights (the step in, the double-click's placement, the cancel) run
    // at twice the casual rate, so an enter snaps while a pan glides.
    property real camRate: 1.0
    // Which way the camera's zoom is travelling, for the skin's asymmetric
    // curve, and the zoom a rising flight left from, for its even fade.
    // Set when a flight begins, tracked every camStep tick, reset when the
    // spring stops.
    property bool zoomRising: false
    property real lastZoom: 1
    property real skinFromZoom: 1
    function camGo(z, goalX, goalY, gx, gy, rate) {
        dbg("camGo", "z=" + z + " goal=(" + Math.round(goalX) + "," + Math.round(goalY) + ")");
        z = clampZoom(z);
        const pinned = gx !== undefined && gx !== null;
        camStop();
        // The spring's rate follows the jump: a small correction glides at
        // the casual pace, a far flight (the home, the activity step) runs
        // a stiffer spring so it settles as promptly - the snappy big
        // moves never feel like waiting.
        if (rate === undefined) {
            const jump = Math.hypot(goalX - viewX, goalY - viewY) / Math.max(0.25, zoom) + Math.abs(z - zoom) * 4000;
            camRate = Math.max(1.0, Math.min(2.4, 0.9 + jump / 5000));
        } else {
            camRate = Math.max(0.25, Number(rate));
        }
        if (!smoothZoom) {
            if (pinned) setZoom(z, Qt.point(gx, gy));
            else { zoom = z; viewX = goalX; viewY = goalY; }
            lastZoom = zoom;
            zoomRising = false;
            return;
        }
        const w = camSpring * camRate;
        camGoalZoom = z;
        // The tour draws its path: the flight's start is remembered so the
        // trace can draw from where the camera came to where it is now.
        camFromX = viewX;
        camFromY = viewY;
        camFromZoom = zoom;
        camTraceFade = 1;
        // The skin's retire measures against this flight's own start, so a
        // step in from any zoom fades the chrome evenly with the flight.
        zoomRising = z > zoom;
        if (zoomRising) skinFromZoom = zoom;
        lastZoom = zoom;
        if (pinned) {
            const c = globalToCanvas(gx, gy);
            camAnchorX = c.x; camAnchorY = c.y; camAnchorGX = gx; camAnchorGY = gy;
            camAnchored = true;
            camGoalX = viewX; camGoalY = viewY;
        } else {
            camAnchored = false;
            camGoalX = goalX; camGoalY = goalY;
            // No kick. A critically damped spring let go from rest starts
            // with the full acceleration and zero velocity: the first step
            // is imperceptible and the flight builds into one unbroken
            // glide. A push toward the goal here would snap the first
            // frame - a jump the eye reads as a cut, not a flight.
        }
        camHasGoal = true;
    }

    // A zoom about a screen point: the wheel at the cursor, a pinch, an edge
    // stepping the canvas out around its own screen.
    function camZoomTo(z, gx, gy) { camGo(z, viewX, viewY, gx, gy); }

    // One step, dt in seconds. A Timer and not a FrameAnimation: a
    // FrameAnimation advances with the frames the compositor draws for the
    // effect, so the first step of a gesture would wait for damage the gesture
    // has not caused yet - the wheel sets a goal, nothing on screen has moved,
    // no frame is drawn, and the spring never starts. A timer steps from the
    // event loop; the step it takes is what damages the scene, and the motion
    // then keeps its own frames coming. 16 ms is a frame at 60 Hz, and the dt
    // is deliberately the interval and not what the event loop actually took,
    // so a busy loop slows the camera rather than lengthening its steps - an
    // explicit Euler spring is only stable for a fraction of its period.
    function camStep(dt) {
        if (!camLive() || dt <= 0) return;
        // (The Euler spring is only stable while w*dt stays well under 1:
        // above ~32/s a fly with the knobs high diverges - a state read
        // once caught the view at 2.7e253 - so cap at the stability edge.)
        const w = Math.min(32, camSpring * camRate), k = w * w, c = 2 * w;
        if (camHasGoal) {
            camVZoom += (-k * (zoom - camGoalZoom) - c * camVZoom) * dt;
            if (!camAnchored) {
                camVX += (-k * (viewX - camGoalX) - c * camVX) * dt;
                camVY += (-k * (viewY - camGoalY) - c * camVY) * dt;
            }
            // The flight's trace fades as the camera eats the distance: the
            // plane remembers where the eye came from until the arrival.
            const tdist = Math.hypot(camGoalX - camFromX, camGoalY - camFromY);
            const walked = Math.min(1, Math.hypot(viewX - camFromX, viewY - camFromY) / Math.max(1, tdist));
            camTraceFade = 1 - walked;
        } else {
            // The flick's own beat first: the friction eases in over the
            // opening ~120 ms - a throw keeps its speed for a breath and
            // then decays - and gathers again near camRest so the stop
            // eases out instead of cutting.
            flingAge += dt;
            const eased = panFriction * (0.55 + 0.45 * Math.min(1, flingAge / 0.12));
            const near = Math.max(0, Math.min(1, Math.hypot(camVX, camVY) * zoom / (2 * camRest)));
            const f = Math.exp(-(eased / Math.max(0.3, near)) * dt);
            camVX *= f; camVY *= f; camVZoom *= f;
        }
        const z = clampZoom(zoom + camVZoom * dt);
        if (z !== zoom) zoom = z;
        // The skin's curve is asymmetric: a zooming-out camera reveals fast,
        // a zooming-in one retires slowly, so the chrome never blinks out in
        // a flight's tail. Tracked here, the only place the zoom moves.
        zoomRising = zoom > lastZoom;
        lastZoom = zoom;
        if (camAnchored) {
            viewX = camAnchorX - camAnchorGX / zoom;
            viewY = camAnchorY - camAnchorGY / zoom;
        } else {
            viewX += camVX * dt;
            viewY += camVY * dt;
        }
        const nearZoom = Math.abs(zoom - camGoalZoom) < 0.0004 && Math.abs(camVZoom) < 0.02;
        if (camHasGoal && nearZoom
            && (camAnchored || (Math.abs(viewX - camGoalX) < 0.8 && Math.abs(viewY - camGoalY) < 0.8
                                && Math.abs(camVX) < 3 && Math.abs(camVY) < 3))) {
            zoom = camGoalZoom;
            if (camAnchored) {
                viewX = camAnchorX - camAnchorGX / zoom;
                viewY = camAnchorY - camAnchorGY / zoom;
            } else {
                viewX = camGoalX; viewY = camGoalY;
            }
            const cb = camOnArrive;
            camStop();
            if (cb) cb();
            return;
        }
        if (!camHasGoal && camVZoom === 0
            && Math.abs(camVX) * zoom < camRest && Math.abs(camVY) * zoom < camRest) {
            camStop();
        }
    }

    property real lastTickAt: 0

    // The physics tick's dt: the real time since the last tick, clamped
    // to a frame at 60 Hz. The Euler spring is only stable for a fraction
    // of its period, so a busy loop then slows the motion rather than
    // lengthening its steps - the old fixed dt's property, kept - while
    // a fast display still integrates at real time instead of the
    // timer's own cadence.
    function frameDt() {
        const now = Date.now();
        let dt = (now - lastTickAt) / 1000;
        if (!(dt > 0)) dt = 0;
        lastTickAt = now;
        if (dt > 0.0167) dt = 0.0167;
        return dt;
    }

    Timer {
        // A display's own cadence is all the compositor needs: the old 8 ms
        // ticks repainted twice per frame, and that doubled full-screen load
        // is exactly what starved the video wallpaper's renderer in motion.
        interval: 16
        repeat: true
        running: effect.visible
        onTriggered: {
            const dt = effect.frameDt();
            if (effect.camLive()) effect.camStep(dt);
            // Each of these is a walk over every window: at rest with nothing
            // floating and nothing gliding there is nothing for them to do.
            // The float walk also drops a picture whose window has just been
            // unpinned (floatOf), so it runs while any picture is still held,
            // not only while a window is pinned.
            if (effect.pinnedCount > 0 || effect.floatHeld()) effect.floatPinned(dt);
            for (const id in effect.entryAnims) { effect.stepEntryAnims(); break; }
        }
    }

    // ---- opening and closing fades ------------------------------------------
    // The overworld's chrome (frame borders and tint, tags, toolbar, help)
    // fades while a step in flies and fades back in if the flight is
    // interrupted. The entries, the ground and the wallpaper never fade:
    // what is stepped into is the location, which looks exactly like the
    // canvas at 1:1. Entering is the camera holding an arrival callback -
    // flyEnter and cancel leave one - so any camera takeover clears it and
    // the chrome comes back.
    property real chromeFade: 1
    readonly property bool entering: camOnArrive !== null
    onEnteringChanged: {
        // The chrome stays up through a flight: hiding the frames, the tags
        // and the toolbar at the flight's start and showing them again at its
        // end reads as a blink. The fade is for a close asked while the
        // chrome is up, which farewellHide restarts itself.
        if (!entering && visible) welcomeAnim.restart();
    }
    NumberAnimation {
        id: farewellAnim
        target: effect
        property: "chromeFade"
        to: 0
        duration: 160
        easing.type: Easing.InOutCubic
    }
    NumberAnimation {
        id: welcomeAnim
        target: effect
        property: "chromeFade"
        to: 1
        duration: 160
        easing.type: Easing.InOutCubic
    }

    // A close asked for while the chrome is still up - stepping in from 1:1,
    // a cancel with nothing to fly back from - fades the chrome out first
    // and hides when it is gone. At 1:1 the thumbnails and the real windows
    // agree, so the fade is the only thing the eye can see, and cutting the
    // frames, the tags and the toolbar in one frame is exactly the flash
    // that must not happen. With SmoothZoom off, and once the chrome is
    // already gone (a flight's arrival), the close is taken at once, as a
    // script measures it.
    property bool closing: false
    property var farewellThen: null
    function farewellHide(then) {
        dropPassthrough();
        if (!smoothZoom) {
            then();
            return;
        }
        closing = true;
        farewellThen = then;
        if (chromeFade > 0.02) farewellAnim.restart();
        // The close is instant at 1:1: the scene and the desktop are the same
        // picture there (the thumbnails cover the real windows at the same
        // pixels), so a fade would only run through black - KWin composites
        // the scene over black, not over the desktop. Both callers put the
        // camera at 1:1 before they get here, so there is no jump to mask.
        closeTimer.restart();
    }
    Timer {
        id: closeTimer
        interval: 170
        repeat: false
        onTriggered: {
            const fn = effect.farewellThen;
            effect.farewellThen = null;
            effect.closing = false;
            if (fn) fn();
        }
    }

    // Windows fade in when the opening view moves the camera, so a step out
    // to fit draws its subjects in instead of popping them. 1 for an open at
    // 1:1 and for a quiet slide, where the canvas is the desktop itself.
    property real thumbOpacity: 1
    NumberAnimation {
        id: thumbFadeAnim
        target: effect
        property: "thumbOpacity"
        to: 1
        duration: 200
        easing.type: Easing.OutCubic
    }

    // Look through the current activity's frames. On the smooth camera this
    // springs like any other destination; with SmoothZoom off it lands at
    // once, which is what the scenarios measure.
    function home() {
        const t = targetOf(currentActivity);
        dbg("home", "target (" + Math.round(t.x) + "," + Math.round(t.y) + ")");
        camGo(1, t.x, t.y);
    }

    function origin() {
        camGo(1, 0, 0);
    }

    // Fit every window and every frame into the screen the pointer is on (the
    // active screen's, when there is no pointer), at once for a script and on
    // the spring for the toolbar and the key.
    function zoomExtents(animate, rate) {
        let l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            l = Math.min(l, e.x); t = Math.min(t, e.y);
            r = Math.max(r, e.x + e.width); b = Math.max(b, e.y + e.height);
        }
        const fs = frames();
        for (let i = 0; i < fs.length; ++i) {
            const f = fs[i];
            l = Math.min(l, f.x); t = Math.min(t, f.y);
            r = Math.max(r, f.x + f.width); b = Math.max(b, f.y + f.height);
        }
        if (l === Infinity) { l = 0; t = 0; r = 1; b = 1; }
        const sg = actionScreen().geometry;
        const f = Logic.fitBox(l, t, r, b, sg, 80, zoomMin);
        if (animate) { camGo(f.zoom, f.viewX, f.viewY, undefined, undefined, rate); return; }
        camStop();
        zoom = f.zoom;
        viewX = f.viewX;
        viewY = f.viewY;
    }

    // ---- open / close ------------------------------------------------------
    function open(quietMode, spec) {
        refreshGroundWallpaper();
        if (visible) return;
        camStop();
        graspJumped = false;
        quiet = !!quietMode;
        // Fresh open: the pointer is the hand's until the tick sees the seam.
        seamPark = false;
        entryViewX = viewX;
        entryViewY = viewY;
        zoom = 1.0;
        clearSelection();
        snapEdges = configuration.SnapEdges;
        snapCorners = configuration.SnapCorners;
        snapGrid = configuration.SnapGrid;
        dragRaw = {};
        dragIndex = -1;
        targetRaw = null;
        pendingNewAt = null;
        // The tour's anchor belongs to one visit: a digit jump or a bracket
        // tour sets it, and left alone it made the next visit's tour start
        // from the room the last one ended in, not from where the eye is.
        travelCluster = -1;
        loadHiddenFrames();
        refreshActivities();
        refreshNames();
        targets[currentActivity] = { x: viewX, y: viewY };
        ensureTargets();
        entryTargets = copyTargets(targets);
        snapshot();
        canvasMenus = 0;
        settled = false;
        openFrames = {};
        for (let i = 0; i < entries.length; ++i) openFrames[entries[i].window.internalId] = { x: entries[i].frameX, y: entries[i].frameY };
        visible = true;
        let moved = false;
        if (!quiet) moved = openView(spec);
        // Where the opening view put the camera: a close that finds it still
        // there has not been navigated, and goes back to where it began.
        // With SmoothZoom off the view jumps and leaves no goal: the camera itself is the goal.
        openGoal = !moved ? null : camHasGoal ? { x: camGoalX, y: camGoalY, z: camGoalZoom } : { x: viewX, y: viewY, z: zoom };
        if (!quiet && passthrough) probeCall.call();
        // The fidelity ladder samples the load the moment the overworld
        // opens - no brief spell of full decoration on an already-busy
        // machine while the pulse's first tick is still two seconds away.
        if (!quiet) loadPulse.restart();
        // The step out fades the overworld's chrome in, and - when the opening
        // view moves the camera - the windows in after it: a cut to fit, and a
        // chrome pop at 1:1, would each read as a glitch. A quiet slide has
        // neither: it is the desktop, and the desktop does not fade.
        if (quiet) {
            thumbOpacity = 1;
        } else {
            chromeFade = 0;
            welcomeAnim.restart();
            if (moved) { thumbOpacity = 0; thumbFadeAnim.restart(); }
            else thumbOpacity = 1;
        }
        // The canvas opens instantly, opaque: KWin composites the scene's
        // framebuffer over black, so a fade-in here would flash black, and
        // at 1:1 the scene and the desktop it covers are the same picture
        // (the thumbnails sit over the real windows at the same pixels), so
        // nothing needs bridging. A flight's motion covers its own open; a
        // stale fade-out from a zoomed close is stopped so a quick reopen
        // never catches it mid-fade.
        sceneFadeAnim.stop();
        sceneFade = 1;
        sceneFadeAnim.to = 1;
        dbg("open", (quiet ? "quiet slide" : "overworld") + (moved ? " (camera moved)" : "") + ", spec=" + spec);
    }

    // Where the camera starts: fit everything, stay at 1:1, or a zoom anchored
    // at the centre of the screen being opened. An edge or corner passes its
    // own spec (BorderZoom) instead of OpenZoom: the canvas steps out around
    // the screen the pointer pushed, about that screen's centre. Because the
    // anchor does not move, the point the push left under that centre is the
    // point applying comes back to, so a corner's step out and the chord's
    // "enter the location under the screen centre" still agree exactly.
    // Returns whether the camera moved, so the opening knows whether the
    // windows are coming from the desktop (no fade) or from elsewhere (fade).
    function openView(spec) {
        if (spec === undefined || spec === null || spec === "") spec = configuration.OpenZoom;
        spec = String(spec || "fit").trim().toLowerCase();
        if (spec === "fit") { zoomExtents(true); return true; }
        const z = Number(spec);
        if (!(z > 0) || z >= 1) {
            // At 1:1 a fullscreen app is exactly the desktop: stepping out
            // would be invisible. Zoom out a little instead, so the canvas
            // is clearly the canvas.
            if (fullscreenOpen()) { fullscreenZoomTo(); return true; }
            return false;
        }
        const g = actionScreen().geometry;
        camZoomTo(z, g.x + g.width / 2, g.y + g.height / 2);
        return true;
    }

    // A fullscreen window is active and the fullscreen opening view is
    // enabled (FullscreenZoom is not "1").
    function fullscreenOpen() {
        const w = KWin.Workspace.activeWindow;
        if (!w || w.deleted || !w.fullScreen) return false;
        return String(configuration.FullscreenZoom || "0.85").trim().toLowerCase() !== "1";
    }
    function fullscreenZoomTo() {
        const spec = String(configuration.FullscreenZoom || "0.85").trim().toLowerCase();
        const g = actionScreen().geometry;
        if (spec === "fit") { zoomExtents(true); return; }
        const z = Number(spec);
        camZoomTo(z > 0 ? z : 0.85, g.x + g.width / 2, g.y + g.height / 2);
    }

    // Write every window's geometry relative to the frame it sits in, move it to
    // that frame's activity, put the camera on the current activity's target,
    // and hand input back. A close asked for while a gesture is in hand waits
    // for the buttons to come up, so the canvas never hands a held button to
    // the desktop mid-press.
    function commit(activate) {
        dbg("commit", "entering at zoom " + zoom.toFixed(3) + ", activate=" + activate);
        // A commit on a closed canvas still writes and publishes (the debug
        // channel uses it so), but it is a second ask for a close that has
        // landed: its layout must not go on the undo stack a second time.
        const wasOpen = visible;
        endSwitcher();
        finishEntryAnims();
        stopClickPan();
        if (sceneGestures > 0) {
            deferredClose = function () { commit(activate); };
            deferredAt = Date.now();
            return;
        }
        camStop();
        // The camera must be a real place before any geometry is written:
        // a diverged spring or a poisoned pan leaves NaN/Inf in the view, and
        // a frame write with those would hand KWin unusable geometries.
        if (!Number.isFinite(viewX) || !Number.isFinite(viewY) || !Number.isFinite(zoom) || zoom <= 0) {
            console.warn("kwin-canvas: refusing to commit from a non-finite camera, resetting it (view was " + viewX + "," + viewY + " zoom " + zoom + ")");
            viewX = 0;
            viewY = 0;
            zoom = 1.0;
        }
        // Entering syncs the floated windows to their pictures: the float's
        // clamped spot - the place the eye saw the window - becomes the
        // window's coordinates, so a floated window never lands off-screen
        // when the camera leaves it behind.
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (!isPinnedEntry(e)) continue;
            const f = floatOf[e.window.internalId];
            if (!f) continue;
            if (Math.abs(f.x - (e.x - viewX) * zoom) > 0.4 || Math.abs(f.y - (e.y - viewY) * zoom) > 0.4) {
                e.x = viewX + f.x / zoom;
                e.y = viewY + f.y / zoom;
                revision++;
            }
        }
        for (const k in targets) {
            targets[k].x = Math.round(targets[k].x);
            targets[k].y = Math.round(targets[k].y);
        }
        const seen = {};
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (e.window.deleted) continue;
            seen[e.window.internalId] = true;
            let a = activityAt(e);
            if (a === null) a = e.activity;
            // A window on every activity stays on every activity.
            if (a !== e.activity && a && e.window.activities.length > 0) e.window.activities = [a];
            e.activity = a;
            const t = targetOf(a);
            // Take the new frame position first: the write below is this
            // function's own projection of the entry, so the entry must
            // absorb it as no move (see settle()), not as the user having
            // dragged the window to the new screen position.
            const fx = Math.round(e.x - t.x), fy = Math.round(e.y - t.y);
            e.frameX = fx;
            e.frameY = fy;
            e.window.frameGeometry = Qt.rect(fx, fy, e.width, e.height);
        }
        // Windows not shown (minimized, hidden, other desktops) share the
        // plane: keep them where they were relative to their activity's frames.
        const all = KWin.Workspace.stackingOrder;
        for (let i = 0; i < all.length; ++i) {
            const w = all[i];
            if (seen[w.internalId] || w.deleted || !w.managed) continue;
            if (w.desktopWindow || w.dock || w.popupWindow || w.specialWindow) continue;
            const a = activityOf(w);
            const was = entryTargets[a], now = targetOf(a);
            if (!was) continue;
            const dx = was.x - now.x, dy = was.y - now.y;
            if (dx === 0 && dy === 0) continue;
            const g = w.frameGeometry;
            w.frameGeometry = Qt.rect(g.x + dx, g.y + dy, g.width, g.height);
        }
        // The frames now sit relative to these targets, so a later commit
        // (the chord, a stale click, an activity switch) must measure the
        // hidden windows against them and not shift them twice.
        entryTargets = copyTargets(targets);
        const cur = targetOf(currentActivity);
        viewX = cur.x;
        viewY = cur.y;
        zoom = 1.0;
        // Every commit leaves its layout on the undo stack, so Ctrl+Z can
        // step back to the one before it.
        if (wasOpen) {
            if (undoStack.length >= 20) undoStack.shift();
            undoStack.push({ targets: copyTargets(targets), layout: entries.map(function (e) { return { internalId: e.window.internalId, x: e.x, y: e.y, activity: e.activity }; }) });
        }
        // The location survives the session: where the eye left the plane
        // is where it comes back to after a restart.
        configuration.ViewX = Math.round(viewX);
        configuration.ViewY = Math.round(viewY);
        configuration.writeConfig();
        publishGround();
        publishCanvasState();
        settled = false;
        swiping = false;
        farewellHide(function () {
            visible = false;
            quiet = false;
        });
        if (activate && !activate.deleted) {
            KWin.Workspace.activeWindow = activate;
        }
    }

    // Cancel: back to where the canvas opened, nothing moved. With the smooth
    // camera the way back is a spring like any other - the camera flies to
    // the entry view at 1:1 and the restore happens on arrival - and a grab
    // mid-flight keeps the canvas open where the hand left it. The debug
    // channel takes doCancel() directly, the instant path a script measures.
    function cancel() {
        if (!visible) return;
        camStop();
        if (quiet || !smoothZoom
            || (Math.abs(zoom - 1) < 0.001 && Math.abs(viewX - entryViewX) < 0.5 && Math.abs(viewY - entryViewY) < 0.5)) {
            doCancel();
            return;
        }
        camGo(1, entryViewX, entryViewY, undefined, undefined, 2.0);
        camOnArrive = doCancel;
    }

    function doCancel() {
        dbg("cancel", "switcher=" + switcherActive);
        endSwitcher();
        stopClickPan();
        if (!visible) return;
        if (sceneGestures > 0) {
            deferredClose = doCancel;
            deferredAt = Date.now();
            return;
        }
        slideAnim.stop();
        unsettle();
        targets = copyTargets(entryTargets);
        viewX = entryViewX;
        viewY = entryViewY;
        zoom = 1.0;
        swiping = false;
        farewellHide(function () {
            visible = false;
            quiet = false;
        });
    }

    // The chord: step out to the canvas, or enter the location in view.
    function toggle() {
        if (quiet) { if (grasp) graspEnd(); else finishSlide(); return; }
        if (visible) enterHere(); else open();
    }

    // A screen edge or corner fired: by default the same step out and the
    // same enter, but the step out is a step *around the screen that was
    // pushed* (BorderZoom), so the push shows the desks around that screen
    // instead of the desktop it was already on. The chord and the toolbar
    // keep OpenZoom; a border that fires while the canvas is open enters, as
    // it always has. With BorderSlide the borders are a route around the
    // plane instead of a door in and out of it: a push pans one step toward
    // the pushed side, a slide at 1:1 and a camera step in the open canvas.
    // The opening view of this canvas, when it moved the camera (a corner
    // push at "fit" or a zoom): null once it has been left or never moved.
    property var openGoal: null
    function untouchedSinceOpen() {
        const g = openGoal;
        if (!g) return false;
        const x = camHasGoal ? camGoalX : viewX, y = camHasGoal ? camGoalY : viewY, z = camHasGoal ? camGoalZoom : zoom;
        return Math.abs(x - g.x) < 1 && Math.abs(y - g.y) < 1 && Math.abs(z - g.z) < 0.001;
    }
    function toggleFromBorder(border) {
        if (configuration.BorderSlide) { borderSlide(border); return; }
        if (quiet) { if (grasp) graspEnd(); else finishSlide(); return; }
        // Pushed again with the camera where the push left it: nothing was
        // chosen, so the way out is the way back. Entering "the location
        // under the screen centre" is only meaningful once you have looked
        // somewhere; at a fit view that centre is the plane's middle, and
        // the exit landed at a place nobody asked for.
        if (visible && untouchedSinceOpen()) { cancel(); return; }
        if (visible) { enterHere(); return; }
        open(false, configuration.BorderZoom);
    }

    // One border pan step: half a screen (PanStep), corners on both axes,
    // toward the pushed side. A slide mid-slide chains another step onto it,
    // so holding the pointer against the edge travels the plane. Border
    // numbers are ElectricBorder: 0 top, clockwise to 7 top-left.
    function borderSlide(border) {
        const dirs = [{ x: 0, y: -1 }, { x: 1, y: -1 }, { x: 1, y: 0 }, { x: 1, y: 1 },
                      { x: 0, y: 1 }, { x: -1, y: 1 }, { x: -1, y: 0 }, { x: -1, y: -1 }];
        const d = dirs[border];
        if (!d) return;
        const st = panStep();
        if (canvasOpen) { panKey(d.x, d.y); return; }
        slide(d.x * st.x, d.y * st.y);
    }

    // Move the camera one step (dx, dy in {-1, 0, 1}): the pan chords, the
    // border pan and the arrow keys all take this path, springing on the
    // smooth camera and jumping with SmoothZoom off.
    function panKey(dx, dy) {
        const st = panStep();
        camGo(zoom, viewX + dx * st.x / zoom, viewY + dy * st.y / zoom);
    }

    // Enter the location under the active screen's centre. The activity
    // whose frame holds that canvas point becomes current, its own when no
    // frame does, and its viewport is placed so that point is at the screen
    // centre at 1:1: at zoom 1 that is exactly where the camera is.
    function enterHere() {
        const g = actionScreen().geometry;
        const cx = g.x + g.width / 2, cy = g.y + g.height / 2;
        const c = globalToCanvas(cx, cy);
        const fs = frames();
        let id = null;
        for (let i = 0; i < fs.length; ++i) {
            const f = fs[i];
            if (c.x < f.x || c.x >= f.x + f.width || c.y < f.y || c.y >= f.y + f.height) continue;
            if (f.id === currentActivity) { id = f.id; break; }
            if (id === null) id = f.id;
        }
        const a = id !== null ? id : currentActivity;
        const t = targetOf(a);
        t.x = Math.round(c.x - cx);
        t.y = Math.round(c.y - cy);
        dbg("enterHere", "c=(" + Math.round(c.x) + "," + Math.round(c.y) + ") -> (" + t.x + "," + t.y + ")");
        flyEnter(a, t.x, t.y, function () { finishEnter(a); });
    }

    // ---- placing the desk around a window -------------------------------------

    // The offsets that keep a w x h window wholly inside the screen g, inset by
    // margin: the range of screen offsets its top-left may take, the offset
    // that centres it, and whether any offset fits at all (a window larger than
    // the screen fits nowhere). Everything here is in the units the target
    // moves in - canvas pixels, which at the applied 1:1 are screen pixels.
    // The range itself is Logic.fitRange, the pure half in logic.js.

    // The area of the windows on activity a, other than the one being placed,
    // that the screen g shows with that activity's target at (tx, ty). Windows
    // are counted one at a time - an overlap is counted twice - which is enough
    // to prefer the offset that keeps the desk in view.
    function deskArea(a, g, tx, ty, skip) {
        let sum = 0;
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (!e || e.window.deleted || e.window.internalId === skip) continue;
            if (e.activity !== a || !onActivity(e.window, a)) continue;
            // The screen sits at (g.x, g.y) in the desk: a screen off the origin
            // is clipped against its own rectangle, not against 0..width.
            const l = Math.max(e.x - tx, g.x), t = Math.max(e.y - ty, g.y);
            const r = Math.min(e.x - tx + e.width, g.x + g.width);
            const b = Math.min(e.y - ty + e.height, g.y + g.height);
            if (r > l && b > t) sum += (r - l) * (b - t);
        }
        return sum;
    }

    // Where the target goes to place `entry` on activity a around the active
    // screen g: the screen offset the window's top-left takes. The window
    // wholly in view is the one hard rule; among the offsets that keep it so,
    // the one that leaves the most of the desk's other windows in view wins, so
    // arriving at a window does not throw the rest of the desk off the screen.
    // The window is raised by the focus itself, so what it covers is not the
    // question - what the screen shows is. The target moves the whole plane, so
    // the windows keep their places relative to each other and only the screen
    // over them changes: the area in view is piecewise linear in the offset,
    // it breaks where a window's edge meets the screen's, so the best offset is
    // one of those alignments, the centred one, or a corner. Ties go to the
    // centred offset, which is where "centre" has always put the window, so the
    // common case - a window alone in view, or neighbours too far to matter -
    // does not change.
    function smartOffset(entry, a, g) {
        const margin = 8;
        const range = Logic.fitRange(entry.width, entry.height, g, margin);
        if (!range.fits) return { dx: range.cx, dy: range.cy };   // larger than the screen: centred, clipped
        const clamp = function (v, lo, hi) { return Math.max(lo, Math.min(hi, v)); };
        const xs = [range.x0, range.x1, range.cx], ys = [range.y0, range.y1, range.cy];
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (!e || e.window.deleted || e.window.internalId === entry.window.internalId) continue;
            if (e.activity !== a || !onActivity(e.window, a)) continue;
            // The offset is the window's top-left on screen; a neighbour's edges
            // sit at its own offset plus the gap between the two, so these are
            // the offsets that bring a neighbour's edge onto the screen's.
            const rx = e.x - entry.x, ry = e.y - entry.y;
            xs.push(clamp(-rx, range.x0, range.x1));
            xs.push(clamp(g.width - e.width - rx, range.x0, range.x1));
            ys.push(clamp(-ry, range.y0, range.y1));
            ys.push(clamp(g.height - e.height - ry, range.y0, range.y1));
        }
        let best = { dx: range.cx, dy: range.cy }, bestArea = -1, bestD = 0;
        for (let i = 0; i < xs.length; ++i) {
            for (let j = 0; j < ys.length; ++j) {
                const dx = xs[i], dy = ys[j];
                const area = deskArea(a, g, entry.x - g.x - dx, entry.y - g.y - dy, entry.window.internalId);
                const d = Math.abs(dx - range.cx) + Math.abs(dy - range.cy);
                if (bestArea < 0 || area > bestArea + 0.5
                    || (Math.abs(area - bestArea) <= 0.5 && d < bestD)) {
                    best = { dx: dx, dy: dy }; bestArea = area; bestD = d;
                }
            }
        }
        return best;
    }

    // ---- named actions --------------------------------------------------------

    // focusWindow: apply with this window focused. The window's activity is
    // the one whose frame it sits in, else the one it belongs to; the canvas
    // switches to it if it is not current, and the focus waits for the
    // switch, since KWin reports it asynchronously. Where its viewport goes
    // is focusMode(), and every mode is the activity's target: the frames, the
    // windows on them and the wallpaper slide together, nothing on the plane
    // moves, and nothing is written.
    property var pendingFocus: null
    // Where the viewport goes when a window gesture applies with that window
    // focused, written into the activity's target. gx/gy is the point kept
    // under the pointer in "window" mode; without one (the swap), the
    // window's centre is the anchor. Every mode is the activity's target:
    // the frames, the windows on them and the wallpaper slide together,
    // nothing on the plane moves, and nothing is written until the commit.
    function placeTarget(entry, a, gx, gy) {
        const t = targetOf(a);
        const mode = focusMode();
        if (mode === "window") {
            if (gx === undefined || gx === null) {
                const g = actionScreen().geometry;
                t.x = Math.round(entry.x + entry.width / 2 - (g.x + g.width / 2));
                t.y = Math.round(entry.y + entry.height / 2 - (g.y + g.height / 2));
            } else {
                // The first click of a double-click may have started a pan;
                // anchor on the camera's destination, not a mid-flight view.
                const vx = camHasGoal ? camGoalX : viewX, vy = camHasGoal ? camGoalY : viewY;
                t.x = Math.round(vx + gx / zoom - gx);
                t.y = Math.round(vy + gy / zoom - gy);
                // The point clicked is kept under the pointer unless that would
                // leave the window hanging over an edge of the screen: then the
                // least shift that brings it wholly back in, because a window a
                // double-click focused should not be half off the screen.
                const g = actionScreen().geometry;
                const range = Logic.fitRange(entry.width, entry.height, g, 8);
                if (range.fits) {
                    t.x = Math.round(entry.x - g.x - Math.max(range.x0, Math.min(range.x1, entry.x - t.x - g.x)));
                    t.y = Math.round(entry.y - g.y - Math.max(range.y0, Math.min(range.y1, entry.y - t.y - g.y)));
                }
            }
        } else if (mode === "smart") {
            const g = actionScreen().geometry;
            const off = smartOffset(entry, a, g);
            t.x = Math.round(entry.x - g.x - off.dx);
            t.y = Math.round(entry.y - g.y - off.dy);
        } else if (mode === "centre" || activityAt(entry) === null) {
            // "centre", and "desktop" for a window outside every frame.
            const g = actionScreen().geometry;
            t.x = Math.round(entry.x + entry.width / 2 - (g.x + g.width / 2));
            t.y = Math.round(entry.y + entry.height / 2 - (g.y + g.height / 2));
        }
        return t;
    }

    function focusWindow(entry, gx, gy) {
        clickPanEntry = null;
        clickPanTimer.stop();
        if (gx === undefined) { const p = cursorScreen(); gx = p.x; gy = p.y; }
        const inFrame = activityAt(entry);
        const a = inFrame !== null ? inFrame : (entry.activity || currentActivity);
        const t = placeTarget(entry, a, gx, gy);
        if (a && a !== currentActivity) {
            flyEnter(a, t.x, t.y, function () {
                pendingFocus = entry.window;
                KWin.Workspace.currentActivity = a;
                commit(null);
            });
            return;
        }
        flyEnter(a, t.x, t.y, function () { commit(entry.window); });
    }

    // zoomToActivity: camera fitted to that activity's frames - the ones that
    // are drawn, hidden outputs left out - on the spring like any other
    // destination. The canvas stays open.
    function zoomToActivity(id) {
        const fs = frames();
        let l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
        for (let i = 0; i < fs.length; ++i) {
            if (fs[i].id !== id) continue;
            l = Math.min(l, fs[i].x); t = Math.min(t, fs[i].y);
            r = Math.max(r, fs[i].x + fs[i].width); b = Math.max(b, fs[i].y + fs[i].height);
        }
        if (l === Infinity) return;
        const sg = actionScreen().geometry;
        const pad = 60;
        const z = Math.max(zoomMin, Math.min(1.0, Math.min((sg.width - 2 * pad) / (r - l), (sg.height - 2 * pad) / (b - t))));
        dbg("camGo", "zoomToActivity z=" + z.toFixed(3) + " to (" + Math.round((l + r) / 2 - (sg.x + sg.width / 2) / z) + "," + Math.round((t + b) / 2 - (sg.y + sg.height / 2) / z) + ")");
        camGo(z, (l + r) / 2 - (sg.x + sg.width / 2) / z, (t + b) / 2 - (sg.y + sg.height / 2) / z);
    }

    // ---- the animated step in -------------------------------------------------
    // Entering a location is a flight, not a cut: the camera springs to
    // (tx, ty) - the location's viewport at 1:1 - the overworld's chrome
    // fades, and on arrival done() runs, which switches the activity when
    // asked and commits. At zoom 1 the thumbnails and the real windows agree,
    // so the commit writes what the eye already saw and nothing on screen
    // jumps. A drag, a wheel or another camera move mid-flight takes the
    // camera back and the step in is over; the canvas stays open where the
    // hand left it. With SmoothZoom off the step is taken at once, as before.
    function flyEnter(a, tx, ty, done) {
        if (!visible || !smoothZoom
            || (Math.abs(zoom - 1) < 0.001 && Math.abs(viewX - tx) < 0.5 && Math.abs(viewY - ty) < 0.5)) {
            done();
            return;
        }
        camGo(1, tx, ty, undefined, undefined, 2.0);
        camOnArrive = done;
    }

    // The camera has arrived: activity a is made current - KWin reports the
    // switch asynchronously - and the commit writes every window relative to
    // the frame it sits in and hands input back.
    function finishEnter(a) {
        if (a !== currentActivity) KWin.Workspace.currentActivity = a;
        commit(null);
    }

    // gotoActivity: apply with that activity current, flying to its viewport
    // first. The camera springs to the activity's target at 1:1 and the
    // switch and the commit happen on arrival, so a frame double-click steps
    // into that location with the same animated step, wherever the camera is.
    function gotoActivity(id) {
        const a = id || currentActivity;
        const t = targetOf(a);
        flyEnter(a, t.x, t.y, function () { finishEnter(a); });
    }

    // newActivityAt: a new activity whose active-screen frame is centred on
    // the window, the window moved into it, applied and focused. The manager
    // answers asynchronously; activityAdded() finishes the job.
    function newActivityAt(entry) {
        if (!activityIds[0]) return;   // activities disabled
        pendingNewAt = entry;
        addActivity();
    }

    // ---- snapping --------------------------------------------------------------
    // Toggles start from config each time the canvas opens; the toolbar flips them.
    property bool snapEdges: true
    property bool snapCorners: true
    property bool snapGrid: false

    // Rects other than the moving set: windows and every activity's frames.
    function snapCandidates(movingIds, movingActivity) {
        const out = [];
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (movingIds && movingIds[e.window.internalId]) continue;
            out.push({ x: e.x, y: e.y, width: e.width, height: e.height });
        }
        const fs = frames();
        for (let i = 0; i < fs.length; ++i) {
            if (movingActivity !== null && movingActivity !== undefined && fs[i].id === movingActivity) continue;
            out.push({ x: fs[i].x, y: fs[i].y, width: fs[i].width, height: fs[i].height });
        }
        return out;
    }

    // Offset that snaps `rect` (canvas units): per-axis edge snap, corner snap
    // when both axes meet the same candidate, grid on left/top. The nearest
    // within SnapDistance screen pixels wins; 0 when nothing is near.
    function snapDelta(rect, cands) {
        const th = configuration.SnapDistance / zoom;
        let bx = 0, by = 0, bax = th + 1, bay = th + 1;
        const rx = [rect.x, rect.x + rect.width], ry = [rect.y, rect.y + rect.height];
        if (snapEdges || snapCorners) {
            for (let i = 0; i < cands.length; ++i) {
                const c = cands[i];
                const cx = [c.x, c.x + c.width], cy = [c.y, c.y + c.height];
                let ex = 0, ey = 0, eax = th + 1, eay = th + 1;
                for (let a = 0; a < 2; ++a) for (let b = 0; b < 2; ++b) {
                    const dx = cx[b] - rx[a], dy = cy[b] - ry[a];
                    if (Math.abs(dx) < eax) { eax = Math.abs(dx); ex = dx; }
                    if (Math.abs(dy) < eay) { eay = Math.abs(dy); ey = dy; }
                }
                if (snapEdges) {
                    if (eax < bax) { bax = eax; bx = ex; }
                    if (eay < bay) { bay = eay; by = ey; }
                } else if (eax <= th && eay <= th && eax + eay < bax + bay) {
                    bax = eax; bay = eay; bx = ex; by = ey;
                }
            }
        }
        if (snapGrid) {
            const g = Math.max(1, configuration.SnapGridSize);
            const gx = Math.round(rect.x / g) * g - rect.x, gy = Math.round(rect.y / g) * g - rect.y;
            if (Math.abs(gx) < bax) { bax = Math.abs(gx); bx = gx; }
            if (Math.abs(gy) < bay) { bay = Math.abs(gy); by = gy; }
        }
        return { dx: bax <= th ? bx : 0, dy: bay <= th ? by : 0 };
    }

    // Snap one moving edge value (1-D) against candidate edges and the grid.
    function snapEdge1D(value, horizontal, cands) {
        const th = configuration.SnapDistance / zoom;
        let best = 0, ba = th + 1;
        if (snapEdges || snapCorners) {
            for (let i = 0; i < cands.length; ++i) {
                const c = cands[i];
                const es = horizontal ? [c.x, c.x + c.width] : [c.y, c.y + c.height];
                for (let k = 0; k < 2; ++k) { const d = es[k] - value; if (Math.abs(d) < ba) { ba = Math.abs(d); best = d; } }
            }
        }
        if (snapGrid) {
            const g = Math.max(1, configuration.SnapGridSize);
            const d = Math.round(value / g) * g - value;
            if (Math.abs(d) < ba) { ba = Math.abs(d); best = d; }
        }
        return ba <= th ? best : 0;
    }

    // Raw, unsnapped positions of the set being dragged, keyed by window id,
    // and the entry the drag started on. A drag is live while dragIndex is >= 0:
    // the grip clears it on release and open() clears it with the rest of the
    // gesture state. That is what tells an edge pan a window is in hand, so it
    // can bring it along (edgePanStep).
    property var dragRaw: ({})
    property int dragIndex: -1
    function beginDrag(index) {
        const e = entries[index];
        if (!e) return;
        // A hand on a window is a hand on the canvas: any flight - a step in,
        // a cancel on the way back - is over, and the camera stops where it is.
        camStop();
        dragRaw = {};
        dragIndex = index;
        const set = isSelected(e) ? entries.filter(isSelected) : roomOf(e);
        for (let i = 0; i < set.length; ++i) dragRaw[set[i].window.internalId] = { x: set[i].x, y: set[i].y };
    }
    // A window held by KWin to a screen-locked state - tiled, or maximized -
    // belongs to a room: the other such windows in its cluster. Tiling is
    // one layout across a frame, so taking one window by the hand takes the
    // layout; a free window is its own set.
    function lockedEntry(e) { return !!e && !!e.window && !e.window.deleted && (!!e.window.tile || !!e.window.maximizeMode); }
    function roomOf(e) {
        if (!lockedEntry(e)) return [e];
        const ci = clusterIndexOfEntry(e);
        if (ci < 0 || !clusters[ci]) return [e];
        const out = [];
        for (let k = 0; k < clusters[ci].ids.length; ++k) {
            const m = entryById(clusters[ci].ids[k]);
            if (m && lockedEntry(m)) out.push(m);
        }
        return out.length > 0 ? out : [e];
    }
    // A hand on a cluster's badge is a hand on the whole cluster: the drag
    // set becomes its members, and the ordinary drag machinery moves them
    // as one, their geometry kept.
    function beginClusterDrag(i) {
        const c = clusters[i];
        if (!c) return;
        camStop();
        dragRaw = {};
        dragIndex = -1;
        for (let k = 0; k < c.ids.length; ++k) {
            const e = entryById(c.ids[k]);
            if (e) dragRaw[e.window.internalId] = { x: e.x, y: e.y };
        }
    }
    function dragCluster(i, dx, dy) {
        const c = clusters[i];
        if (!c || c.ids.length === 0) return;
        const e = entryById(c.ids[0]);
        if (e) dragEntry(entries.indexOf(e), dx, dy);
    }

    // ---- the weight of a dragged window --------------------------------------
    // Drawn, never measured: the entries, and so the committed geometry, follow
    // the pointer exactly. What trails is the picture, and how far it trails is
    // the hand's velocity, so a window leans after the hand while it is thrown
    // about and settles a moment after the hand stops - the read Compiz's and
    // KWin's wobbly windows give a window being moved, on a canvas instead of a
    // screen, without a mesh: a lifted scale, a trail along the direction of
    // travel and a lean about the centre, each on Qt's physical spring
    // (SpringAnimation: mass, spring, damping, epsilon) so the settle is a
    // spring rather than a curve.
    property real dragVX: 0
    property real dragVY: 0
    property real dragLagX: 0
    property real dragLagY: 0
    property real dragLean: 0
    property real dragLastAt: 0
    readonly property bool windowPhysics: configuration.WindowPhysics !== false
    // The speed at which the trail is at its longest, how far it may reach in
    // screen pixels, and how far the window may lean, in degrees.
    readonly property real dragLagFull: 900
    readonly property real dragLagMax: 26
    readonly property real dragLeanMax: 2.2

    function noteDrag(dx, dy) {
        // WindowPhysics off is no weight at all, not a weight nothing draws:
        // the trail, the lean and the velocity are zero, so what the state
        // reports is what the screen shows.
        if (!windowPhysics) { endWindowDrag(); return; }
        const now = Date.now();
        const dt = dragLastAt ? Math.max(8, now - dragLastAt) : 16;
        dragLastAt = now;
        // Smoothed: one sample of a 100 Hz pointer is noise, and a spring fed
        // noise shakes.
        dragVX = dragVX * 0.6 + (dx / (dt / 1000)) * 0.4;
        dragVY = dragVY * 0.6 + (dy / (dt / 1000)) * 0.4;
        const speed = Math.sqrt(dragVX * dragVX + dragVY * dragVY);
        if (speed <= 0) { dragLagX = 0; dragLagY = 0; dragLean = 0; return; }
        const reach = dragLagMax * Math.min(1, speed / dragLagFull);
        dragLagX = -dragVX / speed * reach;
        dragLagY = -dragVY / speed * reach;
        dragLean = Math.max(-dragLeanMax, Math.min(dragLeanMax, -dragVX / dragLagFull * dragLeanMax * 2));
    }

    // The weight goes: the hand has stopped and the trail, the lean and the
    // velocity are zero. noteDrag() calls this with the physics off, so it
    // touches nothing but the weight - the drag's own state is endDrag().
    function endWindowDrag() {
        dragVX = 0; dragVY = 0; dragLastAt = 0;
        dragLagX = 0; dragLagY = 0; dragLean = 0;
    }

    // The drag is over: the grip's release, or anything that ends a gesture.
    function endDrag() {
        // A pinned window's anchor is remembered where the hand let it go:
        // the float tick reads the entry itself and clamps the picture on
        // screen, so a drop outside is carried, not snapped.
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (!isPinnedEntry(e) || !dragRaw[e.window.internalId]) continue;
            const sx0 = (e.x - viewX) * zoom, sy0 = (e.y - viewY) * zoom;
            const cl = clampScreen(e);
            if (Math.abs(sx0 - cl.sx) < 0.5 && Math.abs(sy0 - cl.sy) < 0.5)
                pinned[e.window.caption] = { sx: sx0, sy: sy0 };
        }
        // The throw: a window let go while still moving fast keeps going, on
        // the glide's own Hermite curve with the hand's velocity as its start,
        // and comes to rest a short way on (the distance a flick would carry
        // under friction). Only for a hand that was still moving in the last
        // 80 ms - a window set down after a pause stays where it was put.
        const set = [];
        for (let i = 0; i < entries.length; ++i) if (dragRaw[entries[i].window.internalId]) set.push(entries[i]);
        const speed = Math.hypot(dragVX, dragVY);
        const fresh = dragLastAt > 0 && Date.now() - dragLastAt < 80;
        dragIndex = -1;
        // The drag's set goes with it: animateEntry leaves a window in dragRaw
        // to the hand, so one left behind would never glide again.
        dragRaw = {};
        lastSnapDX = 0; lastSnapDY = 0;
        // Only where the glide animates: with MovesGlide off animateEntry
        // writes the destination at once, and a throw would be a teleport.
        if (windowPhysics && configuration.MovesGlide !== false && fresh && speed > throwMin && set.length > 0) {
            // Screen px/s to plane px, over the carry time; capped so a wild
            // flick does not send a window off into the dark.
            const k = Math.min(1, throwMax / (speed * throwCarry));
            const ox = dragVX * throwCarry * k / zoom, oy = dragVY * throwCarry * k / zoom;
            dbg("throw", "speed=" + Math.round(speed) + " carry=(" + Math.round(ox) + "," + Math.round(oy) + ")");
            lastThrow = { dx: ox, dy: oy };
            for (let i = 0; i < set.length; ++i) {
                const e = set[i];
                if (isPinnedEntry(e)) continue;
                animateEntry(e, e.x + ox, e.y + oy, 0, dragVX / zoom, dragVY / zoom);
            }
        } else {
            lastThrow = null;
        }
        endWindowDrag();
    }
    // The throw's tuning: the hand speed (screen px/s) below which a release
    // is a set-down, the carry time a flick travels for, and the furthest it
    // may carry in screen px.
    readonly property real throwMin: 900
    readonly property real throwCarry: 0.12
    readonly property real throwMax: 360
    property var lastThrow: null

    // ---- arrange the selection ----------------------------------------------
    // Entries to arrange: the selection, or the one window the menu was opened on.
    property var contextEntry: null
    function arrangeTargets() {
        const out = [];
        for (let i = 0; i < entries.length; ++i) if (isSelected(entries[i])) out.push(entries[i]);
        if (out.length === 0 && contextEntry) out.push(contextEntry);
        out.sort(function (a, b) { return (a.y - b.y) || (a.x - b.x); });
        return out;
    }

    // Whether every window the pin menu would act on is already pinned, for
    // the menu's label.
    function pinTargetsPinned() {
        const list = arrangeTargets();
        if (list.length === 0) return false;
        for (let i = 0; i < list.length; ++i) if (!isPinnedEntry(list[i])) return false;
        return true;
    }

    function bbox(list) {
        let l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
        for (let i = 0; i < list.length; ++i) {
            const e = list[i];
            l = Math.min(l, e.x); t = Math.min(t, e.y); r = Math.max(r, e.x + e.width); b = Math.max(b, e.y + e.height);
        }
        return { x: l, y: t, width: r - l, height: b - t };
    }

    // arrange MODE [ROWS COLS]: horizontal, vertical, cascade keep sizes;
    // tile and grid split the selection's bounding box into cells and
    // command each window to its cell.
    function arrange(mode, rows, cols) {
        const list = arrangeTargets();
        if (list.length === 0) return;
        const gap = configuration.ArrangeGap;
        const box = bbox(list);
        const spots = {}; // internalId -> {x, y}: the landing, for the glide and the pin's clamp
        if (mode === "horizontal") {
            let x = box.x;
            for (let i = 0; i < list.length; ++i) { spots[list[i].window.internalId] = { x: x, y: box.y }; x += list[i].width + gap; }
        } else if (mode === "vertical") {
            let y = box.y;
            for (let i = 0; i < list.length; ++i) { spots[list[i].window.internalId] = { x: box.x, y: y }; y += list[i].height + gap; }
        } else if (mode === "cascade") {
            const step = 40;
            for (let i = 0; i < list.length; ++i) spots[list[i].window.internalId] = { x: box.x + i * step, y: box.y + i * step };
        } else {
            if (mode === "tile" || !(rows > 0 && cols > 0)) {
                cols = Math.ceil(Math.sqrt(list.length));
                rows = Math.ceil(list.length / cols);
            }
            const cw = Math.max(50, Math.floor((box.width - gap * (cols - 1)) / cols));
            const ch = Math.max(50, Math.floor((box.height - gap * (rows - 1)) / rows));
            for (let i = 0; i < list.length; ++i) {
                const e = list[i];
                const r = Math.floor(i / cols), c = i % cols;
                spots[e.window.internalId] = { x: box.x + c * (cw + gap), y: box.y + r * (ch + gap) };
                const idx = entries.indexOf(e);
                if (idx >= 0) requestSize(idx, cw, ch, false, false);
            }
        }
        for (let i = 0; i < list.length; ++i) {
            const sp = spots[list[i].window.internalId];
            animateEntry(list[i], sp.x, sp.y, i * 35); // the wave: the batch lands in a cascade, not a lockstep
        }
        // A pinned window keeps its pin: the arrangement becomes the new
        // anchor, clamped on screen - read from the landing, not the launch.
        for (let i = 0; i < list.length; ++i) {
            if (isPinnedEntry(list[i])) {
                const sp = spots[list[i].window.internalId];
                pinned[list[i].window.caption] = clampScreen(list[i], sp.x, sp.y);
            }
        }
        revision++;
    }

    // sendTo(activity): move the selection so each window keeps its place
    // within a frame, now in that activity's frame. sendTo(null): park the
    // set near the origin at the nearest spot outside every frame.
    // Lay the current activity's windows out in rows: sorted top-to-bottom,
    // left-to-right, packed from the frame's top-left with the tidy gap.
    // Nothing is written until the next commit - the same pattern as arrange.
    function tidy() {
        const vs = KWin.Workspace.virtualScreenGeometry;
        const t = targetOf(currentActivity);
        const gap = Math.max(12, Number(configuration.TidyGap) || 32);
        const list = [];
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (e.activity !== currentActivity) continue;
            list.push({ x: e.x, y: e.y, width: e.width, height: e.height, e: e });
        }
        if (list.length === 0) return;
        // tidyRows sorts a copy and returns the spots in that sorted order,
        // so the caller must sort its own list the same way before applying.
        list.sort(function (a, b) { return (a.y - b.y) || (a.x - b.x); });
        const spots = Logic.tidyRows(list, { gap: gap, origin: { x: t.x + gap, y: t.y + gap }, maxWidth: vs.width - gap * 2 });
        for (let i = 0; i < list.length; ++i) {
            animateEntry(list[i].e, spots[i].x, spots[i].y, i * 35); // the wave: the tidy lands row by row
        }
        revision++;
    }

    function sendTo(id) {
        const list = arrangeTargets();
        if (list.length === 0) return;
        const spots = {}; // internalId -> {x, y}: the landing, for the glide and the pin's clamp
        if (id !== null && id !== undefined) {
            for (let i = 0; i < list.length; ++i) {
                const e = list[i];
                let from = activityAt(e);
                if (from === null) from = e.activity;
                const a = peekTarget(from), b = peekTarget(id);
                spots[e.window.internalId] = { x: e.x + b.x - a.x, y: e.y + b.y - a.y };
            }
        } else {
            const box = bbox(list);
            const gap = configuration.ArrangeGap;
            const fs = frames();
            // Candidate spots: the origin, then just outside the union of all frames on each side.
            let l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
            for (let i = 0; i < fs.length; ++i) {
                const f = fs[i];
                l = Math.min(l, f.x); t = Math.min(t, f.y);
                r = Math.max(r, f.x + f.width); b = Math.max(b, f.y + f.height);
            }
            if (l === Infinity) { l = 0; t = 0; r = 0; b = 0; }
            const cands = [{ x: 0, y: 0 }, { x: l - box.width - gap, y: 0 }, { x: 0, y: t - box.height - gap },
                           { x: r + gap, y: 0 }, { x: 0, y: b + gap }];
            const clear = function (sx, sy) {
                for (let i = 0; i < fs.length; ++i) {
                    const f = fs[i];
                    if (sx < f.x + f.width && sx + box.width > f.x && sy < f.y + f.height && sy + box.height > f.y) return false;
                }
                return true;
            };
            let best = null, bd = Infinity;
            for (let i = 0; i < cands.length; ++i) {
                if (!clear(cands[i].x, cands[i].y)) continue;
                const dist = Math.hypot(cands[i].x, cands[i].y);
                if (dist < bd) { bd = dist; best = cands[i]; }
            }
            if (!best) best = { x: l - box.width - gap, y: t - box.height - gap };
            for (let i = 0; i < list.length; ++i) {
                spots[list[i].window.internalId] = { x: list[i].x + best.x - box.x, y: list[i].y + best.y - box.y };
            }
        }
        for (let i = 0; i < list.length; ++i) {
            const sp = spots[list[i].window.internalId];
            animateEntry(list[i], sp.x, sp.y, i * 35); // the wave: the batch lands in a cascade, not a lockstep
        }
        for (let i = 0; i < list.length; ++i) {
            if (isPinnedEntry(list[i])) {
                const sp = spots[list[i].window.internalId];
                pinned[list[i].window.caption] = clampScreen(list[i], sp.x, sp.y);
            }
        }
        revision++;
    }

    // Dispatch a gesture on a window against the mouse bindings.
    signal contextRequested(var entry)

    function windowGesture(entry, count, modifiers, button) {
        if (gestureMatches(configuration.MouseContextMenu, count, modifiers, button)) {
            contextEntry = entry;
            if (!isSelected(entry)) selectOnly(entry);
            contextRequested(entry);
        } else if (gestureMatches(configuration.MouseNewActivityAt, count, modifiers) && activityAt(entry) === null) {
            newActivityAt(entry);
        } else if (gestureMatches(configuration.MouseFocusWindow, count, modifiers)) {
            focusWindow(entry);
        } else if (gestureMatches(configuration.MouseSelectToggle, count, modifiers)) {
            selectToggle(entry);
        } else if (gestureMatches(configuration.MouseSelectAdd, count, modifiers)) {
            selectAdd(entry);
        } else if (gestureMatches(configuration.MouseSelect, count, modifiers)) {
            selectOnly(entry);
            // A click on a window focuses it: with the pass-through plugin a
            // client-area click already activates the window natively, so
            // this makes a click anywhere on the window - title bar included
            // - mean the same thing. The focus also makes the keyboard
            // follow, so the next keys go to the clicked window.
            if (!entry.window.deleted) KWin.Workspace.activeWindow = entry.window;
            // A click brings the window wholly into view: what is clicked on
            // must be seen, so the camera pans the least that fits it. The
            // pan waits out the double-click interval first - the first
            // click of a double-click must not move the window under the
            // pointer mid-tap, which resets the double-click's detection and
            // the placement that follows it.
            clickPanEntry = entry;
            clickPanTimer.restart();
        }
    }
    property var clickPanEntry: null
    // The click's pan is owed to an open canvas: every close drops it, or the
    // timer would fly a camera nobody is looking at after the commit.
    function stopClickPan() {
        clickPanEntry = null;
        clickPanTimer.stop();
    }
    Timer {
        id: clickPanTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (clickPanEntry && visible) {
                const e = clickPanEntry;
                clickPanEntry = null;
                bringIntoView(e);
            }
        }
    }

    // The modifier of the add gesture is also the marquee modifier on the ground.
    function marqueeModifiers() { return gestureFor(configuration.MouseSelectAdd).mods; }
    // The point over a window's frame, in the same coordinates the thumbs
    // are drawn in: the ground's tap drops the selection only on the frame's
    // own ground, never on a window - a window's tap is the window's gesture.
    function entryAtScreen(sx, sy) {
        for (let i = entries.length - 1; i >= 0; --i) {
            const e = entries[i];
            const f = floatOf[e.window.internalId];
            const x = f ? f.x : (e.x - viewX) * zoom;
            const y = f ? f.y : (e.y - viewY) * zoom;
            if (sx >= x && sx < x + e.width * zoom && sy >= y && sy < y + e.height * zoom) return e;
        }
        return null;
    }

    function frameGesture(id, count, modifiers) {
        if (gestureMatches(configuration.MouseGotoActivity, count, modifiers)) gotoActivity(id);
        else if (gestureMatches(configuration.MouseZoomToActivity, count, modifiers)) zoomToActivity(id);
    }

    function pick(entry) { focusWindow(entry); }

    // Move a window on the canvas by a screen-space delta while the canvas is open.
    // Entries are addressed by index: the Repeater hands delegates a copy of the
    // element, so mutating modelData would never reach the committed table.
    // A selected window drags the whole selection; relative geometry is kept.
    // Positions accumulate unsnapped in dragRaw, then the set's bounding box
    // is snapped as one, so a drag can always pull away from a snap.
    function dragEntry(index, dx, dy) {
        const e = entries[index];
        if (!e) return;        if (!dragRaw[e.window.internalId]) beginDrag(index);
        const set = [];
        for (let i = 0; i < entries.length; ++i) if (dragRaw[entries[i].window.internalId]) set.push(entries[i]);
        for (let i = 0; i < set.length; ++i) {
            const r = dragRaw[set[i].window.internalId];
            r.x += dx / zoom; r.y += dy / zoom;
            set[i].x = r.x; set[i].y = r.y;
        }
        const box = bbox(set);
        const d = snapDelta(box, snapCandidates(dragRaw, null));
        for (let i = 0; i < set.length; ++i) { set[i].x += d.dx; set[i].y += d.dy; }
        snapCatch(d);
        revision++;
    }
    // The magnet: the moment a drag catches a snap, the window would jump the
    // last few pixels to the edge. The picture instead starts where the hand
    // had it and springs onto the edge, so the snap reads as a pull, not a
    // teleport. Drawn only - the entry is already exact.
    property real snapKickX: 0
    property real snapKickY: 0
    property real lastSnapDX: 0
    property real lastSnapDY: 0
    property int snapCatches: 0
    function snapCatch(d) {
        const caughtX = d.dx !== 0 && lastSnapDX === 0, caughtY = d.dy !== 0 && lastSnapDY === 0;
        lastSnapDX = d.dx; lastSnapDY = d.dy;
        if (!windowPhysics || quiet || (!caughtX && !caughtY)) return;
        snapCatches++;
        snapKickAnim.stop();
        if (caughtX) snapKickX = -d.dx * zoom;
        if (caughtY) snapKickY = -d.dy * zoom;
        snapKickAnim.restart();
    }
    ParallelAnimation {
        id: snapKickAnim
        NumberAnimation { target: effect; property: "snapKickX"; to: 0; duration: 170; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        NumberAnimation { target: effect; property: "snapKickY"; to: 0; duration: 170; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
    }

    // Command the real window to a size while the canvas is open. Position is
    // untouched. The client answers with whatever size it accepts, and
    // syncSize() copies that back into the entry when the geometry changes.
    function requestSize(index, w, h, anchorRight, anchorBottom) {
        const e = entries[index];
        if (!e || e.window.deleted) return;
        camStop();
        // Snap the edge being dragged. Left/top anchors keep the far edge fixed.
        const ids = {}; ids[e.window.internalId] = true;
        const cands = snapCandidates(ids, null);
        const right = e.x + e.width, bottom = e.y + e.height;
        w += snapEdge1D(anchorRight ? right - w : e.x + w, true, cands) * (anchorRight ? -1 : 1);
        h += snapEdge1D(anchorBottom ? bottom - h : e.y + h, false, cands) * (anchorBottom ? -1 : 1);
        e.anchorRight = anchorRight;
        e.anchorBottom = anchorBottom;
        e.askW = Math.max(50, Math.round(w));
        e.askH = Math.max(50, Math.round(h));
        const f = e.window.frameGeometry;
        e.window.frameGeometry = Qt.rect(f.x, f.y, e.askW, e.askH);
    }

    // Absorb a window's real frame change into its entry. Returns true if anything moved.
    function syncEntry(e) {
        if (!e || e.window.deleted) return false;
        const f = e.window.frameGeometry;
        let changed = false;
        if (f.x !== e.frameX || f.y !== e.frameY) {
            e.x += f.x - e.frameX;
            e.y += f.y - e.frameY;
            e.frameX = f.x;
            e.frameY = f.y;
            changed = true;
        }
        if (f.width !== e.width || f.height !== e.height) {
            e.askW = 0;
            e.askH = 0;
            if (e.anchorRight) e.x += e.width - f.width;
            if (e.anchorBottom) e.y += e.height - f.height;
            e.width = f.width;
            e.height = f.height;
            changed = true;
        }
        return changed;
    }

    function syncIndex(index) {
        if (syncEntry(entries[index])) revision++;
    }

    // ---- pass-through plugin -------------------------------------------------
    KWin.DBusCall {
        id: probeCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "probe"
        onFinished: effect.passthroughProbed()
    }
    KWin.DBusCall {
        id: activeCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "setActive"
    }
    KWin.DBusCall {
        id: cameraCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "setCamera"
    }
    KWin.DBusCall {
        id: navCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "setNavButtons"
    }
    KWin.DBusCall {
        id: holdCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "setHoldButtons"
    }
    KWin.DBusCall {
        id: holdDelayCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "setHoldDelay"
    }
    KWin.DBusCall {
        id: hoverDelayCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "setHoverDelay"
    }
    KWin.DBusCall {
        id: canvasStateCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "setCanvasState"
    }
    KWin.DBusCall {
        id: verboseCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "setVerbose"
    }
    KWin.DBusCall {
        id: doorCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "setDoorEnabled"
    }
    // The plugin's own state, polled for the toolbar's hand dot. The reply
    // string is "active=.. view=(x,y) zoom=.. grab=.. ground=.. hover=..
    // nav=.. hold=.. seam=.." - a hover or a grab is the window's hand.
    KWin.DBusCall {
        id: pluginStateCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "state"
        onFinished: (result) => {
            effect.dbg("hand", "plugin state reply: " + String(result));
            const s = String(result || "");
            const hi = s.indexOf(" hover=");
            const gi = s.indexOf(" grab=");
            const h = hi >= 0 ? s.slice(hi + 7).split(" ")[0] : "-";
            const gr = gi >= 0 ? s.slice(gi + 6).split(" ")[0] : "-";
            effect.handOnWindow = h !== "-" || gr !== "-";
        }
    }
    Timer {
        interval: 400
        repeat: true
        running: effect.visible && !effect.quiet && effect.passthroughLive
        onTriggered: { if (effect.passthroughLive) pluginStateCall.call(); }
    }
    // The machine's load, for the fidelity ladder. The plugin reads /proc
    // itself (three small reads) and answers "cpu=N load=NN.NN mem=MMMM
    // gpu=N"; cpu and gpu are the busy percentages since the previous call,
    // gpu via NVML when the NVIDIA driver is present. Polled every two
    // seconds while the overworld is open - a fixed mode needs no probe,
    // the ladder applies the cap directly.
    KWin.DBusCall {
        id: loadCall
        service: "org.kde.KWin"
        path: "/KWinCanvas"
        dbusInterface: "org.kde.kwin.canvas.Passthrough"
        method: "load"
        onFinished: (result) => {
            const s = String(result || "");
            const ci = s.indexOf("cpu=");
            const cpu = ci >= 0 ? Number(s.slice(ci + 4).split(" ")[0]) : 0;
            const gi = s.indexOf("gpu=");
            const gpu = gi >= 0 ? Number(s.slice(gi + 4).split(" ")[0]) : 0;
            const mi = s.indexOf("mem=");
            const mem = mi >= 0 ? Number(s.slice(mi + 4).split(" ")[0]) : 0;
            effect.qualityApply(Number.isFinite(cpu) ? cpu : 0, Number.isFinite(gpu) ? gpu : 0, Number.isFinite(mem) ? mem : 0);
        }
    }
    Timer {
        id: loadPulse
        interval: 2000
        repeat: true
        running: effect.visible && !effect.quiet
        onTriggered: {
            if (String(effect.configuration.QualityMode) !== "Auto") effect.qualityApply(0, 0, 0);
            else loadCall.call();
        }
    }
    // The shader wallpaper's feed. The commit writes the authoritative state
    // for the closed desktop; this tick keeps it fed while the canvas runs,
    // so the wallpaper's engine (its own 1s poll) sees the live camera and
    // the clusters mid-flight instead of the last landing. The
    // overworld's scene covers the wallpaper while the canvas is open, but
    // the data is live for the engine's preview and any surface that reads
    // the file.
    Timer {
        interval: 1000
        repeat: true
        running: effect.visible
        onTriggered: effect.publishCanvasState()
    }
    // The plugin answered: if the canvas is still open, switch it on and give it the camera.
    function passthroughProbed() {
        if (!canvasOpen || passthroughLive) return;
        passthroughLive = true;
        publishCamera();
        publishNav();
        publishHold();
        publishVerbose();
        activeCall.arguments = [true];
        activeCall.call();
    }
    function publishCamera() {
        if (!passthroughLive) return;
        cameraCall.arguments = [viewX, viewY, zoom, currentActivity, JSON.stringify(targets)];
        cameraCall.call();
    }
    // The buttons the plugin leaves to the canvas whatever is drawn under the
    // pointer: the same mask the shim reads (planeNavButtons). Told when the
    // plugin answers, and again if the binding changes.
    function publishNav() {
        if (!passthroughLive) return;
        navCall.arguments = [planeNavButtons];
        navCall.call();
    }
    // The canvas-modifier buttons (CanvasHold): the plugin watches for these
    // even while the canvas is closed, consumes them, and flips the effect's
    // canvasHold property on each press and release. The mask has to reach
    // the plugin before the first hold, so it is published as soon as the
    // effect loads, on every reconfigure, and again whenever the plugin
    // answers its probe.
    readonly property int holdButtons: bindings.hold || 0
    function publishHold() {
        holdCall.arguments = [holdButtons];
        holdCall.call();
        const delay = Number(configuration.HoldDelay) || 300;
        // The | 0 is load-bearing: QML numbers are doubles, and QDBus does
        // not demote a double argument to the plugin's int slot, so the call
        // would vanish. (holdButtons above is already an int property.)
        holdDelayCall.arguments = [delay | 0];
        holdDelayCall.call();
        const hover = Number(configuration.HoverDelay) || 900;
        hoverDelayCall.arguments = [hover | 0];
        hoverDelayCall.call();
        publishDoor();
    }
    // The zoom door's knob reaches the plugin too: the door needs the
    // filter's eyes while the canvas is closed, and the plugin reads its
    // own copy once at load - so the effect publishes the setting at every
    // reconfigure (the same moments publishHold runs).
    function publishDoor() {
        doorCall.arguments = [configuration.WheelDoor !== false];
        doorCall.call();
    }
    // The trace flag reaches the plugin too, so its side of every decision
    // lands in the same log.
    function publishVerbose() {
        if (!passthroughLive) return;
        verboseCall.arguments = [verb];
        verboseCall.call();
    }
    onVerbChanged: publishVerbose()
    function dropPassthrough() {
        if (!passthroughLive) return;
        passthroughLive = false;
        activeCall.arguments = [false];
        activeCall.call();
    }
    onViewXChanged: if (passthroughLive) Qt.callLater(publishCamera)
    onViewYChanged: if (passthroughLive) Qt.callLater(publishCamera)
    onZoomChanged: if (passthroughLive) Qt.callLater(publishCamera)
    onPlaneNavButtonsChanged: publishNav()
    onHoldButtonsChanged: publishHold()
    onPlaneInputChanged: if (planeInput) dropPassthrough()

    // ---- plane input -----------------------------------------------------------
    // The pointer in global screen coordinates; KWin reports plane
    // coordinates while the transform is live.
    function cursorScreen() {
        const p = KWin.Workspace.cursorPos;
        return planeLive ? Qt.point(p.x * planeScale + planeOffsetX, p.y * planeScale + planeOffsetY) : p;
    }

    // The output holding a global point, or null. Edge panning asks which
    // screen the pointer is on so that only that screen's view pans.
    function screenAt(x, y) {
        const ss = KWin.Workspace.screens;
        for (let i = 0; i < ss.length; ++i) {
            const g = ss[i].geometry;
            if (x >= g.x && x < g.x + g.width && y >= g.y && y < g.y + g.height) return ss[i];
        }
        return null;
    }

    // The screen the user is acting on: the one the pointer is on, else the
    // active window's. A screen edge fires with the pointer on the border's own
    // pixel, and KWin puts the corner zones on every screen of the layout
    // (ElectricBorderAllScreenCorner), so on several outputs this is the screen
    // that was pushed - which is the screen the camera should open around, not
    // whichever one the focused window happens to be on. Workspace.activeScreen
    // is that window's screen, which on a two-monitor desktop is wrong half the
    // time; everything the pointer starts asks here instead.
    function actionScreen() {
        const p = cursorScreen();
        return screenAt(p.x, p.y) || KWin.Workspace.activeScreen;
    }

    // One step of edge panning, for a view whose screen is sg: radial and
    // natural. The pointer inside the central resting zone does nothing; past
    // it the pan follows the pointer's direction from the screen centre and
    // speeds up toward the edge, so a corner pans diagonally and a pointer
    // hard against the edge flies. The view moves toward the pushed side,
    // revealing what lies beyond it, as dragging the desk away does.
    function edgePanStep(sg, dt) {
        if (!sg || edgePanSpeed <= 0 || dt <= 0) return;
        // The chrome owns its pixels: resting the pointer on the dock or a
        // panel must not keep the canvas scrolling underneath it.
        if (chromeHover) return;
        const p = cursorScreen();
        if (p.x < sg.x || p.x >= sg.x + sg.width || p.y < sg.y || p.y >= sg.y + sg.height) return;
        const cx = sg.x + sg.width / 2, cy = sg.y + sg.height / 2;
        const dx = p.x - cx, dy = p.y - cy;
        // The resting zone: everything but the outer band (EdgePanMargin).
        const deadX = sg.width / 2 - edgePanMargin, deadY = sg.height / 2 - edgePanMargin;
        const reachX = edgePanMargin, reachY = edgePanMargin;
        const tx = Math.abs(dx) <= deadX ? 0 : Math.sign(dx) * Math.min(1, (Math.abs(dx) - deadX) / reachX);
        const ty = Math.abs(dy) <= deadY ? 0 : Math.sign(dy) * Math.min(1, (Math.abs(dy) - deadY) / reachY);
        // The envelope: the pan gathers over ~120 ms and lets go the same
        // way, so the camera never snaps into or out of the edge motion.
        const target = (tx !== 0 || ty !== 0) ? 1 : 0;
        edgePanGain += (target - edgePanGain) * (1 - Math.exp(-dt / (target > edgePanGain ? 0.045 : 0.075)));
        if (edgePanGain < 0.002 && target === 0) { edgePanGain = 0; return; }
        // The depth, curved: a gentle start and a strong edge.
        const vx = Math.sign(tx) * Math.pow(Math.abs(tx), 1.2) * edgePanSpeed * dt * edgePanGain;
        const vy = Math.sign(ty) * Math.pow(Math.abs(ty), 1.2) * edgePanSpeed * dt * edgePanGain;
        noteGesture();
        const beforeX = viewX, beforeY = viewY;
        panBy(-vx, -vy);
        // The window rides the camera's own move: it must keep its screen
        // spot exactly, which is the same as moving with the camera across
        // the plane. dragEntry's units are screen pixels, so the plane delta
        // rides through the zoom.
        edgeDrag((viewX - beforeX) * zoom, (viewY - beforeY) * zoom);
    }

    // An edge pan with a window in hand takes the window along: holding a
    // navigate button on a window and pushing the pointer to a screen edge pans
    // and carries it. The camera
    // moved the plane by (vx, vy) on screen, so the window moves with the
    // plane's content by the same amount on the plane - its screen position
    // does not change and
    // it stays under the pointer - while the desk, the frames included, travels
    // under it: the edge scroll of any drag and drop, with a desktop on the
    // plane. Same call as the pointer's own step, so the set being dragged, the
    // snapping and the write under plane input all behave the same, and the
    // window stays still on screen, which is why it neither trails nor leans.
    function edgeDrag(dx, dy) {
        if (dragIndex < 0) return;
        dragEntry(dragIndex, dx, dy);
    }

    // Called by the shim for a global screen point: true where the canvas
    // takes the pointer, false where it goes to w, the window KWin finds at
    // the matching plane point. The pointer goes to a window only over the
    // client area of its drawn thumbnail, or over a drawn app popup, with no
    // control above it, and only while KWin has that same window there.
    function planeTakes(x, y, w) {
        if (!planeLive || canvasMenus > 0) return true;
        const sv = effect.viewAt(Qt.point(x, y));
        let item = sv ? sv.rootItem : null;
        if (!item) return true;
        let p = Qt.point(x - item.sg.x, y - item.sg.y);
        for (let c = item.childAt(p.x, p.y); c; c = item.childAt(p.x, p.y)) {
            p = item.mapToItem(c, p.x, p.y);
            item = c;
            if (item.objectName === "kwin-canvas-client") return !reaches(item.entry, w);
            if (item.objectName === "kwin-canvas-popup") return !w || item.modelData !== w;
        }
        return true;
    }

    // KWin has the entry's window at the drawn position: on the current
    // activity, where the entry says, and topmost there.
    function reaches(e, w) {
        if (!e || !e.window || e.window.deleted || w !== e.window) return false;
        if (e.activity !== currentActivity || !onActivity(e.window, currentActivity)) return false;
        const t = peekTarget(currentActivity), f = e.window.frameGeometry;
        return Math.abs(e.x - t.x - f.x) < 1 && Math.abs(e.y - t.y - f.y) < 1;
    }

    // KWin routes the pointer by real geometry, so while the transform is
    // live a window of the current activity that moves on the canvas is
    // written at once. The entry takes the new frame position first, so it
    // absorbs the write as no move.
    function settle() {
        if (!planeLive) return;
        const t = peekTarget(currentActivity);
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (!e || !e.window || e.window.deleted || e.activity !== currentActivity || !onActivity(e.window, currentActivity)) continue;
            const fx = Math.round(e.x - t.x), fy = Math.round(e.y - t.y);
            if (fx === e.frameX && fy === e.frameY) continue;
            e.frameX = fx;
            e.frameY = fy;
            // A size requestSize() asked for may not have arrived yet; ask for
            // it again rather than the old size.
            const g = e.window.frameGeometry;
            e.window.frameGeometry = Qt.rect(fx, fy, e.askW || g.width, e.askH || g.height);
            settled = true;
        }
    }
    onRevisionChanged: { if (planeLive) Qt.callLater(settle); Qt.callLater(recluster); }

    // Cancel puts every window settle() moved back where it was at open.
    function unsettle() {
        if (!settled) return;
        settled = false;
        for (let i = 0; i < entries.length; ++i) {
            const w = entries[i] ? entries[i].window : null;
            if (!w || w.deleted) continue;
            const o = openFrames[w.internalId];
            if (!o) continue;
            const g = w.frameGeometry;
            if (g.x !== o.x || g.y !== o.y) {
                w.frameGeometry = Qt.rect(o.x, o.y, g.width, g.height);
            }
        }
    }

    // ---- ground publication ------------------------------------------------
    KWin.DBusCall {
        id: groundCall
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
    }

    // The active wallpaper: the ground's offset writes are only meaningful
    // while the kwin-canvas-ground wallpaper is drawing them - and any write
    // there makes plasmashell rebuild the wallpaper item, so a foreign
    // wallpaper (a video, say) must never receive them.
    KWin.DBusCall {
        id: wallpaperQueryCall
        service: "org.kde.plasmashell"
        path: "/PlasmaShell"
        dbusInterface: "org.kde.PlasmaShell"
        method: "evaluateScript"
        onFinished: (result) => {
            const s = String(result || "");
            effect.groundIsActive = s.indexOf("kwin-canvas-ground") !== -1;
            // Whether every wallpaper is one Plasma's own item can draw. Kept
            // here, on the effect, because the scene is rebuilt on every
            // open and a scene that has to ask for itself paints its first
            // frames before the answer: the black frame of a fly.
            const plugins = s.split("|").filter(function (p) { return p.trim().length > 0; });
            if (plugins.length > 0) {
                const picture = ["org.kde.image", "org.kde.slideshow", "org.kde.color", "org.kde.potd", "kwin-canvas-ground"];
                effect.wallpaperPicture = plugins.every(function (p) { return picture.indexOf(p.trim()) !== -1; });
            }
            effect.groundCheckedAt = Date.now();
            effect.dbg("ground", "wallpaper query: " + s);
        }
    }
    property bool groundIsActive: false
    property bool wallpaperPicture: false
    property double groundCheckedAt: 0
    function refreshGroundWallpaper() {
        wallpaperQueryCall.arguments = ["let r = ''; const ds = desktops(); for (let i = 0; i < ds.length; ++i) { r += (ds[i].wallpaperPlugin || '') + '|'; } print(r);"];
        wallpaperQueryCall.call();
    }

    function publishGround() {
        if (!configuration.PublishGround) return;
        if (Date.now() - groundCheckedAt > 3000) refreshGroundWallpaper();
        if (!groundIsActive) return;
        const script =
            "const ds = desktops();" +
            "for (let i = 0; i < ds.length; ++i) {" +
            "  ds[i].currentConfigGroup = ['Wallpaper', 'kwin-canvas-ground', 'General'];" +
            "  ds[i].writeConfig('OffsetX', " + viewX + ");" +
            "  ds[i].writeConfig('OffsetY', " + viewY + ");" +
            // The ground's own knobs ride the same channel: the wallpaper
            // must draw the grid the user configured, or the seam between
            // the closed desktop and the canvas's ground would show two
            // different grids wherever the camera leaves the frame.
            "  ds[i].writeConfig('GridBase', " + (Number(configuration.GridBase) || 64) + ");" +
            "  ds[i].writeConfig('GridOctaveFactor', " + (Number(configuration.GridOctaveFactor) || 8) + ");" +
            "  ds[i].writeConfig('GridOctaves', " + (Number(configuration.GridOctaves) || 4) + ");" +
            "  ds[i].writeConfig('Background', '" + String(configuration.Background || "#1c1f26").replace(/'/g, "") + "');" +
            "  ds[i].writeConfig('LineColor', '" + String(configuration.LineColor || "#7f8fb0").replace(/'/g, "") + "');" +
            "  ds[i].writeConfig('TileImage', '" + String(configuration.TileImage || "").replace(/'/g, "") + "');" +
            "  ds[i].writeConfig('ShowLabels', " + (configuration.ShowLabels === false ? "false" : "true") + ");" +
            "}";
        groundCall.arguments = [script];
        groundCall.call();
    }

    // ---- the shader channel ------------------------------------------------
    // The plane's remembered state, pushed at each commit for the shader
    // wallpaper's engine: the saved view, the clusters and the ground,
    // all in plane coordinates - the plugin screen-projects them, so a
    // fragment shader works in pixels with no camera math of its own.
    function canvasStateString() {
        let s = "view=" + Math.round(viewX) + "," + Math.round(viewY) + "\n";
        // The projection scales by the zoom: a publish mid-overworld (the live
        // tick) must land the features where the eye sees them, not where a
        // 1:1 projection would put them. The commit publishes at zoom 1.
        s += "zoom=" + zoom.toFixed(3) + "\n";
        // The ground itself: the shader wallpaper draws the plane's own grid,
        // so the closed desktop is the plane at rest.
        const lc = configuration.LineColor;
        const bg = configuration.Background;
        s += "grid=" + (Number(configuration.GridBase) || 64) + "," + (Number(configuration.GridOctaveFactor) || 8) + "," + (Number(configuration.GridOctaves) || 4)
            + "," + Math.round((lc ? lc.r : 0.5) * 255) + "," + Math.round((lc ? lc.g : 0.56) * 255) + "," + Math.round((lc ? lc.b : 0.69) * 255)
            + "," + Math.round((bg ? bg.r : 0.11) * 255) + "," + Math.round((bg ? bg.g : 0.12) * 255) + "," + Math.round((bg ? bg.b : 0.15) * 255) + "\n";
        for (let i = 0; i < clusters.length && i < 16; i++) {
            s += "cluster=" + Math.round(clusters[i].cx) + "," + Math.round(clusters[i].cy) + "," + clusters[i].n + "\n";
        }
        return s;
    }
    function publishCanvasState() {
        canvasStateCall.arguments = [canvasStateString()];
        canvasStateCall.call();
    }

    // ---- backdrop: the desktop's own wallpaper on the plane ------------------
    // The canvas's background is the wallpaper, not a void. On the desks it is
    // exact - every frame draws the real desktop window, so at 1:1 the
    // overworld is pixel-identical to the desktop under the effect. Beyond the
    // desks the plane shows the same wallpaper blurred (BackdropBlur) and
    // dimmed (BackdropDim), screen-fixed like an overview's backdrop, with the
    // ground grid over it: the desktop dissolving into a haze instead of the
    // wallpaper repeating in tiles. The blur layer is the desktop window
    // itself, live - a slideshow, a picture of the day or an animated
    // wallpaper keeps going in the haze too - and it is hidden while the
    // current activity's frame covers the view, which is where the blur would
    // be invisible anyway (open at 1:1, an idle slide), so it costs nothing
    // until the camera moves. Only the effect draws this; while the canvas is
    // closed the wallpaper is the real one, and the ground wallpaper plugin
    // (with a grid, at 1:1) stands in for the plane.
    property int screensRev: 0

    function backdropMode() {
        const m = String(configuration.Backdrop || "wallpaper").trim().toLowerCase();
        return m === "grid" ? "grid" : "wallpaper";
    }
    // The wallpaper rides through untouched now: the backdrop's half-res
    // copy and its blur are gone, so the real desktop behind the plane is
    // the haze-free, grey-free continuation at every zoom.
    // The blur layers drawn: one per output, in wallpaper mode. The state
    // line reports this, so a scenario can see which mode is up.
    readonly property int backdropLayers: backdropMode() === "wallpaper" ? KWin.Workspace.screens.length : 0

    // ---- 1:1 behaviours (effect closed) ------------------------------------
    // A window that rides with this activity's viewport: managed, not part of
    // the shell, on this activity or on every activity. Minimized windows and
    // other desktops' windows count, so the plane stays whole under a pan.
    function isViewportWindow(w) {
        if (!w || w.deleted || !w.managed) return false;
        if (w.desktopWindow || w.dock || w.popupWindow || w.specialWindow) return false;
        return onActivity(w, currentActivity);
    }

    // Shift the current activity's viewport: move its windows and its target.
    function shiftAll(dx, dy) {
        const all = KWin.Workspace.stackingOrder;
        for (let i = 0; i < all.length; ++i) {
            const w = all[i];
            if (!isViewportWindow(w)) continue;
            const g = w.frameGeometry;
            w.frameGeometry = Qt.rect(g.x + dx, g.y + dy, g.width, g.height);
        }
        const t = targetOf(currentActivity);
        t.x -= dx;
        t.y -= dy;
        viewX = t.x;
        viewY = t.y;
        publishGround();
    }

    // ---- the slide: an animated pan at 1:1 ---------------------------------
    // Open quietly at 1:1, where the thumbnails and the ground are pixel-
    // identical to the real screen, move the camera, and end with shiftAll:
    // the desktop slides, and this activity's windows are written once at the
    // end. Nothing changes activity, and only this activity's windows are
    // drawn, so what slides is what 1:1 shows. A slide that arrives mid-slide
    // extends the destination. dx, dy are canvas pixels the camera moves by;
    // the windows move the other way.
    property real slideToX: 0
    property real slideToY: 0
    readonly property int panDuration: Math.max(0, Number(configuration.PanDuration) || 0)
    readonly property int sceneFadeMs: Math.max(1, Number(configuration.SceneFadeMs) || 90)

    // One pan step in screen pixels: a fraction of the active screen.
    function panStep() {
        const f = Math.max(0.05, Math.min(1, Number(configuration.PanStep) || 0.5));
        const g = actionScreen().geometry;
        return Qt.point(Math.round(g.width * f), Math.round(g.height * f));
    }

    // The slide's duration grows with its distance, sub-linearly: a short
    // pan reads quick, a long one glides, and the PanDuration knob is the
    // half-screen reference.
    function slide(dx, dy) {
        if (!beginSlide()) return;
        if (!slideAnim.running) { slideToX = viewX; slideToY = viewY; }
        slideToX += dx;
        slideToY += dy;
        slideGo();
    }

    // A slide to a fresh destination, from wherever the camera is now: the
    // fly's own slide. A fly is the destination itself, not a step to
    // chain onto a previous one's half-travelled slide.
    function slideTo(dx, dy) {
        if (!beginSlide()) return;
        slideToX = viewX + dx;
        slideToY = viewY + dy;
        slideGo();
    }

    // The glide waits one event-loop turn for the scene's first paint: the
    // quiet canvas at 1:1 paints the same pixels as the desktop it covers,
    // so the warm frame is invisible, and the cold thumbnails never flash
    // under the glide.
    function slideGo() {
        if (slideWarm) {
            slideWarm = false;
            Qt.callLater(slideGo);
            return;
        }
        // The flight's length follows its distance, gently: a short hop is
        // quick, a long one a little longer, so near moves never drag and far
        // ones never jerk. PanDuration is the reference for about half a
        // screen; 0 still jumps.
        const dist = Math.hypot(slideToX - viewX, slideToY - viewY) * zoom;
        const g = actionScreen().geometry;
        const half = Math.max(1, Math.hypot(g.width, g.height) / 2);
        slideMs = panDuration <= 0 ? 0 : Math.round(Math.max(0.8, Math.min(1.5, 0.8 + 0.7 * Math.sqrt(dist / half))) * panDuration);
        slideAnim.restart();
    }
    property int slideMs: panDuration

    // Open quietly if closed. False while the real canvas is open.
    function beginSlide() {
        if (visible && !quiet) return false;
        // A slide that has landed holds the scene one paint more before its
        // close (slideCloseTimer). A new slide in that 32 ms must not glide on
        // the landed canvas: its entry state is the old slide's, and the
        // landing would shift the windows by the first slide a second time.
        // The close is taken now, and the new slide opens fresh.
        if (slideCloseTimer.running) {
            slideCloseTimer.stop();
            visible = false;
            quiet = false;
        }
        if (!visible) {
            // The quiet scene opens instantly, opaque: KWin composites the
            // scene's framebuffer over black, so a fade-in here would flash
            // black, and at 1:1 the scene and the desktop it covers are the
            // same picture - the thumbnails over the real windows at the
            // same pixels - so the seam needs no bridging.
            sceneFadeAnim.stop();
            sceneFade = 1;
            open(true);
            slideToX = viewX;
            slideToY = viewY;
            slideWarm = true;
            dbg("slide", "quiet open, gliding " + panDuration + "ms after the first paint");
        }
        return true;
    }

    // The animation has arrived: the destination becomes this activity's
    // viewport. Every shown window is written once, where it sits on the
    // plane relative to its activity's frames. Writing a geometry makes its
    // entry absorb the move as a delta, so nothing may read an entry after
    // writing it. Windows the canvas does not show ride with the viewport as
    // under a commit. All of it happens while the thumbnails still cover the
    // screen.
    function endSlide() {
        if (!quiet) return;
        stopClickPan();
        swiping = false;
        dropPassthrough();
        zoom = 1.0;
        const dx = Math.round(slideToX - entryViewX), dy = Math.round(slideToY - entryViewY);
        // The same net as commit: a slide that landed on a non-finite camera
        // must not write non-finite frames.
        if (!Number.isFinite(dx) || !Number.isFinite(dy) || !Number.isFinite(viewX) || !Number.isFinite(viewY)) {
            console.warn("kwin-canvas: refusing a slide landing from a non-finite camera, resetting it (delta was " + dx + "," + dy + ")");
            viewX = entryViewX;
            viewY = entryViewY;
            visible = false;
            quiet = false;
            return;
        }
        targets = copyTargets(entryTargets);
        const cur = targetOf(currentActivity);
        cur.x += dx;
        cur.y += dy;
        const seen = {};
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (e.window.deleted) continue;
            seen[e.window.internalId] = true;
            const t = targetOf(e.activity);
            // Take the new frame position first, as commit does: the write
            // below is this function's own projection of the entry, so the
            // entry must absorb it as no move - a floating window's entry is
            // where the float put it, not where the old frame was.
            const fx = Math.round(e.x - t.x), fy = Math.round(e.y - t.y);
            e.frameX = fx;
            e.frameY = fy;
            const g = e.window.frameGeometry;
            if (g.x !== fx || g.y !== fy) {
                e.window.frameGeometry = Qt.rect(fx, fy, g.width, g.height);
            }
        }
        if (dx !== 0 || dy !== 0) {
            const all = KWin.Workspace.stackingOrder;
            for (let i = 0; i < all.length; ++i) {
                const w = all[i];
                if (seen[w.internalId] || !isViewportWindow(w)) continue;
                const g = w.frameGeometry;
                w.frameGeometry = Qt.rect(g.x - dx, g.y - dy, g.width, g.height);
            }
        }
        viewX = cur.x;
        viewY = cur.y;
        publishGround();
        dbg("slide", "arrived at (" + Math.round(viewX) + "," + Math.round(viewY) + "), geometries written, closing");
        // The close is instant: the canvas's last frame sits exactly over
        // the real windows at the destination (the thumbnails cover them at
        // the same pixels), so cutting to the real desktop is invisible. A
        // fade-out here would run through black and flash.
        // One more paint at the destination before the scene goes: the
        // camera, the targets and the real windows have all just changed in
        // this turn, and a close in the same turn can leave the compositor
        // showing the scene's frame from before them - the slide's last
        // position with black where its frame had left. At the destination
        // the scene is the desktop it covers, so the extra frame is unseen.
        slideCloseTimer.restart();
    }
    Timer {
        id: slideCloseTimer
        interval: 32
        repeat: false
        onTriggered: {
            if (!effect.quiet) return;
            effect.visible = false;
            effect.quiet = false;
        }
    }

    // Jump to the destination and settle now (another action wants the canvas).
    function finishSlide() {
        if (!quiet) return;
        slideAnim.stop();
        endSlide();
    }

    ParallelAnimation {
        id: slideAnim
        // Leaps off at once and lands with a hair of carry (a 3% OutBack):
        // the old in-out curve had covered 5% of the way at 50 ms, so every
        // fly seemed to hesitate before it went. This one is past half by then.
        NumberAnimation { target: effect; property: "viewX"; to: effect.slideToX; duration: effect.slideMs; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
        NumberAnimation { target: effect; property: "viewY"; to: effect.slideToY; duration: effect.slideMs; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
        onFinished: effect.endSlide()
    }

    NumberAnimation {
        id: sceneFadeAnim
        target: effect
        property: "sceneFade"
        duration: effect.sceneFadeMs
        easing.type: Easing.InOutCubic
    }

    // Pan by one step in a direction (dx, dy in {-1, 0, 1}): the camera moves
    // that way. Closed, it is a slide; open, the camera springs one step.
    function panStepBy(dx, dy) {
        if (canvasOpen) { panKey(dx, dy); return; }
        const st = panStep();
        slide(dx * st.x, dy * st.y);
    }

    // Touchpad swipe: the desktop follows the fingers, then settles one step
    // in the swipe's direction, or slides back if the swipe is cancelled.
    // The fingers move the content, so the camera goes the other way.
    property real swipeBaseX: 0
    property real swipeBaseY: 0
    property bool swiping: false
    function swipeProgress(dx, dy, p) {
        if (!swiping) {
            if (p <= 0) return;
            if (!beginSlide()) return;
            slideAnim.stop();
            swipeBaseX = viewX;
            swipeBaseY = viewY;
            swiping = true;
        }
        const st = panStep();
        p = Math.max(0, Math.min(1, p));
        viewX = swipeBaseX - dx * st.x * p;
        viewY = swipeBaseY - dy * st.y * p;
    }
    function swipeEnd(dx, dy, ok) {
        if (!swiping) return;
        swiping = false;
        const st = panStep();
        slideToX = ok ? swipeBaseX - dx * st.x : swipeBaseX;
        slideToY = ok ? swipeBaseY - dy * st.y : swipeBaseY;
        slideAnim.restart();
    }

    // The finger count is copied out of the configuration so the handlers
    // are re-registered only when it changes, not on every reconfigure.
    property int swipeFingers: 0
    function readSwipeFingers() {
        const n = Number(configuration.PanSwipeFingers) || 0;
        if (n !== swipeFingers) swipeFingers = n;
    }
    Instantiator {
        // Four handlers, one per direction, for the configured finger count.
        model: {
            const n = effect.swipeFingers;
            if (n < 3) return [];
            return [{ f: n, d: KWin.SwipeGestureHandler.Left,  dx: -1, dy: 0 },
                    { f: n, d: KWin.SwipeGestureHandler.Right, dx: 1,  dy: 0 },
                    { f: n, d: KWin.SwipeGestureHandler.Up,    dx: 0,  dy: -1 },
                    { f: n, d: KWin.SwipeGestureHandler.Down,  dx: 0,  dy: 1 }];
        }
        delegate: KWin.SwipeGestureHandler {
            required property var modelData
            direction: modelData.d
            fingerCount: modelData.f
            deviceType: KWin.SwipeGestureHandler.Touchpad
            onProgressChanged: effect.swipeProgress(modelData.dx, modelData.dy, progress)
            onActivated: effect.swipeEnd(modelData.dx, modelData.dy, true)
            onCancelled: effect.swipeEnd(modelData.dx, modelData.dy, false)
        }
    }

    // The activation fly: the desktop slides until the window is wholly in
    // view, at the pan that leaves the most of the other windows in view for
    // the least movement - not always centred, so a desk keeps its shape.
    function flyToWindow(w) {
        const t = peekTarget(activityOf(w));
        const f = w.frameGeometry;
        const rect = { x: f.x + t.x, y: f.y + t.y, width: f.width, height: f.height };
        // The activation fly keeps the whole neighbourhood in view: the
        // focused window lands with its cluster around it, not pinned at
        // the screen edge (the plain least-pan parked the window at the
        // edge with the cluster just outside).
        const others = [];
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (e.window === w) continue;
            others.push({ x: e.x, y: e.y, width: e.width, height: e.height });
        }
        const d = smartPan(rect, others, 24);
        if (d.dx !== 0 || d.dy !== 0) slideTo(d.dx, d.dy);
    }
    // The entry a window is drawn from, or null.
    function entryFor(w) {
        for (let i = 0; i < entries.length; ++i) if (entries[i].window === w) return entries[i];
        return null;
    }
    // Fly the camera so the window is wholly in view, centred on the screen
    // the pointer is on (the swap's flight, the hover's nudge).
    function flyToEntry(e, rate) {
        if (!e) return;
        const others = [];
        for (let i = 0; i < entries.length; ++i) {
            if (entries[i] === e) continue;
            others.push({ x: entries[i].x, y: entries[i].y, width: entries[i].width, height: entries[i].height });
        }
        const d = smartPan({ x: e.x, y: e.y, width: e.width, height: e.height }, others, 24);
        dbg("camGo", "flyToEntry " + e.window.caption + " d=(" + Math.round(d.dx) + "," + Math.round(d.dy) + ")");
        camGo(zoom, viewX + d.dx, viewY + d.dy, undefined, undefined, rate);
    }

    Connections {
        target: KWin.Workspace
        function onWindowActivated(w) {
            // Remember the focus for the cluster tour's destination.
            if (w && !w.deleted) { focusAt[w.internalId] = Date.now(); }
            // Open: a raise (pass-through clicks) restacks the thumbnails.
            // The plane transform is only ever live while open, so the
            // on-screen test below always sees geometry as drawn.
            if (effect.visible) { Qt.callLater(effect.resync); return; }
            if (!effect.configuration.FollowActivation) return;
            if (!effect.isFlyableWindow(w)) return;
            const g = w.frameGeometry;
            // A focused window must be wholly on screen: an intersection is
            // not enough - one hanging off an edge is exactly what a focus
            // must not leave behind. Fully inside, nothing moves.
            const vs = KWin.Workspace.virtualScreenGeometry;
            if (g.x >= vs.x && g.y >= vs.y && g.x + g.width <= vs.x + vs.width && g.y + g.height <= vs.y + vs.height) return;
            // The hand is on the pointer: remember the window, and the release
            // handler flies once the buttons are up - the opening canvas would
            // grab the gesture mid-click. A click on an already-active window
            // raises no activation; the plugin's click publication covers that
            // half, so the two meet in the same release handler. Without a
            // button down (Alt-Tab, the task bar) the fly takes a turn of its
            // own, so the activation finishes first.
            if (effect.pointerButtons !== 0) { effect.pendingFly = w; return; }
            Qt.callLater(function () { if (!w.deleted) effect.flyToWindow(w); });
        }
        function onActivitiesChanged(id) { Qt.callLater(effect.activitiesChanged); }
        // App popups come and go with these too; resync() refreshes them.
        function onWindowAdded(w) { effect.watchWindow(w); Qt.callLater(effect.refreshDesktopWindow); if (effect.visible) Qt.callLater(effect.resync); }
        function onWindowRemoved(w) { if (w) { delete effect.focusAt[w.internalId]; delete effect.watchedWindows[w.internalId]; delete effect.planeRestore[w.internalId]; delete effect.holdTrack[w.internalId]; delete effect.dirtyWindows[w.internalId]; } Qt.callLater(effect.refreshDesktopWindow); if (effect.visible) Qt.callLater(effect.resync); }
        // Switching activities at 1:1 switches viewport: the ground follows.
        function onCurrentActivityChanged(id) {
            if (effect.refreshActivities()) effect.ensureTargets();
            // A focus fly that crossed activities waits for this signal, and
            // the canvas may still be visible (a smooth close is mid-flight):
            // take the window before any early return, or the focus waits for
            // the next activity switch.
            const w = effect.pendingFocus;
            effect.pendingFocus = null;
            if (!effect.visible) {
                const t = effect.targetOf(KWin.Workspace.currentActivity || "");
                effect.viewX = t.x;
                effect.viewY = t.y;
                effect.publishGround();
            }
            if (w && !w.deleted) KWin.Workspace.activeWindow = w;
        }
        // Another desktop's windows are a different set on the same plane.
        function onCurrentDesktopChanged() { if (effect.visible) Qt.callLater(effect.resync); }
        // A hotplug, a resolution change, a rearrange or a virtual output
        // coming or going: the layout the frames and the backdrop tiles are
        // read from has changed.
        function onScreensChanged() {
            effect.screensRev++;
            if (effect.visible) Qt.callLater(effect.resync);
        }
        function onVirtualScreenGeometryChanged() { effect.screensRev++; }
    }

    // ---- shortcuts ---------------------------------------------------------
    KWin.ShortcutHandler {
        name: "Toggle Canvas"
        text: "Canvas: step out to the canvas, or enter the location in view"
        sequence: effect.configuration.ToggleShortcut
        onActivated: effect.toggle()
    }
    KWin.ShortcutHandler {
        name: "Canvas Switcher"
        text: "Canvas: the switcher - the whole plane as a map; hold the chord and step with Tab, release or press Enter to enter"
        sequence: effect.configuration.SwitcherShortcut
        onActivated: { effect.switcherFromChord = true; effect.switcherCluster = false; effect.switcherModMask = effect.modMaskOf(effect.configuration.SwitcherShortcut); effect.switcherToggle() }
    }
    KWin.ShortcutHandler {
        name: "Canvas Switcher Alternate"
        text: "Canvas: the cluster switcher - steps among the windows of the cluster the eye is on, fitted to it (bind over KWin's own Alt+Tab)"
        sequence: effect.configuration.SwitcherAltShortcut
        onActivated: { effect.switcherFromChord = true; effect.switcherCluster = true; effect.switcherModMask = effect.modMaskOf(effect.configuration.SwitcherAltShortcut); effect.switcherToggle() }
    }
    KWin.ShortcutHandler {
        name: "Canvas Home"
        text: "Canvas: return this activity to the origin"
        sequence: effect.configuration.HomeShortcut
        onActivated: {
            if (effect.quiet) { if (effect.grasp) effect.graspEnd(); else effect.finishSlide(); }
            if (effect.visible) { effect.home(); return; }
            effect.open();
            const t = effect.targetOf(effect.currentActivity);
            t.x = 0;
            t.y = 0;
            effect.commit(null);
        }
    }
    // The in-canvas actions as global shortcuts too, with no default chord,
    // so they can be bound in System Settings > Shortcuts > KWin. They act
    // only while the canvas is open.
    KWin.ShortcutHandler { name: "Canvas Apply";    text: "Canvas: apply and close";           sequence: ""; onActivated: if (effect.canvasOpen) effect.commit(null) }
    KWin.ShortcutHandler { name: "Canvas Cancel";   text: "Canvas: cancel";                    sequence: ""; onActivated: if (effect.canvasOpen) effect.cancel() }
    KWin.ShortcutHandler { name: "Canvas Fit";      text: "Canvas: zoom to fit";               sequence: ""; onActivated: if (effect.canvasOpen) effect.zoomExtents(true) }
    KWin.ShortcutHandler { name: "Canvas Origin";   text: "Canvas: camera to the origin";      sequence: ""; onActivated: if (effect.canvasOpen) effect.origin() }
    KWin.ShortcutHandler { name: "Canvas Zoom In";  text: "Canvas: zoom in";                   sequence: ""; onActivated: if (effect.canvasOpen) effect.camZoomTo(effect.zoom * effect.zoomStep, effect.cursorScreen().x, effect.cursorScreen().y) }
    KWin.ShortcutHandler { name: "Canvas Zoom Out"; text: "Canvas: zoom out";                  sequence: ""; onActivated: if (effect.canvasOpen) effect.camZoomTo(effect.zoom / effect.zoomStep, effect.cursorScreen().x, effect.cursorScreen().y) }
    // Pan at 1:1 by one step (a slide), or move the open canvas's camera.
    KWin.ShortcutHandler { name: "Canvas Pan Left";  text: "Canvas: pan left";  sequence: effect.configuration.PanLeftShortcut;  onActivated: effect.panStepBy(-1, 0) }
    KWin.ShortcutHandler { name: "Canvas Pan Right"; text: "Canvas: pan right"; sequence: effect.configuration.PanRightShortcut; onActivated: effect.panStepBy(1, 0) }
    KWin.ShortcutHandler { name: "Canvas Pan Up";    text: "Canvas: pan up";    sequence: effect.configuration.PanUpShortcut;    onActivated: effect.panStepBy(0, -1) }
    KWin.ShortcutHandler { name: "Canvas Pan Down";  text: "Canvas: pan down";  sequence: effect.configuration.PanDownShortcut;  onActivated: effect.panStepBy(0, 1) }

    // ---- screen edges ------------------------------------------------------
    // The Screen Edges settings page lists this effect (X-KWin-Border-Activate)
    // and writes the chosen corners into BorderActivate. One handler per edge;
    // pushing the pointer into it toggles the canvas, like Overview's hot corner.
    Instantiator {
        model: effect.configuration.BorderActivate
        delegate: KWin.ScreenEdgeHandler {
            required property int modelData
            enabled: true
            edge: modelData
            // A held pan button parks the pointer at the edge on purpose:
            // pushing into the border to pan the canvas must not toggle it.
            onActivated: {
                if (!effect.navHeld) effect.toggleFromBorder(modelData);
            }
        }
    }
    Instantiator {
        model: effect.configuration.TouchBorderActivate
        delegate: KWin.ScreenEdgeHandler {
            required property int modelData
            enabled: true
            mode: KWin.ScreenEdgeHandler.Touch
            edge: modelData
            onActivated: effect.toggle()
        }
    }

    // ---- nested test harness -----------------------------------------------
    // The harness writes DebugCommand + DebugSeq into kwinrc and calls reconfigure.
    function runDebug(cmd) {
        const a = cmd.trim().split(/\s+/);
        // A malformed command must not touch the plane: the geometry-writing
        // commands all take numbers, and a non-number would land as NaN in a
        // window's committed position.
        const numok = (i) => Number.isFinite(Number(a[i]));
        refreshActivities();
        switch (a[0]) {
        case "open": open(); break;
        case "commit": commit(null); break;
        case "cancel": doCancel(); break;
    case "release": sceneGestures = 0; break; // the stuck-gesture emergency: the parked close fires at once
        case "toggle": toggle(); break;
        case "home": home(); break;
        case "reloadstate": loadClusterState(); loadBookmarks(); break;
        case "bookmark": {
            // bookmark set N | bookmark go N: the keys' two verbs, for a script.
            if (a[1] === "set" && numok(2)) bookmarkSet(Number(a[2]));
            else if (a[1] === "go" && numok(2)) bookmarkGo(Number(a[2]));
            break;
        }
        case "origin": origin(); break;
        case "extents": zoomExtents(); break;
        case "pan": if (numok(1) && numok(2)) panBy(Number(a[1]), Number(a[2])); break;
        case "panpx": if (numok(1) && numok(2)) { viewX -= Number(a[1]) / zoom; viewY -= Number(a[2]) / zoom; } break; // screen pixels at the current zoom, no torch: the tests' exact pan
        case "zoom": {
            if (!numok(1)) break;
            const p = a.length >= 4 && numok(2) && numok(3) ? Qt.point(Number(a[2]), Number(a[3])) : cursorScreen();
            setZoom(Number(a[1]), p);
            break;
        }
        case "shift": if (numok(1) && numok(2)) shiftAll(Number(a[1]), Number(a[2])); break;
        case "slide": if (numok(1) && numok(2)) slide(Number(a[1]), Number(a[2])); break;
        case "enter": enterHere(); break;
        case "panstep": if (numok(1) && numok(2)) panStepBy(Number(a[1]), Number(a[2])); break;
        case "swipe": {
            // swipe DX DY PROGRESS | swipe DX DY end | swipe DX DY cancel
            if (!numok(1) || !numok(2)) break;
            if (a[3] === "end") swipeEnd(Number(a[1]), Number(a[2]), true);
            else if (a[3] === "cancel") swipeEnd(Number(a[1]), Number(a[2]), false);
            else if (numok(3)) swipeProgress(Number(a[1]), Number(a[2]), Number(a[3]));
            break;
        }
        case "drag": if (numok(1) && numok(2) && numok(3)) { beginDrag(Number(a[1])); dragEntry(Number(a[1]), Number(a[2]), Number(a[3])); } break;
        case "cdrag": if (numok(1) && numok(2) && numok(3)) { beginClusterDrag(Number(a[1])); dragCluster(Number(a[1]), Number(a[2]), Number(a[3])); endDrag(); } break;
        case "resize": if (numok(1) && numok(2) && numok(3)) requestSize(Number(a[1]), Number(a[2]), Number(a[3]), false, false); break;
        case "resetview": {
            // 1:1 only: forget the pan history so canvas == frame for this activity.
            if (visible) break;
            viewX = 0; viewY = 0;
            targets[currentActivity] = { x: 0, y: 0 };
            break;
        }
        case "placeby": {
            // placeby CAPTION_SUBSTR X Y [W H]: position (and size) an entry by caption.
            if (!numok(2) || !numok(3)) break;
            for (let i = 0; i < entries.length; ++i) {
                const e = entries[i];
                if (e.window.caption.indexOf(a[1]) === -1) continue;
                e.x = Number(a[2]); e.y = Number(a[3]);
                if (a.length >= 6 && numok(4) && numok(5)) requestSize(i, Number(a[4]), Number(a[5]), false, false);
                revision++;
                break;
            }
            break;
        }
        case "place": {
            if (!numok(1) || !numok(2) || !numok(3)) break;
            const e = entries[Number(a[1])];
            if (e) { e.x = Number(a[2]); e.y = Number(a[3]); revision++; }
            break;
        }
        case "frames": {
            // frames DX DY [activityIndex]
            if (!numok(1) || !numok(2)) break;
            const id = a.length >= 4 && numok(3) ? activityIds[Number(a[3])] : currentActivity;
            dragTarget(id, Number(a[1]), Number(a[2]));
            break;
        }
        case "pick": if (numok(1)) pick(entries[Number(a[1])]); break;
        case "focus": if (numok(1)) focusWindow(entries[Number(a[1])]); break;
        case "goto": if (numok(1)) gotoActivity(activityIds[Number(a[1])]); break;
        case "zoomto": if (numok(1)) zoomToActivity(activityIds[Number(a[1])]); break;
        case "newactivityat": if (numok(1)) newActivityAt(entries[Number(a[1])]); break;
        case "activate": {
            const all = KWin.Workspace.stackingOrder;
            for (let i = 0; i < all.length; ++i) {
                if (all[i].caption.indexOf(a[1]) !== -1) { KWin.Workspace.activeWindow = all[i]; break; }
            }
            break;
        }
        case "fullscreen": {
            // fullscreen CAPTION [on|off]: the scripting Window's fullScreen
            // is writable, which is how a scenario puts a fullscreen app up.
            for (let i = 0; i < entries.length; ++i) {
                const w = entries[i].window;
                if (w.caption.indexOf(a[1]) !== -1) { w.fullScreen = a[2] !== "off"; break; }
            }
            break;
        }
        case "activity": if (numok(1)) KWin.Workspace.currentActivity = activityIds[Number(a[1])]; break;
        case "addactivity": addActivity(); break;
        case "rmactivity": if (numok(1)) removeActivity(activityIds[Number(a[1])]); break;
        case "hide": case "show": {
            // hide|show ACTIVITY_INDEX [SCREEN_INDEX]
            const screens = KWin.Workspace.screens;
            const s = a.length >= 3 ? screens[Number(a[2])] : KWin.Workspace.activeScreen;
            setHidden(activityIds[Number(a[1])], s, a[0] === "hide");
            break;
        }
        case "activities": {
            // Raw ids as KWin reports them, and each window's list.
            let s = "kwin-canvas activities: current=" + JSON.stringify(KWin.Workspace.currentActivity) + " all=" + JSON.stringify(Array.prototype.slice.call(KWin.Workspace.activities));
            const all = KWin.Workspace.stackingOrder;
            for (let i = 0; i < all.length; ++i) s += "\n  " + all[i].caption + " " + JSON.stringify(Array.prototype.slice.call(all[i].activities));
            console.log(s);
            break;
        }
        case "list": {
            const all = KWin.Workspace.stackingOrder;
            let s = "kwin-canvas windows:";
            for (let i = 0; i < all.length; ++i) {
                const w = all[i]; const g = w.frameGeometry;
                s += "\n  " + (isCanvasWindow(w, true) ? "*" : " ") + " " + w.caption + " frame=(" + g.x + "," + g.y + " " + g.width + "x" + g.height + ") activity=" + (w.activities.length === 0 ? "all" : labelOf(activityOf(w)));
            }
            console.log(s);
            break;
        }
        case "locate": {
            // locate TEXT: the global centre of the visible control on the
            // primary screen whose text is TEXT, for tests that click it.
            const sv = viewForScreen(primaryScreen);
            const root = sv ? sv.rootItem : null;
            const text = a.slice(1).join(" ");
            const it = root ? findLabelled(root, text) : null;
            const p = it ? it.mapToItem(root, it.width / 2, it.height / 2) : null;
            console.log("kwin-canvas locate " + text + " = " + (p ? Math.round(p.x + root.sg.x) + " " + Math.round(p.y + root.sg.y) : "none"));
            break;
        }
        case "help": helpOpen = !helpOpen; break;
        case "select": selectOnly(entries[Number(a[1])]); break;
        case "selectadd": selectAdd(entries[Number(a[1])]); break;
        case "selecttoggle": selectToggle(entries[Number(a[1])]); break;
        case "clearsel": clearSelection(); break;
        case "pin": pinEntries([entries[Number(a[1])]]); break;
        case "unpin": unpinEntries([entries[Number(a[1])]]); break;
        case "unpinall": pinned = {}; for (let i = 0; i < entries.length; ++i) setPinned(entries[i].window, false); break;
        case "arrange": arrange(a[1], Number(a[2]), Number(a[3])); break;
        case "tidy": tidy(); break;
        case "undo": undo(); break;
        case "snap": {
            const on = a[2] === "on";
            if (a[1] === "edges") snapEdges = on; else if (a[1] === "corners") snapCorners = on; else if (a[1] === "grid") snapGrid = on;
            break;
        }
        case "begindrag": beginDrag(Number(a[1])); break;
        case "sendto": sendTo(a[1] === "none" || !numok(1) ? null : activityIds[Number(a[1])]); break;
        case "marquee": if (numok(1) && numok(2) && numok(3) && numok(4)) selectInRect(Number(a[1]), Number(a[2]), Number(a[3]), Number(a[4])); break;
        case "state": break;
        case "verbose": verb = a[1] !== "off"; publishVerbose(); break;
        case "threads": {
            // threads: every stretch of every thread the view is about to
            // draw, with its z - the wiring of the weave, for when the
            // picture and the model disagree.
            const g = actionScreen().geometry;
            const spans = clusterThreads(g.x, g.y);
            let s = "kwin-canvas threads: " + spans.length;
            for (let i = 0; i < spans.length; ++i) {
                const t = spans[i];
                s += "\nkwin-canvas thread: " + Math.round(t.x1) + "," + Math.round(t.y1) + " -> " + Math.round(t.x2) + "," + Math.round(t.y2) + " z=" + t.z.toFixed(3) + (t.lit ? " lit" : "");
            }
            console.log(s);
            break;
        }
        case "switch": switcherFromChord = false; switcherCluster = false; switcherToggle(); break;
        case "switchcluster": switcherFromChord = false; switcherCluster = true; switcherToggle(); break;
        case "clusterjump": if (numok(1)) clusterJumpTo(Number(a[1])); break;
        case "clustername": {
            // clustername N name...: the badge's number names that cluster.
            if (numok(1)) {
                const ci = Number(a[1]) - 1;
                if (ci >= 0 && ci < clusters.length) {
                    clusterNames[clusterFingerprint(clusters[ci])] = a.length > 2 ? a.slice(2).join(" ") : "";
                    saveClusterState();
                    clusterRev++;
                }
            }
            break;
        }
        default: console.warn("kwin-canvas: unknown debug command", cmd);
        }
        logState();
    }

    function findLabelled(item, text) {
        if (!item || !item.visible) return null;
        if (item.text === text) return item;
        const ch = item.children;
        for (let i = 0; i < ch.length; ++i) {
            const f = findLabelled(ch[i], text);
            if (f) return f;
        }
        return null;
    }

    function logState() {
        let s = "kwin-canvas state visible=" + visible + (quiet ? " quiet" : "") + (grasp ? " grasp" : "") + (passthroughLive ? " passthrough" : "") + (planeLive ? " plane" : "") + " zoom=" + zoom.toFixed(4) + " view=(" + viewX.toFixed(1) + "," + viewY.toFixed(1) + ") activity=" + labelOf(currentActivity) + " entries=" + entries.length
            + " popups=" + appPopups.length + " menus=" + canvasMenus + " nav=" + (navHeld ? "hold" : "-") + " snap=" + (snapEdges ? "E" : "-") + (snapCorners ? "C" : "-") + (snapGrid ? "G" : "-")
            + " screens=" + KWin.Workspace.screens.length + " backdrop=" + backdropLayers
            + " cam=" + (camHasGoal ? "goal" : (camLive() ? "glide" : "-"))
            + " focus=" + (focusEntry ? JSON.stringify(focusEntry.window.caption) : "-")
            + " clusters=" + clusters.length + " cluster=" + (clusterIndex() >= 0 ? "#" + (clusterIndex() + 1) : "-")
            + " draglag=" + Math.round(Math.sqrt(dragLagX * dragLagX + dragLagY * dragLagY)) + " lean=" + dragLean.toFixed(2)
            + " idle=" + (passthroughIdle ? "1" : "0")
            + " seam=" + (seamPark ? "1" : "0")
            + " graspTarget=" + (graspTarget ? entries.indexOf(graspTarget) : "-")
            + " outcome=" + (grasp ? (zoom < 0.72 ? "world" : "land") : "-")
            + " rest=" + (restStart ? "1" : "0")
            + " moves=" + Object.keys(entryAnims).length
            + " dragraw=" + Object.keys(dragRaw).length
            + " undo=" + undoStack.length
            + " snaps=" + snapCatches
            + " throw=" + (lastThrow ? Math.round(lastThrow.dx) + "," + Math.round(lastThrow.dy) : "-")
            + " bookmarks=" + Object.keys(bookmarks).length
            + " deskwin=" + Object.keys(desktopWindows).length
            + " hoverDelay=" + (configuration.HoverDelay === undefined ? "undef" : configuration.HoverDelay)
            + " map=" + (mapMinimap ? "minimap" : "-")
            + " ql=" + ql
           
            + " cpu=" + Math.round(cpuBusy)
            + " gpu=" + Math.round(gpuBusy)
            + " mem=" + Math.round(memBusy)
            + " active=" + (KWin.Workspace.activeWindow ? JSON.stringify(KWin.Workspace.activeWindow.caption) : "none");
        const ids = activityIds, screens = KWin.Workspace.screens;
        for (let i = 0; i < screens.length; ++i) {
            const g = screens[i].geometry;
            s += "\n  screen[" + i + "] " + screens[i].name + " " + g.width + "x" + g.height + "+" + g.x + "+" + g.y;
        }
        for (let i = 0; i < ids.length; ++i) {
            const t = peekTarget(ids[i]);
            let hidden = "";
            for (let j = 0; j < screens.length; ++j) if (isHidden(ids[i], screens[j])) hidden += (hidden ? "," : "") + screens[j].name;
            s += "\n  {" + i + "} " + labelOf(ids[i]) + " target=(" + t.x.toFixed(0) + "," + t.y.toFixed(0) + ")" + (hidden ? " hidden=" + hidden : "");
        }
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            const g = e.window.frameGeometry;
            const f = floatOf[e.window.internalId];
            const fx = f ? (f.x - (e.x - viewX) * zoom) : 0, fy = f ? (f.y - (e.y - viewY) * zoom) : 0;
            s += "\n  [" + i + "] " + (isSelected(e) ? "*" : " ") + e.window.caption + " canvas=(" + e.x.toFixed(0) + "," + e.y.toFixed(0) + " " + e.width + "x" + e.height + ") frame=(" + g.x + "," + g.y + ")" + (Math.abs(fx) > 0.4 || Math.abs(fy) > 0.4 ? " float=(+" + fx.toFixed(0) + ",+" + fy.toFixed(0) + ")" : "") + " z=" + windowZ(e) + " activity=" + labelOf(e.activity);
        }
        for (let i = 0; i < clusters.length; ++i) {
            const mem = [];
            for (let k = 0; k < clusters[i].ids.length; ++k) {
                for (let j = 0; j < entries.length; ++j) if (entries[j].window.internalId === clusters[i].ids[k]) { mem.push(j); break; }
            }
            const nm = clusterNames[clusterFingerprint(clusters[i])];
            s += "\n  c" + i + ": " + mem.join(" ") + (nm ? " " + JSON.stringify(nm) : "");
        }
        console.log(s);
    }

    // A closed canvas never carries a flight: whatever closed it, the
    // camera's spring must not freeze mid-air with a live goal (the physics
    // timer only runs while the canvas is visible, so a goal set at the
    // close would hang until the next open resumed it mid-flight).
    onVisibleChanged: {
        if (!visible) camStop();
    }

    onConfigurationChanged: {
        hotRev = Number(configuration.HotRev) || 0;
        rebuildBindings();
        readSwipeFingers();
        publishHold();
        refreshGroundWallpaper();
        Qt.callLater(recluster);
        const seq = configuration.DebugSeq;
        if (seq !== lastDebugSeq) {
            lastDebugSeq = seq;
            const cmd = configuration.DebugCommand;
            if (cmd && cmd.length > 0) runDebug(cmd);
        }
    }

    Component.onCompleted: {
        rebuildBindings();
        readSwipeFingers();
        loadHiddenFrames();
        loadClusterState();
        loadBookmarks();
        watchAllWindows();
        refreshActivities();
        refreshDesktopWindow();
        lastDebugSeq = configuration.DebugSeq;
        publishHold();
        refreshGroundWallpaper();
        // The last committed viewport: the plane comes back where it was.
        viewX = Number(configuration.ViewX) || 0;
        viewY = Number(configuration.ViewY) || 0;
        const t0 = targets[currentActivity];
        if (t0) { t0.x = viewX; t0.y = viewY; }
        // The harness can write a command before the QML completes: KWin
        // reports the effect loaded first, and a reconfigure that lands
        // before onCompleted never fires onConfigurationChanged. Run the
        // pending command here, once, so the first command of a nest is
        // never lost.
        const cmd = configuration.DebugCommand;
        if (cmd && cmd.length > 0) runDebug(cmd);
        if (configuration.AutoActivate) {
            Qt.callLater(open);
        }
    }

    // ---- controls ----------------------------------------------------------
    // Every draggable thing on the canvas is a Grip and every clickable thing
    // is an IconButton. Both count themselves into the view's hoverCount so
    // the pan handler stands down while the pointer is over them, both set
    // their own cursor, and both are disabled while Space is held.

    // The scene's shared components live in ui.qml (the hot-reload side).
    delegate: Loader {
        source: Qt.resolvedUrl("ui.qml") + (effect.hotRev > 0 ? "?rev=" + effect.hotRev : "")
        // The loaded scene must own the keyboard focus: KWin delivers the
        // scene's keys to the QuickView's active focus item, and a static
        // focus binding inside a loaded item does not take it - the split
        // taught us that the hard way. Re-assert on every load.
        onLoaded: item.forceActiveFocus();
    }
}


