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
    readonly property bool canvasOpen: visible && !quiet
    // Pass-through: the optional binary plugin is live while the canvas is
    // open. Every key, and every click, drag and wheel over a window, goes
    // to the real window; the ground, the decorations, the frame tags and
    // the toolbar stay the canvas's. Live once the plugin has answered the
    // probe for this opening; the camera is published to it on every change.
    readonly property bool passthrough: configuration.Passthrough !== false && !planeInput
    property bool passthroughLive: false
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
    // The swap buttons: while the canvas modifier is held, a press flies
    // between the two most recent windows.
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
    onCanvasHoldChanged: {
        if (canvasHold) {
            // Held in the open overworld it is navigation only: the views
            // count it into navHeld, and releasing does nothing.
            if (!visible) graspStart();
        } else if (grasp) {
            graspEnd();
        }
    }
    function graspStart() {
        if (visible) return;
        grasp = true;
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
        if (!quiet || !grasp) { grasp = false; return; }
        if (sceneGestures > 0) {
            deferredClose = graspEnd;
            return;
        }
        grasp = false;
        // The swap moved the focus: the location opens where the swapped-to
        // window is, focused on it, as a pick would place it - the frames,
        // their windows and the wallpaper slide to it and nothing else moves.
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
        // fades in, and the map morphs from the full sheet into the corner
        // lens. Zoomed in, the release commits the location, as it always
        // has - a pan during the hold is the location's new viewport.
        if (zoom < 0.72) {
            quiet = false;
            chromeFade = 0;
            welcomeAnim.restart();
            thumbOpacity = 1;
            if (passthrough) probeCall.call();
            return;
        }
        commit(null);
    }

    // SwapButton while the modifier is held: fly between the two most recent
    // windows, an Alt-Tab on the plane. The camera springs to the other
    // window, the focus follows, and the release opens the location there.
    function swapWindow() {
        if (!grasp && !canvasOpen) return;
        if (!grasp) {
            // In the overworld the swap tours the clusters - the bracket
            // keys' own travel, at the speed of the click.
            clusterTravel(1);
            return;
        }
        let target = null;
        for (let i = 0; i < focusHistory.length; ++i) {
            const w = focusHistory[i];
            if (!w || w.deleted) continue;
            if (w !== KWin.Workspace.activeWindow) { target = w; break; }
        }
        if (!target) return;
        KWin.Workspace.activeWindow = target;
        // The swap's own flight is the move; the activation it caused must
        // not fly again on the release, or the two flights fight and the
        // windows jump.
        pendingFly = null;
        clickedWindow = null;
        const e = entryFor(target);
        if (e) flyToEntry(e, 2.0);
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
        if (entries.length === 0) return;
        let idx = -1;
        for (let i = 0; i < entries.length; ++i) if (isSelected(entries[i])) { idx = i; break; }
        const n = idx < 0 ? (dir > 0 ? 0 : entries.length - 1) : (idx + dir + entries.length) % entries.length;
        selectOnly(entries[n]);
        bringIntoView(entries[n]);
    }

    // Pan the camera the least that puts the window wholly on the screen the
    // pointer is on, and - among the pans that keep it so - the one that
    // leaves the most of the other windows in view. The natural stopping
    // points are the alignments that bring the window's edges, or a
    // neighbour's, onto the screen's; the least movement wins the ties.
    function bringIntoView(e) {
        const others = [];
        for (let i = 0; i < entries.length; ++i) {
            if (entries[i] === e) continue;
            others.push({ x: entries[i].x, y: entries[i].y, width: entries[i].width, height: entries[i].height });
        }
        const d = smartPan({ x: e.x, y: e.y, width: e.width, height: e.height }, others, 24);
        if (d.dx !== 0 || d.dy !== 0) camGo(zoom, viewX + d.dx, viewY + d.dy);
    }

    // The best camera pan for a canvas rect: the least movement that keeps
    // it wholly inside the screen the pointer is on, with a margin. The
    // minimal pan is also the least disruption to the rest of the desk - the
    // other windows stay in view precisely because nothing moved more than
    // it had to. A rect larger than the screen is left- and top-aligned.
    function smartPan(rect, others, pad) {
        return Logic.smartPan(rect, actionScreen().geometry, viewX, viewY, zoom, pad);
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

    property int lastDebugSeq: 0

    // The float: the windows hover in Z as the camera steps out of the
    // location, so the overworld feels alive - a gentle per-window bob,
    // each at its own phase, ramping in with the zoom-out.
    readonly property real floatAmt: windowPhysics && !quiet && visible ? Math.min(1, Math.max(0, (1 - zoom) * 3)) : 0

    // The grasp's map: which window the pointer rests on, and the jump.
    property int graspHover: 0
    property int graspHoverIndex: -1
    function graspPick(x, y) {
        const wb = worldBounds();
        const g = actionScreen().geometry;
        const w = g.width - 48, h = g.height - 48;
        const sc = Math.min((w - 12) / wb.width, (h - 12) / wb.height);
        const ox = 24 + (w - wb.width * sc) / 2;
        const oy = 24 + (h - wb.height * sc) / 2;
        const cx = wb.x + (x - ox) / sc, cy = wb.y + (y - oy) / sc;
        for (let i = entries.length - 1; i >= 0; --i) {
            const e = entries[i];
            if (cx >= e.x && cx < e.x + e.width && cy >= e.y && cy < e.y + e.height) return i;
        }
        return -1;
    }
    function graspJump(x, y) {
        const i = graspPick(x, y);
        if (i < 0) return;
        const e = entries[i];
        noteGesture();
        flyToEntry(e, 2.0);
    }
    function graspJumpTo(i) {
        if (i < 0 || i >= entries.length) return;
        noteGesture();
        flyToEntry(entries[i], 2.0);
    }
    Timer {
        interval: 100
        repeat: true
        running: effect.grasp
        onTriggered: {
            const p = effect.cursorScreen();
            effect.graspHoverIndex = effect.graspPick(p.x, p.y);
            effect.graspHover++;
        }
    }

    // ---- floating windows ----------------------------------------------------
    // A floating window's coordinates on the plane never change - only the
    // hand moves them. Its picture is what floats: whenever the camera
    // would push the window partly off the screen, the picture rides at the
    // screen's edge and, pushed there fast, bounces off the edge with real
    // physics before settling against it; move the camera back and the
    // picture is the window again, at its coordinates. The flag is KWin's
    // own "keep above", repurposed - the title-bar menu's always-visible
    // entry and the canvas agree on what floats - and the caption list
    // persists the choice.
    property var pinned: ({})          // caption -> true, the persisted flag
    property var floatOf: ({})         // window internalId -> { x, y, vx, vy, wasInX, wasInY }, screen px
    property int floatRev: 0
    property real floatPrevViewX: 0
    property real floatPrevViewY: 0
    function isPinnedEntry(e) { return e && e.window && !e.window.deleted && e.window.keepAbove; }
    function loadPinned() {
        const list = configuration.PinnedWindows || [];
        const set = {};
        for (let i = 0; i < list.length; ++i) if (list[i]) set[list[i]] = true;
        pinned = set;
        const all = KWin.Workspace.stackingOrder;
        for (let i = 0; i < all.length; ++i) {
            if (pinned[all[i].caption] && !all[i].keepAbove) all[i].keepAbove = true;
        }
    }
    function savePinned() {
        const list = [];
        for (const k in pinned) list.push(k);
        configuration.PinnedWindows = list;
        configuration.writeConfig();
    }
    function pinEntries(list) {
        for (let i = 0; i < list.length; ++i) {
            const e = list[i];
            if (!e || e.window.deleted) continue;
            if (!e.window.keepAbove) e.window.keepAbove = true;
            pinned[e.window.caption] = true;
        }
        savePinned();
    }
    function unpinEntries(list) {
        let any = false;
        for (let i = 0; i < list.length; ++i) {
            const e = list[i];
            if (!e) continue;
            if (e.window.keepAbove) e.window.keepAbove = false;
            if (delete pinned[e.window.caption]) any = true;
        }
        if (any) savePinned();
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
        const sg = screenAt((e.x - viewX) * zoom, (e.y - viewY) * zoom) || actionScreen();
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
        floatRev++;
    }
    Timer {
        interval: 16
        repeat: true
        running: effect.visible
        onTriggered: effect.floatPinned(interval / 1000)
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
    property bool hoverBrought: false
    property real lastGestureAt: 0
    property bool handGesture: false

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
    // Fly to the next or previous cluster in reading order (top to bottom,
    // left to right), from the one the eye is on. The camera springs to the
    // cluster's centre at the current zoom, the toast names the stop.
    function clusterTravel(dir) {
        if (clusters.length === 0) return;
        const cur = clusterIndex();
        const order = [];
        for (let i = 0; i < clusters.length; ++i) order.push(i);
        order.sort(function (p, q) { return (clusters[p].cy - clusters[q].cy) || (clusters[p].cx - clusters[q].cx); });
        let k = 0;
        if (cur >= 0) {
            const pos = order.indexOf(cur);
            k = (pos + dir + order.length) % order.length;
        } else if (dir < 0) k = order.length - 1;
        travelCluster = order[k];
        const c = clusters[order[k]];
        const g = actionScreen().geometry;
        // The jump leaves the old hover behind: the tour anchors to the
        // destination until the eye settles on something new.
        hoverEntry = null;
        focusEntry = null;
        camGo(zoom, c.cx - (g.x + g.width / 2) / zoom, c.cy - (g.y + g.height / 2) / zoom);
        toast("Cluster " + (k + 1) + " of " + clusters.length);
    }
    // The threads through a cluster, in this screen's coordinates: every
    // window joined to every other, a web in the gaps between them, drawn
    // behind the windows. Re-evaluated with the camera, so the web rides
    // the same motion as its windows.
    function clusterPath(i, sgx, sgy) {
        const c = clusters[i];
        if (!c || c.n < 2) return "";
        const pts = [];
        for (let k = 0; k < c.ids.length; ++k) {
            const e = entryById(c.ids[k]);
            if (!e) continue;
            const idx = entries.indexOf(e);
            const bob = Math.sin(floatRev * 0.035 + idx * 137.508) * 2.4 * floatAmt;
            pts.push({
                x: (e.x + e.width / 2 - viewX) * zoom - sgx,
                y: (e.y + e.height / 2 - viewY) * zoom - sgy + bob
            });
        }
        if (pts.length < 2) return "";
        let s = "";
        for (let a = 0; a < pts.length; ++a) {
            for (let b = a + 1; b < pts.length; ++b) {
                s += "M " + pts[a].x.toFixed(1) + " " + pts[a].y.toFixed(1) + " L " + pts[b].x.toFixed(1) + " " + pts[b].y.toFixed(1) + " ";
            }
        }
        return s;
    }
    function entryById(id) {
        for (let i = 0; i < entries.length; ++i) if (entries[i].window.internalId === id) return entries[i];
        return null;
    }

    // ---- bookmarks -----------------------------------------------------------
    // Saved views on the plane, the desks: the digit keys jump to them and
    // Ctrl+digit saves the current view as one. The one thing virtual
    // desktops had that the plane lacks is a way to name where you were;
    // this is it, and the jump springs like every camera move.
    property var bookmarks: []
    function loadBookmarks() {
        let list = [];
        try { list = JSON.parse(configuration.Bookmarks || "[]"); } catch (err) { list = []; }
        bookmarks = list;
    }
    function saveBookmarks() {
        configuration.Bookmarks = JSON.stringify(bookmarks);
        configuration.writeConfig();
    }
    function gotoBookmark(i) {
        const b = bookmarks[i];
        if (!b) return;
        camGo(b.z || 1, b.x, b.y);
        toast("Spot " + (i + 1) + (b.n ? ": " + b.n : ""));
    }
    function saveBookmark(i) {
        while (bookmarks.length <= i) bookmarks.push(null);
        bookmarks[i] = { n: bookmarks[i] ? bookmarks[i].n : ("Spot " + (i + 1)), x: viewX, y: viewY, z: zoom };
        saveBookmarks();
        toast("Saved spot " + (i + 1));
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
        if (navHeld || closing || canvasMenus > 0 || camLive()) return;
        const p = cursorScreen();
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
        if (e && now - hoverSince >= 200) {
            if (!hoverBrought) {
                hoverBrought = true;
                bringIntoView(e);
            }
            if (focusEntry !== e) {
                focusEntry = e;
            }
        } else if (!e && focusEntry) {
            focusEntry = null;
        }
    }
    Timer {
        interval: 100
        repeat: true
        running: effect.canvasOpen && !effect.closing
        onTriggered: effect.hoverTick()
    }

    // ---- key bindings, from config ------------------------------------------
    // Each entry is a list of Qt key codes parsed from a comma-separated list
    // of Qt key names without the Key_ prefix ("Return,Enter").
    property var bindings: ({})

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
            panHold: buttonsFor(configuration.PanHold),
            hold: buttonsFor(configuration.CanvasHold),
            swap: buttonsFor(configuration.SwapButton)
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
            onFinished: (ret) => effect.setActivityName(modelData, String(ret[0]))
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
            if (!e) { e = makeEntry(w); changed = true; }
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
    function closeWhenClear(fn) {
        if (sceneGestures > 0) { deferredClose = fn; return; }
        fn();
    }
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
    // The pass-through has let go after the idle: the canvas owns the
    // input again, until the pointer's next touch.
    property bool passthroughIdle: false
    // How far the camera has left the location while the keyhole is open
    // (the quiet grasp): 0 at home, growing with the zoom-out and the pan.
    // The skin - the frames, the tags, the threads, the glow - fades in
    // with it, so the keyhole and the overworld are one space wearing one
    // skin, and a transient slide stays the seamless desktop it must be.
    readonly property real quietReveal: {
        effect.zoom; effect.viewX; effect.viewY;
        if (!effect.quiet || !effect.grasp) return 0;
        const t = effect.targetOf(effect.currentActivity);
        const g = effect.actionScreen().geometry;
        const away = Math.hypot(effect.viewX - t.x, effect.viewY - t.y);
        return Math.min(1, Math.max(1 - effect.zoom, away / (Math.max(g.width, g.height) * 1.2)));
    }
    property var pendingFly: null
    // The switcher: the hold's map as a toggle. The chord opens the canvas
    // quietly with the map up; Tab and Shift+Tab step the selection - the
    // camera and the map's highlight follow - Enter enters the chosen
    // window, Esc or the chord again steps back out.
    property bool switcherActive: false
    function switcherToggle() {
        if (switcherActive) {
            switcherActive = false;
            doCancel();
            return;
        }
        if (visible && !quiet) { switcherActive = false; return; }
        if (!visible) open(true);
        switcherActive = true;
        clickPanEntry = null;
        clickPanTimer.stop();
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

    function clampZoom(z) { return Math.max(zoomMin, Math.min(1.0, Number(z))); }

    // Zoom while holding the canvas point under `anchor` (global px) fixed on screen.
    function setZoom(z, anchor) {
        z = clampZoom(z);
        const c = Logic.canvasOf(anchor.x, anchor.y, viewX, viewY, zoom);
        const v = Logic.zoomView(c, anchor.x, anchor.y, z);
        zoom = z;
        viewX = v.x;
        viewY = v.y;
    }

    function panBy(dx, dy) {
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
    }

    // A pan the hand let go of: keep the plane moving the way it was, under
    // friction. dx, dy are the screen pixels the drag covered and ms how long
    // it took, so this is the hand's average velocity - negated, because the
    // pan moved the view the other way (content follows the pointer) - and a
    // flick carries while a slow drag settles at once. The caller has already
    // refused a drag that paused before the release (see the pan handler),
    // which is what lets "drag it where you want it and let go" land exactly
    // where it was put.
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
    }

    // Spring the camera to a scale, and - unless a screen point is given to pin
    // - to a place. Instant when SmoothZoom is off, so a script or a still hand
    // gets exactly what it asked for.
    // The rate the current spring runs at: a multiple of camSpring. The
    // flights (the step in, the double-click's placement, the cancel) run
    // at twice the casual rate, so an enter snaps while a pan glides.
    property real camRate: 1.0
    function camGo(z, goalX, goalY, gx, gy, rate) {
        z = clampZoom(z);
        const pinned = gx !== undefined && gx !== null;
        camStop();
        camRate = rate === undefined ? 1.0 : Math.max(0.25, Number(rate));
        if (!smoothZoom) {
            if (pinned) setZoom(z, Qt.point(gx, gy));
            else { zoom = z; viewX = goalX; viewY = goalY; }
            return;
        }
        const w = camSpring * camRate;
        camGoalZoom = z;
        if (pinned) {
            const c = globalToCanvas(gx, gy);
            camAnchorX = c.x; camAnchorY = c.y; camAnchorGX = gx; camAnchorGY = gy;
            camAnchored = true;
            camGoalX = viewX; camGoalY = viewY;
        } else {
            camAnchored = false;
            camGoalX = goalX; camGoalY = goalY;
            // A push toward the goal, so a spring heading somewhere starts
            // moving this frame rather than the next. A fraction of the
            // critical speed cannot overshoot a critically damped spring.
            if (camVX === 0) camVX = (camGoalX - viewX) * w * 0.4;
            if (camVY === 0) camVY = (camGoalY - viewY) * w * 0.4;
        }
        camHasGoal = true;
        // A push off the mark, so a spring heading somewhere starts moving this
        // frame rather than the next.
        if (camVZoom === 0) camVZoom = (z - zoom) * w * 0.4;
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
        const w = camSpring * camRate, k = w * w, c = 2 * w;
        if (camHasGoal) {
            camVZoom += (-k * (zoom - camGoalZoom) - c * camVZoom) * dt;
            if (!camAnchored) {
                camVX += (-k * (viewX - camGoalX) - c * camVX) * dt;
                camVY += (-k * (viewY - camGoalY) - c * camVY) * dt;
            }
        } else {
            const f = Math.exp(-panFriction * dt);
            camVX *= f; camVY *= f; camVZoom *= f;
        }
        const z = clampZoom(zoom + camVZoom * dt);
        if (z !== zoom) zoom = z;
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

    Timer {
        interval: 16
        repeat: true
        running: effect.camLive()
        onTriggered: effect.camStep(interval / 1000)
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
        if (entering) farewellAnim.restart();
        else if (visible) welcomeAnim.restart();
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
        if (!smoothZoom || chromeFade <= 0.02) {
            then();
            return;
        }
        closing = true;
        farewellThen = then;
        farewellAnim.restart();
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
        camGo(1, t.x, t.y);
    }

    function origin() {
        camGo(1, 0, 0);
    }

    // Fit every window and every frame into the screen the pointer is on (the
    // active screen's, when there is no pointer), at once for a script and on
    // the spring for the toolbar and the key.
    function zoomExtents(animate) {
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
        if (animate) { camGo(f.zoom, f.viewX, f.viewY); return; }
        camStop();
        zoom = f.zoom;
        viewX = f.viewX;
        viewY = f.viewY;
    }

    // ---- open / close ------------------------------------------------------
    function open(quietMode, spec) {
        if (visible) return;
        camStop();
        quiet = !!quietMode;
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
        if (!quiet && passthrough) probeCall.call();
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
        switcherActive = false;
        if (sceneGestures > 0) {
            deferredClose = function () { commit(activate); };
            return;
        }
        camStop();
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
        // The location survives the session: where the eye left the plane
        // is where it comes back to after a restart.
        configuration.ViewX = Math.round(viewX);
        configuration.ViewY = Math.round(viewY);
        configuration.writeConfig();
        publishGround();
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
        switcherActive = false;
        if (!visible) return;
        if (sceneGestures > 0) {
            deferredClose = doCancel;
            return;
        }
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
    function toggleFromBorder(border) {
        if (configuration.BorderSlide) { borderSlide(border); return; }
        if (quiet) { if (grasp) graspEnd(); else finishSlide(); return; }
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
            const l = Math.max(e.x - tx, 0), t = Math.max(e.y - ty, 0);
            const r = Math.min(e.x - tx + e.width, g.width);
            const b = Math.min(e.y - ty + e.height, g.height);
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
        const set = isSelected(e) ? entries.filter(isSelected) : [e];
        for (let i = 0; i < set.length; ++i) dragRaw[set[i].window.internalId] = { x: set[i].x, y: set[i].y };
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
        // A pinned window dropped outside the screen bounces back in: the
        // anchor springs from where the hand let go to the nearest spot
        // wholly on screen, overshooting and settling - the physics of the
        // edges.
        for (let i = 0; i < entries.length; ++i) {
            const e = entries[i];
            if (!isPinnedEntry(e) || !dragRaw[e.window.internalId]) continue;
            const sx0 = (e.x - viewX) * zoom, sy0 = (e.y - viewY) * zoom;
            const cl = clampScreen(e);
            if (Math.abs(sx0 - cl.sx) < 0.5 && Math.abs(sy0 - cl.sy) < 0.5) {
                pinned[e.window.caption] = { sx: sx0, sy: sy0 };
            } else {
                bounce = { caption: e.window.caption, sx: sx0, sy: sy0, vx: 0, vy: 0, tx: cl.sx, ty: cl.sy };
            }
        }
        dragIndex = -1;
        endWindowDrag();
    }

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
        if (mode === "horizontal") {
            let x = box.x;
            for (let i = 0; i < list.length; ++i) { list[i].x = x; list[i].y = box.y; x += list[i].width + gap; }
        } else if (mode === "vertical") {
            let y = box.y;
            for (let i = 0; i < list.length; ++i) { list[i].x = box.x; list[i].y = y; y += list[i].height + gap; }
        } else if (mode === "cascade") {
            const step = 40;
            for (let i = 0; i < list.length; ++i) { list[i].x = box.x + i * step; list[i].y = box.y + i * step; }
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
                e.x = box.x + c * (cw + gap);
                e.y = box.y + r * (ch + gap);
                const idx = entries.indexOf(e);
                if (idx >= 0) requestSize(idx, cw, ch, false, false);
            }
        }
        // A pinned window keeps its pin: the arrangement becomes the new
        // anchor, clamped on screen.
        for (let i = 0; i < list.length; ++i) {
            if (isPinnedEntry(list[i])) pinned[list[i].window.caption] = clampScreen(list[i]);
        }
        revision++;
    }

    // sendTo(activity): move the selection so each window keeps its place
    // within a frame, now in that activity's frame. sendTo(null): park the
    // set near the origin at the nearest spot outside every frame.
    function sendTo(id) {
        const list = arrangeTargets();
        if (list.length === 0) return;
        if (id !== null && id !== undefined) {
            for (let i = 0; i < list.length; ++i) {
                const e = list[i];
                let from = activityAt(e);
                if (from === null) from = e.activity;
                const a = peekTarget(from), b = peekTarget(id);
                e.x += b.x - a.x;
                e.y += b.y - a.y;
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
            const spots = [{ x: 0, y: 0 }, { x: l - box.width - gap, y: 0 }, { x: 0, y: t - box.height - gap },
                           { x: r + gap, y: 0 }, { x: 0, y: b + gap }];
            const clear = function (sx, sy) {
                for (let i = 0; i < fs.length; ++i) {
                    const f = fs[i];
                    if (sx < f.x + f.width && sx + box.width > f.x && sy < f.y + f.height && sy + box.height > f.y) return false;
                }
                return true;
            };
            let best = null, bd = Infinity;
            for (let i = 0; i < spots.length; ++i) {
                if (!clear(spots[i].x, spots[i].y)) continue;
                const dist = Math.hypot(spots[i].x, spots[i].y);
                if (dist < bd) { bd = dist; best = spots[i]; }
            }
            if (!best) best = { x: l - box.width - gap, y: t - box.height - gap };
            for (let i = 0; i < list.length; ++i) { list[i].x += best.x - box.x; list[i].y += best.y - box.y; }
        }
        for (let i = 0; i < list.length; ++i) {
            if (isPinnedEntry(list[i])) pinned[list[i].window.caption] = clampScreen(list[i]);
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
    Timer {
        id: clickPanTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (clickPanEntry) {
                const e = clickPanEntry;
                clickPanEntry = null;
                bringIntoView(e);
            }
        }
    }

    // The modifier of the add gesture is also the marquee modifier on the ground.
    function marqueeModifiers() { return gestureFor(configuration.MouseSelectAdd).mods; }

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
        if (!e) return;
        if (!dragRaw[e.window.internalId]) beginDrag(index);
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
        revision++;
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
    // The plugin answered: if the canvas is still open, switch it on and give it the camera.
    function passthroughProbed() {
        if (!canvasOpen || passthroughLive) return;
        passthroughLive = true;
        publishCamera();
        publishNav();
        publishHold();
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
        holdDelayCall.arguments = [delay];
        holdDelayCall.call();
    }
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
        const p = KWin.Workspace.cursorPos;
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
        const p = cursorScreen();
        if (p.x < sg.x || p.x >= sg.x + sg.width || p.y < sg.y || p.y >= sg.y + sg.height) return;
        const cx = sg.x + sg.width / 2, cy = sg.y + sg.height / 2;
        const dx = p.x - cx, dy = p.y - cy;
        // The resting zone: everything but the outer band (EdgePanMargin).
        const deadX = sg.width / 2 - edgePanMargin, deadY = sg.height / 2 - edgePanMargin;
        const reachX = edgePanMargin, reachY = edgePanMargin;
        const tx = Math.abs(dx) <= deadX ? 0 : Math.sign(dx) * Math.min(1, (Math.abs(dx) - deadX) / reachX);
        const ty = Math.abs(dy) <= deadY ? 0 : Math.sign(dy) * Math.min(1, (Math.abs(dy) - deadY) / reachY);
        if (tx === 0 && ty === 0) return;
        // The depth, curved: a gentle start and a strong edge.
        const vx = Math.sign(tx) * Math.pow(Math.abs(tx), 1.7) * edgePanSpeed * dt;
        const vy = Math.sign(ty) * Math.pow(Math.abs(ty), 1.7) * edgePanSpeed * dt;
        noteGesture();
        panBy(-vx, -vy);
        edgeDrag(vx, vy);
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

    function publishGround() {
        if (!configuration.PublishGround) return;
        const script =
            "const ds = desktops();" +
            "for (let i = 0; i < ds.length; ++i) {" +
            "  ds[i].currentConfigGroup = ['Wallpaper', 'kwin-canvas-ground', 'General'];" +
            "  ds[i].writeConfig('OffsetX', " + viewX + ");" +
            "  ds[i].writeConfig('OffsetY', " + viewY + ");" +
            "}";
        groundCall.arguments = [script];
        groundCall.call();
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
    function backdropDim() {
        const d = Number(configuration.BackdropDim);
        if (isNaN(d)) return 0.45;
        return Math.max(0, Math.min(1, d));
    }
    function backdropBlur() {
        const b = Number(configuration.BackdropBlur);
        if (isNaN(b)) return 48;
        return Math.max(0, Math.min(128, Math.round(b)));
    }
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
        slideAnim.restart();
    }

    // A slide to a fresh destination, from wherever the camera is now: the
    // fly's own slide. A fly is the destination itself, not a step to
    // chain onto a previous one's half-travelled slide.
    function slideTo(dx, dy) {
        if (!beginSlide()) return;
        slideToX = viewX + dx;
        slideToY = viewY + dy;
        slideAnim.restart();
    }

    // Open quietly if closed. False while the real canvas is open.
    function beginSlide() {
        if (visible && !quiet) return false;
        if (!visible) {
            open(true);
            slideToX = viewX;
            slideToY = viewY;
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
        swiping = false;
        dropPassthrough();
        zoom = 1.0;
        const dx = Math.round(slideToX - entryViewX), dy = Math.round(slideToY - entryViewY);
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
        visible = false;
        quiet = false;
    }

    // Jump to the destination and settle now (another action wants the canvas).
    function finishSlide() {
        if (!quiet) return;
        slideAnim.stop();
        endSlide();
    }

    ParallelAnimation {
        id: slideAnim
        NumberAnimation { target: effect; property: "viewX"; to: effect.slideToX; duration: effect.panDuration; easing.type: Easing.OutCubic }
        NumberAnimation { target: effect; property: "viewY"; to: effect.slideToY; duration: effect.panDuration; easing.type: Easing.OutCubic }
        onFinished: effect.endSlide()
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

    function intersects(a, b) {
        return a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y;
    }

    // The two most recent windows, most recent first: what the canvas
    // modifier's swap (SwapButton while the modifier is held) flies between,
    // an Alt-Tab on the plane.
    property var focusHistory: []
    // The activation fly: the desktop slides until the window is wholly in
    // view, at the pan that leaves the most of the other windows in view for
    // the least movement - not always centred, so a desk keeps its shape.
    function flyToWindow(w) {
        const t = peekTarget(activityOf(w));
        const f = w.frameGeometry;
        const rect = { x: f.x + t.x, y: f.y + t.y, width: f.width, height: f.height };
        const others = [];
        const all = KWin.Workspace.stackingOrder;
        for (let i = 0; i < all.length; ++i) {
            const o = all[i];
            if (o === w || !isCanvasWindow(o, false)) continue;
            const ot = peekTarget(activityOf(o));
            const of = o.frameGeometry;
            others.push({ x: of.x + ot.x, y: of.y + ot.y, width: of.width, height: of.height });
        }
        const d = smartPan(rect, others, 24);
        if (d.dx !== 0 || d.dy !== 0) slideTo(d.dx, d.dy);
    }
    function noteFocus(w) {
        if (!w || w.deleted) return;
        if (focusHistory.length > 0 && focusHistory[0] === w) return;
        const out = [w];
        for (let i = 0; i < focusHistory.length && out.length < 2; ++i) if (focusHistory[i] !== w) out.push(focusHistory[i]);
        focusHistory = out;
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
        camGo(zoom, viewX + d.dx, viewY + d.dy, undefined, undefined, rate);
    }

    Connections {
        target: KWin.Workspace
        function onWindowActivated(w) {
            effect.noteFocus(w);
            // Open: a raise (pass-through clicks, the swap) restacks the thumbnails.
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
        function onWindowAdded(w) { if (effect.visible) Qt.callLater(effect.resync); }
        function onWindowRemoved(w) { if (effect.visible) Qt.callLater(effect.resync); }
        // Switching activities at 1:1 switches viewport: the ground follows.
        function onCurrentActivityChanged(id) {
            if (effect.refreshActivities()) effect.ensureTargets();
            if (effect.visible) return;
            const t = effect.targetOf(KWin.Workspace.currentActivity || "");
            effect.viewX = t.x;
            effect.viewY = t.y;
            effect.publishGround();
            const w = effect.pendingFocus;
            effect.pendingFocus = null;
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
        text: "Canvas: the switcher - the whole plane as a map, Tab to step, Enter to enter"
        sequence: effect.configuration.SwitcherShortcut
        onActivated: effect.switcherToggle()
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
        case "toggle": toggle(); break;
        case "home": home(); break;
        case "origin": origin(); break;
        case "extents": zoomExtents(); break;
        case "pan": if (numok(1) && numok(2)) panBy(Number(a[1]), Number(a[2])); break;
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
        case "unpinall": pinned = {}; savePinned(); break;
        case "arrange": arrange(a[1], Number(a[2]), Number(a[3])); break;
        case "snap": {
            const on = a[2] === "on";
            if (a[1] === "edges") snapEdges = on; else if (a[1] === "corners") snapCorners = on; else if (a[1] === "grid") snapGrid = on;
            break;
        }
        case "begindrag": beginDrag(Number(a[1])); break;
        case "sendto": sendTo(a[1] === "none" || !numok(1) ? null : activityIds[Number(a[1])]); break;
        case "marquee": if (numok(1) && numok(2) && numok(3) && numok(4)) selectInRect(Number(a[1]), Number(a[2]), Number(a[3]), Number(a[4])); break;
        case "state": break;
        case "switch": switcherToggle(); break;
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
            s += "\n  [" + i + "] " + (isSelected(e) ? "*" : " ") + e.window.caption + " canvas=(" + e.x.toFixed(0) + "," + e.y.toFixed(0) + " " + e.width + "x" + e.height + ") frame=(" + g.x + "," + g.y + ")" + (Math.abs(fx) > 0.4 || Math.abs(fy) > 0.4 ? " float=(+" + fx.toFixed(0) + ",+" + fy.toFixed(0) + ")" : "") + " activity=" + labelOf(e.activity);
        }
        for (let i = 0; i < clusters.length; ++i) {
            const mem = [];
            for (let k = 0; k < clusters[i].ids.length; ++k) {
                for (let j = 0; j < entries.length; ++j) if (entries[j].window.internalId === clusters[i].ids[k]) { mem.push(j); break; }
            }
            s += "\n  c" + i + ": " + mem.join(" ");
        }
        console.log(s);
    }

    onConfigurationChanged: {
        rebuildBindings();
        readSwipeFingers();
        publishHold();
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
        loadPinned();
        loadBookmarks();
        refreshActivities();
        lastDebugSeq = configuration.DebugSeq;
        publishHold();
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

    component Grip : Item {
        id: grip
        required property Item viewItem
        property int cursor: Qt.ArrowCursor
        property bool tappable: false
        // A click with a few pixels of hand noise must stay a click: the drag
        // does not move anything until the hand has travelled this far.
        property real dragDead: 0
        // Whether the hand has genuinely dragged: past the dead zone. The
        // weight follows this, so a sloppy click never lifts a window.
        readonly property bool moving: Math.hypot(total.x, total.y) >= grip.dragDead
        // Off during a grasp: a control the eye cannot see (a frame edge band)
        // must not take a drag the hand meant for the plane. Window bodies and
        // resize grips stay live - moving and resizing windows is what a grasp
        // is for.
        property bool holdOff: false
        property alias buttons: gripDrag.acceptedButtons
        readonly property bool hovered: gripHover.hovered
        readonly property bool active: gripDrag.active
        readonly property point total: gripDrag.activeTranslation
        signal dragStarted()
        signal dragged(real dx, real dy)
        signal dragEnded()
        signal tapped(int count, int modifiers, int button)

        HoverHandler {
            id: gripHover
            enabled: !grip.viewItem.spaceHeld && !(grip.holdOff && effect.grasp)
            cursorShape: gripDrag.active && grip.cursor === Qt.ArrowCursor ? Qt.ClosedHandCursor : grip.cursor
            onHoveredChanged: grip.viewItem.hoverCount += hovered ? 1 : -1
            Component.onDestruction: if (hovered) grip.viewItem.hoverCount -= 1
        }
        DragHandler {
            id: gripDrag
            target: null
            enabled: !grip.viewItem.spaceHeld && !(grip.holdOff && effect.grasp)
            acceptedButtons: effect.gripButtons
            // The portal buttons drag a control exactly as the left button
            // does; where they land on the ground instead they pan (panDrag).
            // A drag of one of them is also the canvas being navigated for as
            // long as it lasts - the view counts it into navHeld, which runs
            // the edge pan and holds the screen edges off - because a
            // TapHandler cannot: a drag past the tap threshold cancels its
            // press, and with it the record of the button being down.
            readonly property bool portal: active && (centroid.pressedButtons & effect.portalButtons) !== 0
            onPortalChanged: grip.viewItem.portalDrags += portal ? 1 : -1
            Component.onDestruction: if (portal) grip.viewItem.portalDrags -= 1
            property point last: Qt.point(0, 0)
            onActiveChanged: {
                effect.sceneGestures += active ? 1 : -1;
                effect.noteGesture(true);
                last = Qt.point(0, 0);
                if (active) grip.dragStarted(); else grip.dragEnded();
            }
            onActiveTranslationChanged: {
                const t = activeTranslation;
                if (grip.dragDead > 0 && Math.hypot(t.x, t.y) < grip.dragDead) return;
                grip.dragged(t.x - last.x, t.y - last.y);
                last = t;
            }
        }
        TapHandler {
            id: gripTap
            enabled: grip.tappable && !grip.viewItem.spaceHeld
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onTapped: (eventPoint, button) => grip.tapped(tapCount, point.modifiers, button)
        }
    }

    // The menus' background: opaque, because the Plasma style's translucent
    // menu assumes the desktop blur behind it and the canvas provides none.
    component MenuBackground : Rectangle {
        implicitWidth: 220
        implicitHeight: 24
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
    }

    component IconButton : Rectangle {
        id: button
        required property Item viewItem
        property string icon: ""
        property color hoverColor: "#60ffffff"
        signal clicked()
        width: 18
        height: 18
        radius: 3
        color: buttonHover.hovered ? hoverColor : "#30ffffff"
        Kirigami.Icon {
            anchors.fill: parent
            anchors.margins: 2
            source: button.icon
            color: "#ffffff"
        }
        HoverHandler {
            id: buttonHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: button.viewItem.hoverCount += hovered ? 1 : -1
            Component.onDestruction: if (hovered) button.viewItem.hoverCount -= 1
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: button.clicked()
        }
    }

    // The activity's name tag: a Grip for its frame group, plus the activity
    // controls: hide or show this frame, add an activity, remove this one.
    component FrameTag : Grip {
        id: tag
        required property string activity
        required property int activityIndex
        required property var screen
        readonly property bool current: activity === effect.currentActivity
        readonly property bool hidden: effect.isHidden(activity, screen)
        readonly property color accent: effect.palette[activityIndex % effect.palette.length]
        cursor: Qt.SizeAllCursor
        width: tagRow.implicitWidth + 12
        height: tagRow.implicitHeight + 6
        opacity: effect.chromeFade * (effect.quiet ? effect.quietReveal : 1)
        onDragStarted: effect.targetRaw = null
        onDragged: (dx, dy) => effect.dragTarget(activity, dx, dy)

        Rectangle {
            anchors.fill: parent
            radius: 3
            color: tag.accent
            opacity: tag.hidden ? 0.45 : (tag.current ? 1 : 0.8)
        }
        Row {
            id: tagRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: effect.labelOf(tag.activity) + " \u00b7 " + tag.screen.name + "  " + tag.screen.geometry.width + "x" + tag.screen.geometry.height
                color: effect.textOn(tag.accent)
                font.pixelSize: 12
                font.bold: true
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                viewItem: tag.viewItem
                icon: tag.hidden ? "view-hidden" : "view-visible"
                onClicked: effect.setHidden(tag.activity, tag.screen, !tag.hidden)
            }
            IconButton {
                visible: tag.activity !== ""
                anchors.verticalCenter: parent.verticalCenter
                viewItem: tag.viewItem
                icon: "list-add"
                onClicked: effect.addActivity()
            }
            IconButton {
                visible: effect.activityIds.length > 1
                anchors.verticalCenter: parent.verticalCenter
                viewItem: tag.viewItem
                icon: "edit-delete"
                hoverColor: "#80ff4040"
                onClicked: effect.removeActivity(tag.activity)
            }
        }
    }

    // ---- per-screen view ---------------------------------------------------
    delegate: Item {
        id: view
        readonly property var screen: KWin.SceneView.screen
        readonly property rect sg: KWin.SceneView.screen.geometry
        property bool spaceHeld: false
        // Number of grips and buttons under the pointer. The pan handler
        // refuses a left press while this is non-zero, so a drag that starts
        // on one of them acts on it instead of racing the pan.
        property int hoverCount: 0
        readonly property bool overControl: hoverCount > 0
        // Drags a portal button is holding, on any control of this screen
        // (a window body, a resize grip, a frame tag or edge). A press of one
        // is a navigation the moment it lands, but the tracker that knows that
        // is a TapHandler and a drag cancels it, so the drags count here too.
        property int portalDrags: 0
        // A pan button held down (PanHold), the canvas modifier (CanvasHold),
        // or the middle button: this screen is being navigated.
        // Four sources, one per stretch of the gesture: the
        // tap tracker knows the press the moment it lands and the release the
        // moment it lifts, whether or not the pointer ever moves — a pointer
        // parked at a screen edge is the whole gesture — the pan drag is
        // active for the stretch where the tracker has handed the gesture to
        // the drag, a drag on a control counts itself (portalDrags) for the
        // stretch where the drag has cancelled the tracker, and the canvas
        // modifier is down for its whole hold, during a grasp and in the open
        // overworld alike. None outlives the button.
        readonly property bool navHeld: navHold.pressed || panDrag.active || portalDrags > 0 || effect.canvasHold
        onNavHeldChanged: effect.navHolds += navHeld ? 1 : -1
        Component.onDestruction: if (navHeld) effect.navHolds -= 1
        // Input is live while the overworld is open, and while a grasp holds
        // the canvas quietly at 1:1 - a slide without a grasp stays inert,
        // which is what keeps a slide a brief animation and nothing more.
        enabled: !effect.quiet || effect.grasp || effect.switcherActive
        focus: true
        Connections {
            target: effect
            function onVisibleChanged() { if (effect.visible) view.hoverCount = 0; }
        }

        // The plane's base: opaque, so nothing shows through to the real
        // desktop under the effect wherever no wallpaper reaches (grid mode,
        // or a blur radius of 0 with the layer hidden). Below everything.
        Rectangle {
            anchors.fill: parent
            z: -100
            color: effect.configuration.Background
        }

        // Backdrop: the blurred continuation of the desktop's wallpaper,
        // screen-fixed like an overview's backdrop. The desks keep the exact
        // wallpaper - every frame draws the real desktop window - and beyond
        // them the plane is the same wallpaper in a haze, dimmed so the desks
        // and the windows stay the subject, with the ground grid over it. It
        // is the desktop window itself, live, and it hides while the current
        // activity's frame covers the view (open at 1:1, an idle slide),
        // which is exactly where the blur would be invisible anyway, so it
        // costs nothing until the camera moves.
        Item {
            id: blurLayer
            anchors.fill: parent
            z: -90
            readonly property bool wallpaper: effect.backdropMode() === "wallpaper"
            // The frame for this screen, drawn: does it cover the view?
            readonly property bool covered: {
                if (!wallpaper) return false;
                effect.revision;
                if (effect.isHidden(effect.currentActivity, view.screen)) return false;
                const t = effect.peekTarget(effect.currentActivity);
                const og = view.sg;
                const x = (t.x + og.x - effect.viewX) * effect.zoom;
                const y = (t.y + og.y - effect.viewY) * effect.zoom;
                const w = og.width * effect.zoom, h = og.height * effect.zoom;
                return x <= 0 && y <= 0 && x + w >= view.width && y + h >= view.height;
            }
            // The haze fades with the camera instead of switching: stepping
            // in softens it out as the desk fills the view, stepping out
            // softens it back. At rest under a covering frame it is gone and
            // costs nothing.
            readonly property bool wantShown: wallpaper && !covered
            property real blurAlpha: wantShown ? 1 : 0
            Behavior on blurAlpha { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }
            visible: wallpaper && (wantShown || blurAlpha > 0.004)
            opacity: blurAlpha
            // The source is rendered at half resolution and the blur is
            // upscaled: a quarter of the pixels for the same haze, which is
            // the difference between a full-screen blur that runs and one
            // that exhausts the GPU alongside the live thumbnails.
            Item {
                id: blurSourceHost
                width: Math.max(1, Math.round(view.width / 2))
                height: Math.max(1, Math.round(view.height / 2))
                anchors.centerIn: parent
                KWin.DesktopBackground {
                    anchors.fill: parent
                    output: view.screen
                    desktop: KWin.Workspace.currentDesktop
                    activity: effect.currentActivity || "default"
                }
            }
            FastBlur {
                anchors.fill: parent
                source: blurSourceHost
                radius: effect.backdropBlur()
                transparentBorder: false
            }
            // The dim over the blur only: the desks ride above it and stay
            // bright. Zero while the canvas slides at 1:1, where the plane
            // and the desktop have to be the same thing, and it fades in
            // with the chrome on open and out with it on the step in, so
            // stepping out and back never flashes the dim.
            Rectangle {
                anchors.fill: parent
                color: effect.configuration.Background
                opacity: effect.backdropDim() * effect.chromeFade * (effect.quiet ? effect.quietReveal : 1)
            }
        }

        Ground {
            anchors.fill: parent
            originX: -effect.viewX * effect.zoom - view.sg.x
            originY: -effect.viewY * effect.zoom - view.sg.y
            zoom: effect.zoom
            baseSpacing: effect.configuration.GridBase
            octaveFactor: effect.configuration.GridOctaveFactor
            octaves: effect.configuration.GridOctaves
            background: effect.configuration.Background
            lineColor: effect.configuration.LineColor
            tileImage: effect.configuration.TileImage
            // With the wallpaper behind it the base rect above is the ground's
            // background, and the grid draws over the wallpaper.
            drawBackground: effect.backdropMode() !== "wallpaper"
        }

        // Pan: left-drag on the ground, middle-drag anywhere, hold Space and
        // left-drag anywhere (Space disables every Grip and IconButton), or
        // hold a PanHold button and drag anywhere. Ground click: drop the
        // selection.
        TapHandler {
            enabled: !view.spaceHeld && !view.overControl
            acceptedButtons: Qt.LeftButton
            onTapped: (eventPoint, button) => { if ((point.modifiers & effect.marqueeModifiers()) === 0) effect.clearSelection(); }
        }

        // A left drag on the ground pans, or, with the add gesture's modifier
        // held, selects by rectangle. The two are told apart by the modifiers
        // the press itself carries: the keys may never reach this item
        // (pass-through hands them to the windows), and the hover events the
        // scene synthesizes between frames carry none, but every real pointer
        // event has the modifier state.
        Rectangle {
            id: marqueeBox
            property real x0: 0
            property real y0: 0
            property real x1: 0
            property real y1: 0
            readonly property rect rect: Qt.rect(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0))
            visible: panDrag.active && panDrag.marquee
            z: 90000
            x: rect.x; y: rect.y; width: rect.width; height: rect.height
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
            border.width: 1
            border.color: Kirigami.Theme.highlightColor
        }

        // The hold itself, on the button alone: no motion is needed for the
        // canvas to be navigated, so a pointer parked in an edge band pans
        // while the button is down. The middle button navigates with nothing
        // configured, the way it does in the drag below, so a held middle
        // button pans at an edge and holds the Screen Edges handlers off the
        // canvas as a hold of any PanHold button does. A tap handler with no
        // policy of its own takes a passive grab for those buttons only, so
        // the left button, the window gestures and the toolbar are untouched,
        // and a release always lifts it.
        TapHandler {
            id: navHold
            acceptedButtons: effect.panHoldButtons | Qt.MiddleButton
        }

        // SwapButton while the canvas modifier is held: fly between the two
        // most recent windows. Only the grasp acts on it; the press is
        // otherwise someone else's (in the overworld the pass-through plugin
        // hands it to the window under the pointer, at 1:1 the window's own
        // back/forward gesture).
        TapHandler {
            id: swapTap
            acceptedButtons: effect.swapButtons
            onTapped: effect.swapWindow()
        }

        DragHandler {
            id: panDrag
            target: null
            // The middle button pans from anywhere, even over a window or a
            // tag: this handler is on the screen's root item, so every press
            // lands on it. The left button and the PanHold buttons pan only on
            // the ground (or anywhere with Space held, or while this drag is
            // already going), so a press on a control is the control's - a
            // drag that starts on one acts on it instead of racing the pan, and
            // a held portal button moves the window it was pressed on rather
            // than panning under it.
            acceptedButtons: Qt.MiddleButton
                             | ((active || view.spaceHeld || !view.overControl) ? effect.gripButtons : 0)
            cursorShape: (active || view.navHeld) ? Qt.ClosedHandCursor : (view.spaceHeld ? Qt.OpenHandCursor : Qt.ArrowCursor)
            property bool marquee: false
            property point last: Qt.point(0, 0)
            // The hand's own record of the drag: how far it travelled, when it
            // started, and when it last moved. A fling is that average velocity
            // and only if the hand was still moving at the release: a drag that
            // pauses before letting go - the way a careful placement ends - is
            // a placement, not a throw.
            property real travelX: 0
            property real travelY: 0
            property real startedAt: 0
            property real movedAt: 0
            onActiveChanged: {
                // The reset belongs to the press, not to both transitions: the
                // release needs the travel and the times the drag ended with,
                // so zeroing them first would make every fling a no-op.
                effect.sceneGestures += active ? 1 : -1;
                effect.noteGesture(true);
                if (active) {
                    last = Qt.point(0, 0);
                    travelX = 0; travelY = 0;
                    effect.camStop();
                    startedAt = Date.now();
                    movedAt = startedAt;
                    const mods = effect.marqueeModifiers();
                    marquee = !view.spaceHeld && mods !== 0 && (centroid.modifiers & mods) !== 0 && (centroid.pressedButtons & Qt.LeftButton) !== 0;
                    if (marquee) {
                        marqueeBox.x0 = centroid.pressPosition.x; marqueeBox.y0 = centroid.pressPosition.y;
                        marqueeBox.x1 = marqueeBox.x0; marqueeBox.y1 = marqueeBox.y0;
                    }
                } else if (marquee) {
                    // The centroid resets on release; the box kept the last corner.
                    marquee = false;
                    const r = marqueeBox.rect;
                    const c0 = effect.globalToCanvas(r.x + view.sg.x, r.y + view.sg.y);
                    effect.selectInRect(c0.x, c0.y, r.width / effect.zoom, r.height / effect.zoom);
                } else {
                    // Let go: carry the plane if the hand was still moving.
                    const now = Date.now();
                    if (now - movedAt <= 120) effect.camFling(travelX, travelY, now - startedAt);
                }
            }
            onActiveTranslationChanged: {
                const t = activeTranslation;
                if (marquee) {
                    marqueeBox.x1 = marqueeBox.x0 + t.x;
                    marqueeBox.y1 = marqueeBox.y0 + t.y;
                    return;
                }
                const dx = t.x - last.x, dy = t.y - last.y;
                effect.panBy(dx, dy);
                last = t;
                travelX += dx;
                travelY += dy;
                if (dx !== 0 || dy !== 0) movedAt = Date.now();
            }
        }

        // Edge panning: while a button navigates the canvas - a PanHold button
        // or the middle button, held anywhere, a window or the ground - and the
        // pointer sits within EdgePanMargin of this screen's edge, the camera
        // keeps moving the way a drag would have — faster the deeper the pointer
        // is in the band — and stops when it leaves the band or the button comes
        // up. A window in hand rides the pan (edgePanStep): holding the button
        // on a window and pushing the pointer to the edge carries the window
        // with it. The screen the pointer is on does the panning, so a hold that
        // walks onto another screen hands over to that screen's view. A Timer,
        // as the camera's is, for the same reason: it steps from the event loop
        // rather than waiting for a frame, and its own step is what gets drawn.
        Timer {
            id: edgePanTimer
            interval: 16
            repeat: true
            running: view.navHeld && effect.edgePan && (effect.canvasOpen || effect.grasp)
            onTriggered: effect.edgePanStep(view.sg, interval / 1000)
        }

        // Zoom at the cursor, whether or not a pan button is held: a notch up
        // zooms in, a notch down zooms out. (With the pass-through plugin
        // loaded, a pointer over a client area belongs to the window, the wheel
        // included, and this handler never sees it.)
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                effect.noteGesture();
                const steps = event.angleDelta.y / 120;
                if (steps === 0) return;
                const anchor = Qt.point(event.x + view.sg.x, event.y + view.sg.y);
                // On the spring, so a notch reads as a zoom rather than a jump
                // and a burst of notches rides as one motion; several notches
                // from where the last one was heading, never from mid-step.
                const from = effect.camHasGoal ? effect.camGoalZoom : effect.zoom;
                effect.camZoomTo(from * Math.pow(effect.zoomStep, steps), anchor.x, anchor.y);
            }
        }

        // Z order, back to front: ground, monitor frames with their real
        // desktop background, windows in KWin's stacking order, frame tags, HUD.

        // Monitor frames: one per activity per output. An activity's frames
        // are a rigid group; dragging any edge band moves them all. The
        // interior is the Plasma desktop background for that output, so each
        // frame reads as a desk top. A hidden frame is not drawn; its tag stays.
        Repeater {
            model: effect.activityIds
            delegate: Repeater {
                id: activityFrames
                required property string modelData
                required property int index
                readonly property string activity: modelData
                readonly property bool current: modelData === effect.currentActivity
                readonly property color accent: effect.palette[index % effect.palette.length]
                // Re-read on a hotplug or a rearrange (screensRev), so the
                // frames follow Display Configuration.
                model: { effect.screensRev; return KWin.Workspace.screens; }
                delegate: Item {
                    id: frame
                    required property var modelData
                    readonly property rect og: modelData.geometry
                    // Quiet, the frame is just its wallpaper, no tint or
                    // outline, so the desktop looks like itself while it moves.
                    visible: !effect.isHidden(activityFrames.activity, modelData)
                    readonly property bool bare: effect.quiet
                    x: { effect.revision; return (effect.peekTarget(activityFrames.activity).x + og.x - effect.viewX) * effect.zoom - view.sg.x; }
                    y: { effect.revision; return (effect.peekTarget(activityFrames.activity).y + og.y - effect.viewY) * effect.zoom - view.sg.y; }
                    width: og.width * effect.zoom
                    height: og.height * effect.zoom
                    z: 1

                    // An empty activity makes KWin 6.7 dereference a null
                    // activities object when activities are disabled, so
                    // always pass a non-empty one.
                    KWin.DesktopBackground {
                        anchors.fill: parent
                        output: frame.modelData
                        desktop: KWin.Workspace.currentDesktop
                        activity: activityFrames.activity || "default"
                    }

                    // Sheet tint: keeps the frame legible when no background
                    // window exists. It fades out toward 1:1, so stepping out
                    // looks like the desktop until the camera moves, and rides
                    // the chrome fade on the way in.
                    Rectangle {
                        anchors.fill: parent
                        visible: !frame.bare || effect.quietReveal > 0.02
                        color: activityFrames.accent
                        opacity: (activityFrames.current ? 0.10 : 0.06) * Math.min(1, Math.max(0, (1 - effect.zoom) * 4)) * effect.chromeFade * (frame.bare ? effect.quietReveal : 1)
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: !frame.bare || effect.quietReveal > 0.02
                        color: "transparent"
                        border.width: activityFrames.current ? 2 : 1
                        border.color: activityFrames.accent
                        opacity: (activityFrames.current ? 0.95 : 0.6) * effect.chromeFade * (frame.bare ? effect.quietReveal : 1)
                    }

                    // A gesture on the frame's own area (windows sit above and
                    // take their own taps). Off during a grasp: the frames are
                    // bare wallpaper then, and a click there should be a click
                    // on the plane.
                    TapHandler {
                        enabled: !view.spaceHeld && !effect.grasp
                        acceptedButtons: Qt.LeftButton
                        onTapped: effect.frameGesture(activityFrames.activity, tapCount, point.modifiers)
                    }

                    // Edge bands: grips for the whole group.
                    Repeater {
                        model: 4
                        delegate: Grip {
                            required property int index
                            readonly property int band: 8
                            viewItem: view
                            cursor: Qt.SizeAllCursor
                            holdOff: true
                            x: index === 1 ? frame.width - band : 0
                            y: index === 3 ? frame.height - band : 0
                            width: (index === 0 || index === 2) ? frame.width : band
                            height: (index === 1 || index === 3) ? frame.height : band
                            onDragStarted: effect.targetRaw = null
                            onDragged: (dx, dy) => effect.dragTarget(activityFrames.activity, dx, dy)
                        }
                    }
                }
            }
        }

        // Windows.
        Repeater {
            model: effect.entries.length
            delegate: Item {
                id: thumb
                required property int index
                // The entry object keeps its identity across drags, so the
                // geometry bindings read the table directly and depend on
                // revision to re-evaluate after dragEntry().
                readonly property var entry: effect.entries[index]
                // The entry a drag started on. A raise restacks the entries
                // under the delegates, so a drag follows its entry, not its index.
                property var held: null
                readonly property int heldIndex: { effect.revision; return effect.entries.indexOf(held); }
                // The float's bob: each window hovers at its own phase.
                readonly property real phase: index * 137.508
                readonly property real bob: { effect.floatRev; return Math.sin(effect.floatRev * 0.035 + phase) * 2.4 * effect.floatAmt; }
                x: { effect.revision; effect.floatRev; effect.viewX; effect.viewY; effect.zoom; const f = effect.floatOf[thumb.entry.window.internalId]; const base = (effect.entries[index].x - effect.viewX) * effect.zoom - view.sg.x; return f ? f.x : base; }
                y: { effect.revision; effect.floatRev; effect.viewX; effect.viewY; effect.zoom; const f = effect.floatOf[thumb.entry.window.internalId]; const base = (effect.entries[index].y - effect.viewY) * effect.zoom - view.sg.y; return (f ? f.y : base) + thumb.bob; }
                width: { effect.revision; return effect.entries[index].width * effect.zoom; }
                height: { effect.revision; return effect.entries[index].height * effect.zoom; }
                visible: !effect.quiet || entry.activity === effect.currentActivity
                opacity: effect.thumbOpacity
                z: 1000 + index + (index * 37) % 26
                // Weight: the window lifts while the hand holds it, trails and
                // leans with the hand, and springs back when the hand stops.
                // The entry is exact throughout; this is the picture only.
                // The lift follows the drag's dead zone, so a click with hand
                // noise never grabs.
                readonly property bool heavy: effect.windowPhysics && !effect.quiet
                // Hovered: the scene's own hover, or the effect's poll. The
                // poll is the one that works over a window's client area while
                // the pass-through plugin owns the pointer there, so the glow,
                // the shadow and the lift follow it; the scene's hover stays
                // for the instant title-bar feel.
                readonly property bool hovered: body.hovered || effect.hoverEntry === thumb.entry
                property bool lifted: body.active && body.moving && heavy
                scale: lifted ? 1.03 : (thumb.hovered && heavy ? 1.008 : 1)
                Behavior on scale { enabled: thumb.heavy; SpringAnimation { spring: 3.6; damping: 0.5; epsilon: 0.001 } }
                transform: [
                    Rotation {
                        origin.x: thumb.width / 2
                        origin.y: thumb.height / 2
                        angle: thumb.lifted ? effect.dragLean : 0
                        Behavior on angle {
                            enabled: thumb.heavy
                            SpringAnimation { spring: 3.4; damping: 0.42; epsilon: 0.02 }
                        }
                    },
                    Translate {
                        x: thumb.lifted ? effect.dragLagX : 0
                        y: thumb.lifted ? effect.dragLagY : 0
                        Behavior on x {
                            enabled: thumb.heavy
                            SpringAnimation { spring: 3.4; damping: 0.42; epsilon: 0.2 }
                        }
                        Behavior on y {
                            enabled: thumb.heavy
                            SpringAnimation { spring: 3.4; damping: 0.42; epsilon: 0.2 }
                        }
                    }
                ]

                KWin.WindowThumbnail {
                    anchors.fill: parent
                    client: thumb.entry.window
                }

                // The soft shadow under the window: the lifted and the
                // hovered one float a little, glass over the plane.
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 3
                    anchors.margins: -2
                    z: -2
                    radius: 8
                    color: "#000000"
                    visible: !effect.quiet || effect.quietReveal > 0.02
                    opacity: effect.quiet ? effect.quietReveal * (liftedNow ? 0.30 : (thumb.hovered ? 0.16 : 0)) : (liftedNow ? 0.30 : (thumb.hovered ? 0.16 : 0))
                    readonly property bool liftedNow: body.active && body.moving && thumb.heavy
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                // The focus glow: the window the pointer has settled on wears
                // the activity's colour softly, so the eye knows which window
                // the canvas considers yours.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    z: -1
                    radius: 6
                    readonly property color accent: effect.activityColor(thumb.entry.activity)
                    visible: { effect.selectionRev; effect.quietReveal; return (!effect.quiet || effect.quietReveal > 0.02) && !effect.isSelected(thumb.entry); }
                    opacity: thumb.hovered ? (effect.quiet ? effect.quietReveal : 1) : 0
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    color: Qt.rgba(accent.r, accent.g, accent.b, 0.16)
                    border.width: 1
                    border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.5)
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    visible: !effect.quiet || effect.quietReveal > 0.02
                    opacity: effect.quiet ? effect.quietReveal : 1
                    readonly property bool sel: { effect.selectionRev; return effect.isSelected(thumb.entry); }
                    border.width: sel ? 3 : (thumb.hovered || body.active ? 2 : 1)
                    border.color: sel ? Kirigami.Theme.highlightColor
                                : (thumb.hovered || body.active ? effect.activityColor(thumb.entry.activity) : "#40ffffff")
                }

                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 2
                    text: thumb.entry.window.caption
                    color: "#ffffff"
                    font.pixelSize: 12
                    visible: effect.zoom < 0.6 || thumb.hovered
                    style: Text.Outline
                    styleColor: "#000000"
                }

                // The pin: a pinned window wears its marker and never leaves
                // the screen.
                Kirigami.Icon {
                    visible: effect.isPinnedEntry(thumb.entry) && (!effect.quiet || effect.quietReveal > 0.02)
                    source: "window-pin"
                    width: 14
                    height: 14
                    anchors.right: parent.right
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 1
                    anchors.rightMargin: 2
                    color: effect.activityColor(thumb.entry.activity)
                }

                // The client decides the size it ends up with. Follow it.
                Connections {
                    target: thumb.entry.window
                    function onFrameGeometryChanged() { effect.syncIndex(thumb.index); }
                    function onStackingOrderChanged() { Qt.callLater(effect.resync); }
                }

                // Body: move on drag, pick on click. The grip takes the PanHold
                // buttons like every other control (Grip), so with pass-through
                // or plane input live a held right button on a window is a
                // portal into the canvas: the app under it never sees the
                // press, and the drag moves the window on the plane instead.
                Grip {
                    id: body
                    anchors.fill: parent
                    viewItem: view
                    tappable: true
                    dragDead: 14
                    // The open hand: the window's own area - the title bar
                    // and the edges - reads as grabbable, while the client
                    // area keeps the app's cursor under the pass-through.
                    cursor: Qt.OpenHandCursor
                    onDragStarted: { thumb.held = thumb.entry; effect.beginDrag(thumb.index); }
                    onDragged: (dx, dy) => { effect.dragEntry(thumb.heldIndex, dx, dy); effect.noteDrag(dx, dy); }
                    onDragEnded: effect.endDrag()
                    onTapped: (count, modifiers, button) => effect.windowGesture(thumb.entry, count, modifiers, button)
                }

                // The window's client area, where planeTakes() lets the
                // pointer through to the window. No handlers, so without the
                // shim the body below takes everything as before.
                Item {
                    objectName: "kwin-canvas-client"
                    readonly property var entry: thumb.entry
                    readonly property rect fg: thumb.entry.window.frameGeometry
                    readonly property rect cg: thumb.entry.window.clientGeometry
                    x: (cg.x - fg.x) * effect.zoom
                    y: (cg.y - fg.y) * effect.zoom
                    width: cg.width * effect.zoom
                    height: cg.height * effect.zoom
                    z: 5
                }

                // Resize grips: four edges, four corners, above the body. Each
                // drag step commands the real window to the new size.
                Repeater {
                    model: 8
                    delegate: Grip {
                        id: grip
                        required property int index
                        readonly property int b: 6
                        readonly property int c: 14
                        readonly property bool north: index === 0 || index === 4 || index === 5
                        readonly property bool south: index === 1 || index === 6 || index === 7
                        readonly property bool west: index === 2 || index === 4 || index === 6
                        readonly property bool east: index === 3 || index === 5 || index === 7
                        readonly property bool corner: index >= 4
                        property real startW: 0
                        property real startH: 0
                        viewItem: view
                        z: 10
                        x: corner ? (west ? 0 : thumb.width - c) : (west ? 0 : (east ? thumb.width - b : c))
                        y: corner ? (north ? 0 : thumb.height - c) : (north ? 0 : (south ? thumb.height - b : c))
                        width: corner ? c : ((west || east) ? b : Math.max(0, thumb.width - 2 * c))
                        height: corner ? c : ((north || south) ? b : Math.max(0, thumb.height - 2 * c))
                        cursor: corner
                            ? ((north && west) || (south && east) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor)
                            : ((north || south) ? Qt.SizeVerCursor : Qt.SizeHorCursor)
                        onDragStarted: {
                            thumb.held = thumb.entry;
                            startW = thumb.entry.width;
                            startH = thumb.entry.height;
                        }
                        onDragged: {
                            const t = grip.total;
                            let rw = startW, rh = startH;
                            if (east) rw = startW + t.x / effect.zoom;
                            if (west) rw = startW - t.x / effect.zoom;
                            if (south) rh = startH + t.y / effect.zoom;
                            if (north) rh = startH - t.y / effect.zoom;
                            effect.requestSize(thumb.heldIndex, rw, rh, west, north);
                        }
                    }
                }
            }
        }

        // App popups, above the windows and the frame tags, below the
        // toolbar and the canvas's menus, in KWin's stacking order. Each is
        // drawn at its real geometry with the plane transform, and its area
        // is where planeTakes() lets the pointer through to it.
        Repeater {
            model: effect.appPopups
            delegate: Item {
                required property var modelData
                required property int index
                readonly property rect fg: modelData ? modelData.frameGeometry : Qt.rect(0, 0, 0, 0)
                objectName: "kwin-canvas-popup"
                x: fg.x * effect.planeScale + effect.planeOffsetX - view.sg.x
                y: fg.y * effect.planeScale + effect.planeOffsetY - view.sg.y
                width: fg.width * effect.planeScale
                height: fg.height * effect.planeScale
                z: 70000 + index

                KWin.WindowThumbnail {
                    anchors.fill: parent
                    client: parent.modelData
                }
            }
        }

        // Clusters: the threads that bind nearby windows, and the badge that
        // names the cluster the eye is on. The thread is the constellation -
        // a polyline weaving through the members, riding the same motion as
        // the windows, lit where the pointer's cluster is and a faint sketch
        // for the rest when zoomed out far enough to see the plane. The
        // badge floats over the active cluster's centre: a glass chip with
        // its number, so the travel keys have a stop to point at.
        Repeater {
            model: effect.clusters.length
            delegate: Item {
                required property int index
                readonly property var cluster: effect.clusters[index]
                readonly property bool active: { effect.clusterRev; effect.focusEntry; effect.selectionRev; return effect.clusterIndex() === index; }
                readonly property real cx: { effect.revision; effect.viewX; effect.viewY; effect.zoom; return (cluster.cx - effect.viewX) * effect.zoom - view.sg.x; }
                readonly property real cy: { effect.revision; effect.viewX; effect.viewY; effect.zoom; return (cluster.cy - effect.viewY) * effect.zoom - view.sg.y; }
                visible: !effect.quiet && cluster.n > 1
                // The delegate fills the whole view - the wrapper has no size
                // of its own, and the path is in view coordinates. The thread
                // sits under the windows it binds but above the frames: the
                // z lives on the delegate, since a child's z cannot lift its
                // parent out of the frame layer.
                width: view.width
                height: view.height
                // The web weaves through the float: the windows hover at
                // spread heights, and the web rides the middle, so it passes
                // over some and under others as they bob. The z lives on the
                // delegate: a child's z cannot lift its parent out of the
                // frame layer.
                z: 1013
                // The cluster's web: plain thin lines joining every window
                // to every other, behind the windows - the constellation
                // reads in the gaps, never over the glass.
                Shape {
                    id: threadShape
                    anchors.fill: parent
                    readonly property real want: (parent.active || effect.zoom < 0.5) ? (parent.active ? 0.4 : 0.16) * cluster.co * (effect.quiet ? effect.quietReveal : 1) : 0
                    property real show: 0
                    opacity: show
                    Behavior on show { NumberAnimation { duration: 350; easing.type: Easing.InOutCubic } }
                    onWantChanged: show = want
                    Component.onCompleted: show = want
                    ShapePath {
                        strokeWidth: 1.1
                        strokeColor: Qt.rgba(1, 1, 1, 0.5)
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg {
                            // The camera and the float are dependencies on
                            // purpose: the web rides every glide, pan and
                            // bob with the windows it binds.
                            path: { effect.revision; effect.clusterRev; effect.floatRev; effect.viewX; effect.viewY; effect.zoom; return effect.clusterPath(index, view.sg.x, view.sg.y); }
                        }
                    }
                }
                // The badge: the cluster's number in reading order, glass. A
                // hand on it drags the whole cluster across the plane.
                Rectangle {
                    id: badge
                    x: cx - width / 2
                    y: cy - height - 14
                    Behavior on x { SpringAnimation { spring: 2.6; damping: 0.62; epsilon: 0.5 } }
                    Behavior on y { SpringAnimation { spring: 2.6; damping: 0.62; epsilon: 0.5 } }
                    z: 59000
                    visible: parent.active && cluster.n > 1 && (!effect.quiet || effect.quietReveal > 0.02)
                    width: row.implicitWidth + 16
                    height: 24
                    radius: 12
                    color: "#cc1e2126"
                    border.width: 1
                    border.color: "#66ffffff"
                    Grip {
                        id: badgeGrip
                        anchors.fill: parent
                        viewItem: view
                        cursor: Qt.OpenHandCursor
                        onDragStarted: effect.beginClusterDrag(index)
                        onDragged: (dx, dy) => effect.dragCluster(index, dx, dy)
                        onDragEnded: effect.endDrag()
                    }
                    Row {
                        id: row
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "#" + (index + 1)
                            color: "#ffffff"
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: cluster.n + " windows"
                            color: "#b8ffffff"
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        // The plane map - one living picture, two homes. While the modifier
        // is held it is the whole screen: the frames as border-only
        // outlines, the windows as shaded sheets, a click flying the camera
        // to a sheet. In the overworld it shrinks into the corner and turns
        // to glass - the view behind it blurred and magnified - and the
        // same click flies the camera. The two homes are one item, so the
        // map morphs between them, springing from the full screen into the
        // corner sheet and back.
        Item {
            id: planeMap
            z: 80000
            readonly property int mw: Math.round(view.sg.width * 0.16)
            readonly property int mh: Math.round(view.sg.height * 0.2)
            readonly property bool asOverlay: (effect.grasp || effect.switcherActive) && view.screen === effect.primaryScreen
            readonly property bool asMinimap: effect.canvasOpen && !effect.quiet && effect.zoom < 0.9 && !effect.grasp && view.screen === effect.primaryScreen
            readonly property rect home: asOverlay
                ? Qt.rect(24, 24, view.sg.width - 48, view.sg.height - 48)
                : Qt.rect(view.sg.width - mw - Kirigami.Units.largeSpacing * 2, view.sg.height - mh - Kirigami.Units.largeSpacing * 2, mw, mh)
            visible: asOverlay || asMinimap
            property bool morphReady: false
            Component.onCompleted: {
                x = home.x; y = home.y; width = home.width; height = home.height;
                morphReady = true;
            }
            onHomeChanged: {
                if (!morphReady) return;
                x = home.x; y = home.y; width = home.width; height = home.height;
            }
            Behavior on x { enabled: planeMap.morphReady; SpringAnimation { spring: 2.4; damping: 0.62; epsilon: 0.5 } }
            Behavior on y { enabled: planeMap.morphReady; SpringAnimation { spring: 2.4; damping: 0.62; epsilon: 0.5 } }
            Behavior on width { enabled: planeMap.morphReady; SpringAnimation { spring: 2.4; damping: 0.62; epsilon: 0.5 } }
            Behavior on height { enabled: planeMap.morphReady; SpringAnimation { spring: 2.4; damping: 0.62; epsilon: 0.5 } }
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            // The map lives: every binding depends on the revision and the
            // camera explicitly - a function's reads do not register as
            // dependencies, so without these the map would be a still.
            readonly property rect wb: { effect.revision; effect.screensRev; return effect.worldBounds(); }
            readonly property real sc: { effect.revision; return Math.min((width - 12) / wb.width, (height - 12) / wb.height); }
            readonly property real ox: { effect.revision; return (width - wb.width * sc) / 2; }
            readonly property real oy: { effect.revision; return (height - wb.height * sc) / 2; }
            function mx(cx) { return ox + (cx - wb.x) * sc; }
            function my(cy) { return oy + (cy - wb.y) * sc; }
            // The lens: the scene behind the map, magnified a little and
            // blurred - the glass the minimap wears, and the frost the
            // overlay's sheets melt the live windows behind into. The
            // sourceRect follows the map's own rect, so one glass rides
            // both homes through the morph, and it fades in with the
            // sheet's entrance so the hold's zoom-out blurs the windows
            // as the map sharpens over them.
            ShaderEffectSource {
                visible: planeMap.asMinimap || planeMap.asOverlay || opacity > 0.004
                id: glass
                anchors.fill: parent
                sourceItem: view
                recursive: false
                sourceRect: Qt.rect(planeMap.x + planeMap.width * 0.02, planeMap.y + planeMap.height * 0.02, planeMap.width * 0.96, planeMap.height * 0.96)
                // Half resolution, like the wallpaper haze: a quarter of the
                // pixels for the same frost, which is the difference between
                // a full-screen blur that runs and one that exhausts the GPU.
                textureSize: Qt.size(Math.max(1, Math.round(width / 2)), Math.max(1, Math.round(height / 2)))
                layer.enabled: true
                layer.effect: FastBlur {
                    radius: 11
                    transparentBorder: false
                }
                // The lens wears the glass; the overlay does not - its blurred
                // live background read as strobing on a real desktop.
                opacity: planeMap.asMinimap ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
            scale: 1.0
            // The map's content, wrapped so the hold's entrance can be the
            // slow blur transition: the sheets, the outlines and the dim
            // sharpen out of a haze as the overlay fades in, and dissolve
            // back into it on the release.
            Item {
                id: graspContent
                anchors.fill: parent
                property real graspFade: planeMap.asOverlay ? 1 : 0
                // The step in fades the map's content with the chrome while
                // the camera's rectangle expands to take the map.
                opacity: (planeMap.asOverlay ? graspFade : 1) * effect.chromeFade
                Behavior on graspFade { NumberAnimation { duration: 430; easing.type: Easing.OutCubic } }
                layer.enabled: true
                layer.effect: GaussianBlur {
                    radius: Math.max(0, 14 * (1 - graspContent.graspFade)) * (planeMap.asOverlay ? 1 : 0)
                    samples: 17
                    transparentBorder: false
                }
            // The dim behind the overlay, and the tint over the lens.
            Rectangle {
                anchors.fill: parent
                radius: planeMap.asMinimap ? 16 : 0
                color: planeMap.asMinimap ? Qt.rgba(0.07, 0.07, 0.09, 0.42) : "transparent"
                // The minimap's dark region bleeds into the plane instead of
                // ending at a line: the edge is a soft falloff.
                layer.enabled: planeMap.asMinimap
                layer.effect: GaussianBlur {
                    radius: 5
                    samples: 17
                    transparentBorder: false
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: planeMap.asMinimap ? 16 : 0
                color: "transparent"
                border.width: 1
                border.color: planeMap.asMinimap ? "#3affffff" : "transparent"
            }

            Repeater {
                model: effect.frames().length
                delegate: Rectangle {
                    required property int index
                    readonly property var f: effect.frames()[index]
                    visible: planeMap.asMinimap
                    x: { effect.revision; effect.screensRev; return planeMap.mx(f.x); }
                    y: { effect.revision; effect.screensRev; return planeMap.my(f.y); }
                    width: { effect.revision; return f.width * planeMap.sc; }
                    height: { effect.revision; return f.height * planeMap.sc; }
                    readonly property color accent: effect.palette[index % effect.palette.length]
                    color: Qt.rgba(accent.r, accent.g, accent.b, 0.30)
                    border.width: 1
                    border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.75)
                    opacity: 0.9
                }
            }
            Repeater {
                model: effect.entries.length
                delegate: Rectangle {
                    required property int index
                    readonly property var e: effect.entries[index]
                    x: { effect.revision; return planeMap.mx(e.x); }
                    y: { effect.revision; effect.floatRev; return planeMap.my(e.y) + Math.sin(effect.floatRev * 0.035 + index * 137.508) * 1.2 * effect.floatAmt * planeMap.sc; }
                    width: { effect.revision; return Math.max(planeMap.asOverlay ? 6 : 1.6, e.width * planeMap.sc); }
                    height: { effect.revision; return Math.max(planeMap.asOverlay ? 6 : 1.6, e.height * planeMap.sc); }
                    radius: planeMap.asOverlay ? 5 : 1
                    color: planeMap.asOverlay
                        ? (effect.graspHoverIndex === index || effect.isSelected(e) ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.20))
                        : Qt.rgba(1, 1, 1, 0.8)
                    border.width: planeMap.asOverlay ? 0.8 : 0
                    border.color: effect.graspHoverIndex === index || effect.isSelected(e) ? "#f0ffffff" : "#70ffffff"
                    Text {
                        anchors.centerIn: parent
                        text: effect.graspHoverIndex === index && planeMap.asOverlay ? e.window.caption : ""
                        color: "#ffffff"
                        font.pixelSize: 10
                        style: Text.Outline
                        styleColor: "#80000000"
                        visible: text !== "" && parent.width > 60
                    }
                    // The sheet itself is the click target; everywhere else
                    // the map passes the pointer to the windows beneath.
                    TapHandler {
                        enabled: planeMap.asOverlay
                        onTapped: effect.graspJumpTo(index)
                    }
                }
            }
            // The camera's viewport on the map: the rectangle that IS the
            // screen. It floats - a soft halo under a rounded glass chip -
            // melts away when the view dominates the map, and expands to
            // take the map the moment a step in begins, while the map's
            // content fades with the chrome.
            Item {
                id: cameraRect
                x: { effect.revision; effect.viewX; effect.zoom; return planeMap.mx(effect.viewX + view.sg.x / effect.zoom); }
                y: { effect.revision; effect.viewY; effect.zoom; return planeMap.my(effect.viewY + view.sg.y / effect.zoom); }
                width: { effect.zoom; effect.revision; return Math.max(3, view.sg.width / effect.zoom * planeMap.sc); }
                height: { effect.zoom; effect.revision; return Math.max(3, view.sg.height / effect.zoom * planeMap.sc); }
                // The graceful extreme: a view that covers most of the map
                // melts instead of becoming a huge slab.
                readonly property real cover: Math.min(1, (width * height) / Math.max(1, planeMap.width * planeMap.height))
                readonly property real fade: 0.35 + 0.65 * (1 - Math.min(1, Math.max(0, (cover - 0.55) / 0.45)))
                // The step in: the world's window expands to take the map.
                readonly property real expansion: effect.entering ? Math.max(1, planeMap.width / Math.max(1, width)) : 1
                scale: expansion
                transformOrigin: Item.Center
                Behavior on scale { SpringAnimation { spring: 2.8; damping: 0.55; epsilon: 0.01 } }
                // The halo, under the chip: the float.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -7
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.08)
                    layer.enabled: true
                    layer.effect: GaussianBlur {
                        radius: 6
                        samples: 17
                        transparentBorder: false
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: planeMap.asMinimap ? 3 : 3
                    color: Qt.rgba(1, 1, 1, planeMap.asOverlay ? 0.05 : 0.12)
                    border.width: 1
                    border.color: "#e8ffffff"
                    opacity: cameraRect.fade
                    // The rectangle itself pans the camera: drag the
                    // viewport across the map and the view follows.
                    DragHandler {
                        property point last: Qt.point(0, 0)
                        onActiveChanged: { if (!active) last = Qt.point(0, 0); }
                        onActiveTranslationChanged: {
                            const t = activeTranslation;
                            effect.panBy(t.x - last.x, t.y - last.y);
                            last = t;
                        }
                    }
                }
            }
            }
            // The minimap's own click flies the camera to the point; the
            // overlay's sheets carry their taps, so the rest of the map
            // never steals the pointer from the windows beneath it.
            TapHandler {
                enabled: planeMap.asMinimap
                onTapped: (eventPoint) => {
                    const wb = effect.worldBounds();
                    const cx = wb.x + (eventPoint.position.x - planeMap.ox) / planeMap.sc;
                    const cy = wb.y + (eventPoint.position.y - planeMap.oy) / planeMap.sc;
                    const g = effect.actionScreen().geometry;
                    effect.camGo(effect.zoom, cx - (g.x + g.width / 2) / effect.zoom, cy - (g.y + g.height / 2) / effect.zoom);
                }
            }
        }

        // Frame tags, above the windows so they can always be grabbed.
        Repeater {
            model: effect.activityIds
            delegate: Repeater {
                id: activityTags
                required property string modelData
                required property int index
                model: { effect.screensRev; return KWin.Workspace.screens; }
                delegate: FrameTag {
                    required property var modelData
                    visible: !effect.quiet || effect.quietReveal > 0.02
                    viewItem: view
                    activity: activityTags.modelData
                    activityIndex: activityTags.index
                    screen: modelData
                    x: { effect.revision; return (effect.peekTarget(activity).x + screen.geometry.x - effect.viewX) * effect.zoom - view.sg.x; }
                    y: { effect.revision; return (effect.peekTarget(activity).y + screen.geometry.y - effect.viewY) * effect.zoom - view.sg.y - height - 2; }
                    z: 60000
                }
            }
        }

        Keys.onPressed: (event) => {
            const k = event.key;
            if (effect.bound("pan", k)) {
                if (!event.isAutoRepeat) view.spaceHeld = true;
            } else if (effect.bound("next", k) && !(event.modifiers & Qt.ShiftModifier)) {
                if (!event.isAutoRepeat) effect.cycleSelection(1);
            } else if (effect.bound("prev", k) || (effect.bound("next", k) && (event.modifiers & Qt.ShiftModifier))) {
                // Shift+Tab arrives as Tab with the shift modifier, whatever
                // the platform does about Backtab, so both count as previous.
                if (!event.isAutoRepeat) effect.cycleSelection(-1);
            } else if (effect.bound("cancel", k)) {
                effect.cancel();
            } else if (effect.bound("apply", k)) {
                effect.applyKey();
            } else if (effect.bound("home", k)) {
                effect.home();
            } else if (effect.bound("origin", k)) {
                effect.origin();
            } else if (effect.bound("fit", k)) {
                effect.zoomExtents(true);
            } else if (effect.bound("zoomIn", k)) {
                const p = effect.cursorScreen();
                effect.camZoomTo(effect.zoom * effect.zoomStep, p.x, p.y);
            } else if (effect.bound("zoomOut", k)) {
                const p = effect.cursorScreen();
                effect.camZoomTo(effect.zoom / effect.zoomStep, p.x, p.y);
            } else if (effect.bound("panLeft", k)) {
                effect.panKey(-1, 0);
            } else if (effect.bound("panRight", k)) {
                effect.panKey(1, 0);
            } else if (effect.bound("panUp", k)) {
                effect.panKey(0, -1);
            } else if (effect.bound("panDown", k)) {
                effect.panKey(0, 1);
            } else if (effect.bound("clusterNext", k) && !(event.modifiers & Qt.ShiftModifier)) {
                if (!event.isAutoRepeat) effect.clusterTravel(1);
            } else if (effect.bound("clusterPrev", k) || (effect.bound("clusterNext", k) && (event.modifiers & Qt.ShiftModifier))) {
                if (!event.isAutoRepeat) effect.clusterTravel(-1);
            } else if (k >= Qt.Key_1 && k <= Qt.Key_9) {
                // The digits are the plane's desks: jump, or save with Ctrl.
                const i = k - Qt.Key_1;
                if (event.modifiers & Qt.ControlModifier) effect.saveBookmark(i);
                else if (!(event.modifiers & (Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier))) effect.gotoBookmark(i);
                else return;
            } else {
                return;
            }
            event.accepted = true;
        }

        Keys.onReleased: (event) => {
            if (effect.bound("pan", event.key) && !event.isAutoRepeat) {
                view.spaceHeld = false;
                event.accepted = true;
            }
        }

        // Arrange menu for the selection, opened by the context gesture on a window.
        Connections {
            target: effect
            function onContextRequested(entry) {
                // Attached properties resolve against this Connections object, so go through the view.
                // One menu, on the screen the pointer is on: every screen's view
                // is connected to this signal, and the pointer's screen is where
                // the gesture was made, not the focused window's.
                if (view.screen !== effect.actionScreen()) return;
                const p = effect.cursorScreen();
                arrangeMenu.x = p.x - view.sg.x;
                arrangeMenu.y = p.y - view.sg.y;
                arrangeMenu.open();
            }
        }
        PC3.Menu {
            id: arrangeMenu
            z: 100001
            title: "Arrange"
            onOpened: effect.canvasMenus++
            onClosed: effect.canvasMenus = Math.max(0, effect.canvasMenus - 1)
            // The Plasma menu background assumes the desktop blur behind it;
            // over the canvas there is none, so the menu is drawn opaque.
            background: MenuBackground { }
            PC3.MenuItem { text: "Arrange horizontally"; icon.name: "view-split-left-right"; onTriggered: effect.arrange("horizontal") }
            PC3.MenuItem { text: "Arrange vertically";   icon.name: "view-split-top-bottom"; onTriggered: effect.arrange("vertical") }
            PC3.MenuItem { text: "Tile";                 icon.name: "view-grid";             onTriggered: effect.arrange("tile") }
            PC3.Menu {
                title: "Grid"
                icon.name: "view-grid"
                background: MenuBackground { }
                Repeater {
                    model: ["1x2", "2x1", "2x2", "3x1", "1x3", "3x2", "2x3", "3x3", "4x2", "2x4"]
                    delegate: PC3.MenuItem {
                        required property string modelData
                        text: modelData.replace("x", " × ") + "  (rows × columns)"
                        onTriggered: { const p = modelData.split("x"); effect.arrange("grid", Number(p[0]), Number(p[1])); }
                    }
                }
            }
            PC3.MenuItem { text: "Cascade";              icon.name: "window-duplicate";      onTriggered: effect.arrange("cascade") }
            PC3.MenuSeparator {}
            PC3.Menu {
                title: "Send to"
                icon.name: "activities"
                background: MenuBackground { }
                Repeater {
                    model: effect.activityIds
                    delegate: PC3.MenuItem {
                        required property string modelData
                        required property int index
                        text: effect.labelOf(modelData)
                        onTriggered: effect.sendTo(modelData)
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: Kirigami.Units.smallSpacing; width: 12; height: 12; radius: 3; color: effect.palette[index % effect.palette.length] }
                    }
                }
                PC3.MenuSeparator {}
                PC3.MenuItem { text: "Plane, outside every activity"; icon.name: "edit-none"; onTriggered: effect.sendTo(null) }
            }
            PC3.MenuSeparator {}
            PC3.MenuItem { text: "Clear selection";      icon.name: "edit-select-none";      onTriggered: effect.clearSelection() }
            PC3.MenuSeparator {}
            PC3.MenuItem { text: effect.pinTargetsPinned() ? "Unfloat" : "Float"; icon.name: "window-pin"; onTriggered: effect.togglePin() }
        }

        // The toast: a brief glass chip naming what just happened (a saved
        // or jumped-to view).
        Rectangle {
            z: 100001
            visible: view.screen === effect.primaryScreen && effect.toastText !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Kirigami.Units.largeSpacing * 3
            width: toastLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
            height: toastLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: Kirigami.Units.cornerRadius
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.78)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
            opacity: { effect.toastRev; return effect.toastText !== "" ? 1 : 0; }
            Behavior on opacity { NumberAnimation { duration: 180 } }
            PC3.Label {
                id: toastLabel
                anchors.centerIn: parent
                text: effect.toastText
            }
        }

        // HUD: a Plasma toolbar, top centre. Camera state, the actions, help
        // with the bindings, and the settings pages that own them.
        Rectangle {
            id: hud
            z: 100000
            visible: view.screen === effect.primaryScreen && (!effect.quiet || effect.quietReveal > 0.5)
            opacity: effect.chromeFade * (effect.quiet ? Math.max(0, Math.min(1, (effect.quietReveal - 0.5) * 2)) : 1)
            readonly property string pos: String(effect.configuration.HudPosition || "Top").toLowerCase()
            readonly property bool atBottom: pos.indexOf("bottom") === 0
            readonly property bool atLeft: pos === "left" || pos === "topleft" || pos === "bottomleft"
            readonly property bool atRight: pos === "right" || pos === "topright" || pos === "bottomright"
            readonly property bool centredV: pos === "left" || pos === "right"
            readonly property bool inCorner: pos === "topleft" || pos === "topright" || pos === "bottomleft" || pos === "bottomright"
            // Shape: auto follows the position (square in a corner, vertical on
            // a side, horizontal on the top or bottom), or forced by config.
            readonly property string shape: {
                const want = String(effect.configuration.HudShape || "auto").toLowerCase();
                if (want === "horizontal" || want === "vertical" || want === "square") return want;
                return inCorner ? "square" : (centredV ? "vertical" : "horizontal");
            }
            readonly property bool vertical: shape === "vertical"
            readonly property bool square: shape === "square"
            readonly property int squareColumns: 4
            anchors.top: atBottom || centredV ? undefined : parent.top
            anchors.bottom: atBottom ? parent.bottom : undefined
            anchors.verticalCenter: centredV ? parent.verticalCenter : undefined
            anchors.left: atLeft ? parent.left : undefined
            anchors.right: atRight ? parent.right : undefined
            anchors.horizontalCenter: !atLeft && !atRight ? parent.horizontalCenter : undefined
            anchors.margins: Kirigami.Units.largeSpacing
            width: hudRow.implicitWidth + Kirigami.Units.largeSpacing * 2
            height: hudRow.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: Kirigami.Units.cornerRadius
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.72)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
            Kirigami.Theme.inherit: false
            Kirigami.Theme.colorSet: Kirigami.Theme.Window

            HoverHandler {
                onHoveredChanged: view.hoverCount += hovered ? 1 : -1
                Component.onDestruction: if (hovered) view.hoverCount -= 1
            }

            GridLayout {
                id: hudRow
                anchors.centerIn: parent
                flow: hud.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                rows: hud.vertical ? -1 : (hud.square ? -1 : 1)
                columns: hud.vertical ? 1 : (hud.square ? hud.squareColumns : -1)
                rowSpacing: Kirigami.Units.smallSpacing
                columnSpacing: Kirigami.Units.smallSpacing

                // Separators only in the linear shapes; a square reads as rows.
                component Sep : Kirigami.Separator {
                    visible: !hud.square
                    Layout.fillHeight: !hud.vertical
                    Layout.fillWidth: hud.vertical
                    Layout.margins: Kirigami.Units.smallSpacing
                }

                Kirigami.Icon {
                    visible: !hud.square
                    source: "activities"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    Layout.alignment: Qt.AlignCenter
                }
                PC3.Label {
                    text: hud.vertical ? effect.labelOf(effect.currentActivity) + "\n" + Math.round(effect.zoom * 100) + "%"
                                       : effect.labelOf(effect.currentActivity) + "   " + Math.round(effect.zoom * 100) + "%"
                    horizontalAlignment: Text.AlignHCenter
                    Layout.alignment: Qt.AlignCenter
                    Layout.columnSpan: hud.square ? hud.squareColumns : 1
                    Layout.rightMargin: hud.vertical || hud.square ? 0 : Kirigami.Units.smallSpacing
                }
                // One swatch per activity in its frame colour; click to zoom to it.
                Repeater {
                    model: effect.activityIds
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool current: modelData === effect.currentActivity
                        width: Kirigami.Units.iconSizes.small
                        height: Kirigami.Units.iconSizes.small
                        radius: 3
                        color: effect.palette[index % effect.palette.length]
                        border.width: current ? 2 : 0
                        border.color: Kirigami.Theme.textColor
                        Layout.alignment: Qt.AlignCenter
                        PC3.ToolTip.text: effect.labelOf(modelData)
                        PC3.ToolTip.visible: swatchHover.hovered
                        HoverHandler { id: swatchHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { acceptedButtons: Qt.LeftButton; onTapped: effect.zoomToActivity(modelData) }
                    }
                }
                Sep {}
                PC3.ToolButton { icon.name: "zoom-fit-best";   text: "Fit";    display: PC3.AbstractButton.IconOnly; PC3.ToolTip.text: "Zoom to fit (" + effect.keyLabel(effect.configuration.KeyFit) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.zoomExtents(true) }
                PC3.ToolButton { icon.name: "go-home";         text: "Home";   display: PC3.AbstractButton.IconOnly; PC3.ToolTip.text: "Look through this activity's frames (" + effect.keyLabel(effect.configuration.KeyHome) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.home() }
                PC3.ToolButton { icon.name: "zoom-in";         text: "In";     display: PC3.AbstractButton.IconOnly; PC3.ToolTip.text: "Zoom in (" + effect.keyLabel(effect.configuration.KeyZoomIn) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.camZoomTo(effect.zoom * effect.zoomStep, view.sg.x + view.sg.width / 2, view.sg.y + view.sg.height / 2) }
                PC3.ToolButton { icon.name: "zoom-out";        text: "Out";    display: PC3.AbstractButton.IconOnly; PC3.ToolTip.text: "Zoom out (" + effect.keyLabel(effect.configuration.KeyZoomOut) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.camZoomTo(effect.zoom / effect.zoomStep, view.sg.x + view.sg.width / 2, view.sg.y + view.sg.height / 2) }
                Sep {}
                PC3.ToolButton { icon.name: "snap-bounding-box-edges";   text: "Edges";   display: PC3.AbstractButton.IconOnly; checkable: true; checked: effect.snapEdges;   onToggled: effect.snapEdges = checked;   PC3.ToolTip.text: "Snap to edges";   PC3.ToolTip.visible: hovered }
                PC3.ToolButton { icon.name: "snap-bounding-box-corners"; text: "Corners"; display: PC3.AbstractButton.IconOnly; checkable: true; checked: effect.snapCorners; onToggled: effect.snapCorners = checked; PC3.ToolTip.text: "Snap to corners"; PC3.ToolTip.visible: hovered }
                PC3.ToolButton { icon.name: "snap-grid";                 text: "Grid";    display: PC3.AbstractButton.IconOnly; checkable: true; checked: effect.snapGrid;    onToggled: effect.snapGrid = checked;    PC3.ToolTip.text: "Snap to grid (" + effect.configuration.SnapGridSize + " px)"; PC3.ToolTip.visible: hovered }
                Sep {}
                PC3.ToolButton { icon.name: "dialog-ok-apply"; text: "Enter";  display: hud.vertical || hud.square ? PC3.AbstractButton.IconOnly : PC3.AbstractButton.TextBesideIcon; PC3.ToolTip.text: "Enter the location under the screen centre (" + effect.keyLabel(effect.configuration.KeyApply) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.enterHere() }
                PC3.ToolButton { icon.name: "dialog-cancel";   text: "Cancel"; display: hud.vertical || hud.square ? PC3.AbstractButton.IconOnly : PC3.AbstractButton.TextBesideIcon; PC3.ToolTip.text: "Back to where you were, nothing moved (" + effect.keyLabel(effect.configuration.KeyCancel) + ")"; PC3.ToolTip.visible: hovered; onClicked: effect.cancel() }
                Sep {}
                PC3.ToolButton { id: helpButton; icon.name: "help-contextual"; text: "Help"; display: PC3.AbstractButton.IconOnly; checkable: true; checked: effect.helpOpen; onToggled: effect.helpOpen = checked; PC3.ToolTip.text: "Controls"; PC3.ToolTip.visible: hovered }
                PC3.ToolButton {
                    icon.name: "configure"; text: "Settings"; display: PC3.AbstractButton.IconOnly
                    PC3.ToolTip.text: "Settings"; PC3.ToolTip.visible: hovered
                    onClicked: settingsMenu.open()
                    PC3.Menu {
                        id: settingsMenu
                        onOpened: effect.canvasMenus++
                        onClosed: effect.canvasMenus = Math.max(0, effect.canvasMenus - 1)
                        background: MenuBackground { }
                        x: hud.vertical ? (hud.atRight ? -width : parent.width) : 0
                        y: hud.vertical ? 0 : parent.height
                        PC3.MenuItem { text: "Effect settings…";  icon.name: "preferences-desktop-effects"; onTriggered: KCM.KCMLauncher.openSystemSettings("kcm_kwin_effects") }
                        PC3.MenuItem { text: "Shortcuts…";        icon.name: "preferences-desktop-keyboard"; onTriggered: KCM.KCMLauncher.openSystemSettings("kcm_keys") }
                        PC3.MenuItem { text: "Screen edges…";     icon.name: "preferences-desktop-screen-edges"; onTriggered: KCM.KCMLauncher.openSystemSettings("kcm_kwinscreenedges") }
                        PC3.MenuItem { text: "Activities…";       icon.name: "activities"; onTriggered: KCM.KCMLauncher.openSystemSettings("kcm_activities") }
                    }
                }
            }
        }

        // Help: the bindings, read from the same config the actions use.
        Rectangle {
            z: 100000
            visible: effect.helpOpen && hud.visible
            opacity: effect.chromeFade
            anchors.top: hud.vertical ? hud.top : (hud.atBottom ? undefined : hud.bottom)
            anchors.bottom: !hud.vertical && hud.atBottom ? hud.top : undefined
            anchors.left: hud.vertical ? (hud.atLeft ? hud.right : undefined) : (hud.atLeft ? hud.left : undefined)
            anchors.right: hud.vertical ? (hud.atRight ? hud.left : undefined) : (hud.atRight ? hud.right : undefined)
            anchors.horizontalCenter: !hud.vertical && !hud.atLeft && !hud.atRight ? hud.horizontalCenter : undefined
            anchors.margins: Kirigami.Units.smallSpacing
            width: helpGrid.implicitWidth + Kirigami.Units.largeSpacing * 2
            height: helpGrid.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: Kirigami.Units.cornerRadius
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.92)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
            Kirigami.Theme.inherit: false
            Kirigami.Theme.colorSet: Kirigami.Theme.Window
            HoverHandler {
                onHoveredChanged: view.hoverCount += hovered ? 1 : -1
                Component.onDestruction: if (hovered) view.hoverCount -= 1
            }
            GridLayout {
                id: helpGrid
                anchors.centerIn: parent
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing
                component K : PC3.Label { font.family: "monospace"; opacity: 0.85 }
                component V : PC3.Label {}
                K { text: "drag ground / " + effect.keyLabel(effect.configuration.KeyPan) + "+drag / middle-drag" } V { text: "pan" }
                K { text: "hold " + effect.holdLabel(effect.configuration.PanHold) + " or middle" } V { text: "the canvas takes the pointer: drag the ground to pan, drag a window to move it" }
                K { text: "hold it / to a screen edge" }                        V { text: "the canvas keeps panning; a window in hand comes along" }
                K { text: "hold " + effect.holdLabel(effect.configuration.CanvasHold) } V { text: "on the desktop: the location itself becomes the canvas; drags and the wheel work, release applies" }
                K { text: "hold it, tap " + effect.holdLabel(effect.configuration.SwapButton) } V { text: "fly between the two most recent windows; release opens the location there, focused" }
                K { text: "click a window / rest on it" }                        V { text: "the camera pans the least that fits it wholly into view" }
                K { text: "wheel / " + effect.keyLabel(effect.configuration.KeyZoomIn) + " / " + effect.keyLabel(effect.configuration.KeyZoomOut) } V { text: "zoom at the cursor" }
                K { text: "drag window" }                                       V { text: "move it on the plane" }
                K { text: "drag window edge or corner" }                        V { text: "resize it" }
                K { text: "drag frame tag or edge" }                            V { text: "move that activity's screens" }
                K { text: "eye on a frame tag" }                                V { text: "hide or show that frame; a hidden frame takes no windows" }
                K { text: effect.gestureLabel(effect.configuration.MouseSelect) + " window" }        V { text: "select it" }
                K { text: effect.gestureLabel(effect.configuration.MouseSelectAdd) + " window, or +drag ground" } V { text: "add to the selection, or select by rectangle" }
                K { text: effect.gestureLabel(effect.configuration.MouseSelectToggle) + " window" }  V { text: "toggle its selection; a selected window drags the whole selection" }
                K { text: effect.gestureLabel(effect.configuration.MouseContextMenu) + " window" }   V { text: "arrange the selection: horizontal, vertical, tile, grid, cascade" }
                K { text: effect.gestureLabel(effect.configuration.MouseFocusWindow) + " window" }   V { text: effect.focusHelp() }
                K { text: effect.gestureLabel(effect.configuration.MouseZoomToActivity) + " frame" }  V { text: "zoom to that activity" }
                K { text: effect.gestureLabel(effect.configuration.MouseGotoActivity) + " frame" }    V { text: "apply with that activity current" }
                K { text: effect.gestureLabel(effect.configuration.MouseNewActivityAt) + " window outside frames" } V { text: "new activity centred on it" }
                K { text: effect.keyLabel(effect.configuration.KeyNext) + " / " + effect.keyLabel(effect.configuration.KeyPrev) } V { text: "step the selection through the windows; the camera follows" }
                K { text: effect.keyLabel(effect.configuration.KeyPanLeft) + " / " + effect.keyLabel(effect.configuration.KeyPanRight) + " / " + effect.keyLabel(effect.configuration.KeyPanUp) + " / " + effect.keyLabel(effect.configuration.KeyPanDown) } V { text: "pan the camera one step" }
                K { text: "1..9 / ctrl+1..9" }                               V { text: "jump to a saved view / save the current view" }
                K { text: effect.keyLabel(effect.configuration.KeyApply) }      V { text: "enter the location under the screen centre; with a window selected, enter it focused" }
                K { text: effect.keyLabel(effect.configuration.KeyCancel) }     V { text: "back to where you were, nothing moved" }
                K { text: effect.keyLabel(effect.configuration.KeyHome) }       V { text: "look through this activity's frames" }
                K { text: effect.keyLabel(effect.configuration.KeyOrigin) }     V { text: "camera to the canvas origin" }
                K { text: effect.keyLabel(effect.configuration.KeyFit) }        V { text: "zoom to fit" }
            }
        }
    }
}
