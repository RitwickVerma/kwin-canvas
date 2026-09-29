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
    readonly property int planeNavButtons: (bindings.panHold || 0) | Qt.MiddleButton
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
    property int lastDebugSeq: 0

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
    function buttonsFor(spec) {
        let mask = 0;
        const names = String(spec || "").split(",");
        for (let i = 0; i < names.length; ++i) {
            const n = names[i].trim();
            if (!n) continue;
            const code = Qt[n];
            if (typeof code !== "number") { console.warn("kwin-canvas: unknown mouse button", n); continue; }
            mask |= code;
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
            panHold: buttonsFor(configuration.PanHold)
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
        if (!entry.window.deleted) entry.window.activities = [id];
        entry.activity = id;
        revision++;
        // Activating a window on another activity does not switch to it.
        KWin.Workspace.currentActivity = id;
        commit(entry.window);
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

    // ---- camera ops --------------------------------------------------------
    function globalToCanvas(gx, gy) { return Qt.point(viewX + gx / zoom, viewY + gy / zoom); }

    function clampZoom(z) { return Math.max(zoomMin, Math.min(1.0, Number(z))); }

    // Zoom while holding the canvas point under `anchor` (global px) fixed on screen.
    function setZoom(z, anchor) {
        z = clampZoom(z);
        const c = globalToCanvas(anchor.x, anchor.y);
        zoom = z;
        viewX = c.x - anchor.x / zoom;
        viewY = c.y - anchor.y / zoom;
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
    function camGo(z, goalX, goalY, gx, gy) {
        z = clampZoom(z);
        const pinned = gx !== undefined && gx !== null;
        camStop();
        if (!smoothZoom) {
            if (pinned) setZoom(z, Qt.point(gx, gy));
            else { zoom = z; viewX = goalX; viewY = goalY; }
            return;
        }
        camGoalZoom = z;
        if (pinned) {
            const c = globalToCanvas(gx, gy);
            camAnchorX = c.x; camAnchorY = c.y; camAnchorGX = gx; camAnchorGY = gy;
            camAnchored = true;
            camGoalX = viewX; camGoalY = viewY;
        } else {
            camAnchored = false;
            camGoalX = goalX; camGoalY = goalY;
        }
        camHasGoal = true;
        // A push off the mark, so a spring heading somewhere starts moving this
        // frame rather than the next.
        if (camVZoom === 0) camVZoom = (z - zoom) * camSpring * 0.4;
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
        const w = camSpring, k = w * w, c = 2 * w;
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
            && (camAnchored || (Math.abs(viewX - camGoalX) < 0.2 && Math.abs(viewY - camGoalY) < 0.2
                                && Math.abs(camVX) < 0.5 && Math.abs(camVY) < 0.5))) {
            zoom = camGoalZoom;
            if (camAnchored) {
                viewX = camAnchorX - camAnchorGX / zoom;
                viewY = camAnchorY - camAnchorGY / zoom;
            } else {
                viewX = camGoalX; viewY = camGoalY;
            }
            camStop();
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
        running: effect.canvasOpen && effect.camLive()
        onTriggered: effect.camStep(interval / 1000)
    }

    // Look through the current activity's frames.
    function home() {
        const t = targetOf(currentActivity);
        viewX = t.x;
        viewY = t.y;
        zoom = 1.0;
    }

    function origin() {
        viewX = 0;
        viewY = 0;
        zoom = 1.0;
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
        const pad = 80;
        const z = Math.max(zoomMin, Math.min(1.0, Math.min((sg.width - 2 * pad) / (r - l), (sg.height - 2 * pad) / (b - t))));
        const cx = (l + r) / 2 - (sg.x + sg.width / 2) / z;
        const cy = (t + b) / 2 - (sg.y + sg.height / 2) / z;
        if (animate) { camGo(z, cx, cy); return; }
        camStop();
        zoom = z;
        viewX = cx;
        viewY = cy;
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
        if (!quiet) openView(spec);
        if (!quiet && passthrough) probeCall.call();
    }

    // Where the camera starts: fit everything, stay at 1:1, or a zoom anchored
    // at the centre of the screen being opened. An edge or corner passes its
    // own spec (BorderZoom) instead of OpenZoom: the canvas steps out around
    // the screen the pointer pushed, about that screen's centre. Because the
    // anchor does not move, the point the push left under that centre is the
    // point applying comes back to, so a corner's step out and the chord's
    // "enter the location under the screen centre" still agree exactly.
    function openView(spec) {
        if (spec === undefined || spec === null || spec === "") spec = configuration.OpenZoom;
        spec = String(spec || "fit").trim().toLowerCase();
        if (spec === "fit") { zoomExtents(true); return; }
        const z = Number(spec);
        if (!(z > 0) || z >= 1) return;
        const g = actionScreen().geometry;
        camZoomTo(z, g.x + g.width / 2, g.y + g.height / 2);
    }

    // Write every window's geometry relative to the frame it sits in, move it to
    // that frame's activity, put the camera on the current activity's target,
    // and hand input back.
    function commit(activate) {
        camStop();
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
        publishGround();
        settled = false;
        visible = false;
        quiet = false;
        swiping = false;
        dropPassthrough();
        if (activate && !activate.deleted) {
            KWin.Workspace.activeWindow = activate;
        }
    }

    function cancel() {
        if (!visible) return;
        camStop();
        unsettle();
        targets = copyTargets(entryTargets);
        viewX = entryViewX;
        viewY = entryViewY;
        zoom = 1.0;
        visible = false;
        quiet = false;
        swiping = false;
        dropPassthrough();
    }

    // The chord: step out to the canvas, or enter the location in view.
    function toggle() {
        if (quiet) { finishSlide(); return; }
        if (visible) enterHere(); else open();
    }

    // A screen edge or corner fired: the same step out and the same enter, but
    // the step out is a step *around the screen that was pushed* (BorderZoom),
    // so the push shows the desks around that screen instead of the desktop it
    // was already on. The chord and the toolbar keep OpenZoom; a border that
    // fires while the canvas is open enters, as it always has.
    function toggleFromBorder() {
        if (quiet) { finishSlide(); return; }
        if (visible) { enterHere(); return; }
        open(false, configuration.BorderZoom);
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
        if (a !== currentActivity) gotoActivity(a); else commit(null);
    }

    // ---- placing the desk around a window -------------------------------------

    // The offsets that keep a w x h window wholly inside the screen g, inset by
    // margin: the range of screen offsets its top-left may take, the offset
    // that centres it, and whether any offset fits at all (a window larger than
    // the screen fits nowhere). Everything here is in the units the target
    // moves in - canvas pixels, which at the applied 1:1 are screen pixels.
    function fitRange(w, h, g, margin) {
        const x0 = margin, x1 = g.width - w - margin;
        const y0 = margin, y1 = g.height - h - margin;
        return { x0: x0, x1: x1, y0: y0, y1: y1,
                 cx: Math.round((g.width - w) / 2), cy: Math.round((g.height - h) / 2),
                 fits: x1 >= x0 && y1 >= y0 };
    }

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
        const range = fitRange(entry.width, entry.height, g, margin);
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
    function focusWindow(entry, gx, gy) {
        if (gx === undefined) { const p = cursorScreen(); gx = p.x; gy = p.y; }
        const inFrame = activityAt(entry);
        const a = inFrame !== null ? inFrame : (entry.activity || currentActivity);
        const t = targetOf(a);
        const mode = focusMode();
        if (mode === "window") {
            const c = globalToCanvas(gx, gy);
            t.x = Math.round(c.x - gx);
            t.y = Math.round(c.y - gy);
            // The point clicked is kept under the pointer unless that would
            // leave the window hanging over an edge of the screen: then the
            // least shift that brings it wholly back in, because a window a
            // double-click focused should not be half off the screen.
            const g = actionScreen().geometry;
            const range = fitRange(entry.width, entry.height, g, 8);
            if (range.fits) {
                t.x = Math.round(entry.x - g.x - Math.max(range.x0, Math.min(range.x1, entry.x - t.x - g.x)));
                t.y = Math.round(entry.y - g.y - Math.max(range.y0, Math.min(range.y1, entry.y - t.y - g.y)));
            }
        } else if (mode === "smart") {
            const g = actionScreen().geometry;
            const off = smartOffset(entry, a, g);
            t.x = Math.round(entry.x - g.x - off.dx);
            t.y = Math.round(entry.y - g.y - off.dy);
        } else if (mode === "centre" || inFrame === null) {
            // "centre", and "desktop" for a window outside every frame.
            const g = actionScreen().geometry;
            t.x = Math.round(entry.x + entry.width / 2 - (g.x + g.width / 2));
            t.y = Math.round(entry.y + entry.height / 2 - (g.y + g.height / 2));
        }
        if (a && a !== currentActivity) {
            pendingFocus = entry.window;
            KWin.Workspace.currentActivity = a;
            commit(null);
            return;
        }
        commit(entry.window);
    }

    // zoomToActivity: camera fitted to that activity's frames, canvas stays open.
    function zoomToActivity(id) {
        const t = peekTarget(id);
        const vs = KWin.Workspace.virtualScreenGeometry;
        const l = t.x + vs.x, tp = t.y + vs.y, r = l + vs.width, b = tp + vs.height;
        const sg = actionScreen().geometry;
        const pad = 60;
        const z = Math.max(zoomMin, Math.min(1.0, Math.min((sg.width - 2 * pad) / (r - l), (sg.height - 2 * pad) / (b - tp))));
        zoom = z;
        viewX = (l + r) / 2 - (sg.x + sg.width / 2) / zoom;
        viewY = (tp + b) / 2 - (sg.y + sg.height / 2) / zoom;
    }

    // gotoActivity: apply with that activity current, frames where they are.
    function gotoActivity(id) {
        if (id && id !== currentActivity) KWin.Workspace.currentActivity = id;
        commit(null);
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
        dragRaw = {};
        dragIndex = index;
        const set = isSelected(e) ? entries.filter(isSelected) : [e];
        for (let i = 0; i < set.length; ++i) dragRaw[set[i].window.internalId] = { x: set[i].x, y: set[i].y };
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
    // The plugin answered: if the canvas is still open, switch it on and give it the camera.
    function passthroughProbed() {
        if (!canvasOpen || passthroughLive) return;
        passthroughLive = true;
        publishCamera();
        publishNav();
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

    // One step of edge panning, for a view whose screen is sg: the pointer
    // parked in an edge band moves the camera the way a drag would have, by
    // the depth in the band times EdgePanSpeed, for dt seconds. Content
    // follows the pointer, as it does under a drag: the pointer at the right
    // edge keeps the canvas moving right. Nothing happens while the pointer is
    // off sg, so a hold that walks onto another screen hands over to its view.
    function edgePanStep(sg, dt) {
        if (!sg || edgePanSpeed <= 0 || dt <= 0) return;
        const p = cursorScreen();
        if (p.x < sg.x || p.x >= sg.x + sg.width || p.y < sg.y || p.y >= sg.y + sg.height) return;
        const m = edgePanMargin;
        const inL = 1 - Math.min(1, (p.x - sg.x) / m);
        const inR = 1 - Math.min(1, (sg.x + sg.width - p.x) / m);
        const inT = 1 - Math.min(1, (p.y - sg.y) / m);
        const inB = 1 - Math.min(1, (sg.y + sg.height - p.y) / m);
        const vx = (inR - inL) * edgePanSpeed * dt;
        const vy = (inB - inT) * edgePanSpeed * dt;
        if (vx === 0 && vy === 0) return;
        panBy(vx, vy);
        edgeDrag(vx, vy);
    }

    // An edge pan with a window in hand takes the window along: holding a
    // navigate button on a window and pushing the pointer to a screen edge pans
    // and carries it. The camera
    // moved the plane by (vx, vy) on screen, so the window moves the other way
    // by the same amount on the plane - its screen position does not change and
    // it stays under the pointer - while the desk, the frames included, travels
    // under it: the edge scroll of any drag and drop, with a desktop on the
    // plane. Same call as the pointer's own step, so the set being dragged, the
    // snapping and the write under plane input all behave the same, and the
    // window stays still on screen, which is why it neither trails nor leans.
    function edgeDrag(dx, dy) {
        if (dragIndex < 0) return;
        dragEntry(dragIndex, -dx, -dy);
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
    onRevisionChanged: if (planeLive) Qt.callLater(settle)

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
    // The canvas's background is the wallpaper, not a void. One
    // KWin.DesktopBackground per output sits at that output's place on the
    // current activity's frames, so at 1:1 it is pixel-identical to the real
    // desktop under the effect and rides the plane as the camera moves - and it
    // is the desktop window itself, live, so a slideshow, a picture of the day
    // or an animated wallpaper keeps going. Beyond the screens the same
    // wallpaper is tiled at primary-screen steps (BackdropReach), each padding
    // tile wearing the wallpaper of the output nearest to it, so the plane
    // reads as the desktop continuing rather than a grid into nothing. Tiles
    // are cheap: KWin shares one offscreen render per (view, window) between
    // every item that shows it (WindowThumbnailSource::getOrCreate in
    // windowthumbnailitem.cpp), so this costs draw calls, not renders.
    //
    // Only the effect draws this. While the canvas is closed the wallpaper is
    // the real one, and the ground wallpaper plugin (with a grid, at 1:1)
    // stands in for the plane.
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
    // The tiles, in canvas units relative to the current activity's frames, so
    // they ride with the frames exactly as the frames' wallpaper does. The
    // model only changes when the screens or the activity do, so a camera move
    // or a drag never rebuilds it.
    readonly property var backdropTiles: {
        screensRev; currentActivity; backdropMode();
        return computeBackdropTiles();
    }
    function computeBackdropTiles() {
        if (backdropMode() !== "wallpaper") return [];
        const ss = KWin.Workspace.screens;
        if (!ss || ss.length === 0) return [];
        const out = [];
        for (let i = 0; i < ss.length; ++i) {
            const g = ss[i].geometry;
            out.push({ o: ss[i], dx: g.x, dy: g.y, w: g.width, h: g.height, z: 0 });
        }
        const reach = Math.max(0, Math.min(4, Math.round(Number(configuration.BackdropReach) || 0)));
        if (reach === 0) return out;
        const vs = KWin.Workspace.virtualScreenGeometry;
        const cellW = Math.max(320, primaryScreen.geometry.width);
        const cellH = Math.max(240, primaryScreen.geometry.height);
        const cols = Math.ceil(vs.width / cellW) + 2 * reach;
        const rows = Math.ceil(vs.height / cellH) + 2 * reach;
        const x0 = vs.x - reach * cellW, y0 = vs.y - reach * cellH;
        for (let r = 0; r < rows; ++r) {
            for (let c = 0; c < cols; ++c) {
                const dx = x0 + c * cellW, dy = y0 + r * cellH;
                out.push({ o: nearestScreen(ss, dx + cellW / 2, dy + cellH / 2),
                           dx: dx, dy: dy, w: cellW, h: cellH, z: -1 });
            }
        }
        return out;
    }
    // The output whose wallpaper a padding tile wears: the nearest one, so the
    // desktop's own edge is where its picture ends rather than a stranger's.
    function nearestScreen(ss, x, y) {
        let best = ss[0], bd = Infinity;
        for (let i = 0; i < ss.length; ++i) {
            const g = ss[i].geometry;
            const ddx = g.x + g.width / 2 - x, ddy = g.y + g.height / 2 - y;
            const d = ddx * ddx + ddy * ddy;
            if (d < bd) { bd = d; best = ss[i]; }
        }
        return best;
    }

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

    function slide(dx, dy) {
        if (!beginSlide()) return;
        if (!slideAnim.running) { slideToX = viewX; slideToY = viewY; }
        slideToX += dx;
        slideToY += dy;
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
            const fx = Math.round(e.x - t.x), fy = Math.round(e.y - t.y);
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
    // that way. Closed, it is a slide; open, the camera just moves.
    function panStepBy(dx, dy) {
        const st = panStep();
        if (canvasOpen) { panBy(-dx * st.x, -dy * st.y); return; }
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

    Connections {
        target: KWin.Workspace
        function onWindowActivated(w) {
            // Open: a raise (pass-through clicks) restacks the thumbnails.
            // The plane transform is only ever live while open, so the
            // on-screen test below always sees geometry as drawn.
            if (effect.visible) { Qt.callLater(effect.resync); return; }
            if (!effect.configuration.FollowActivation) return;
            if (!effect.isCanvasWindow(w, false)) return;
            const g = w.frameGeometry;
            if (effect.intersects(g, KWin.Workspace.virtualScreenGeometry)) return;
            const area = KWin.Workspace.clientArea(KWin.Workspace.PlacementArea, w);
            const dx = Math.round(area.x + (area.width - g.width) / 2 - g.x);
            const dy = Math.round(area.y + (area.height - g.height) / 2 - g.y);
            effect.shiftAll(dx, dy);
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
        name: "Canvas Home"
        text: "Canvas: return this activity to the origin"
        sequence: effect.configuration.HomeShortcut
        onActivated: {
            if (effect.quiet) effect.finishSlide();
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
                if (!effect.navHeld) effect.toggleFromBorder();
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
        refreshActivities();
        switch (a[0]) {
        case "open": open(); break;
        case "commit": commit(null); break;
        case "cancel": cancel(); break;
        case "toggle": toggle(); break;
        case "home": home(); break;
        case "origin": origin(); break;
        case "extents": zoomExtents(); break;
        case "pan": panBy(Number(a[1]), Number(a[2])); break;
        case "zoom": {
            const p = a.length >= 4 ? Qt.point(Number(a[2]), Number(a[3])) : cursorScreen();
            setZoom(Number(a[1]), p);
            break;
        }
        case "shift": shiftAll(Number(a[1]), Number(a[2])); break;
        case "slide": slide(Number(a[1]), Number(a[2])); break;
        case "enter": enterHere(); break;
        case "panstep": panStepBy(Number(a[1]), Number(a[2])); break;
        case "swipe": {
            // swipe DX DY PROGRESS | swipe DX DY end | swipe DX DY cancel
            if (a[3] === "end") swipeEnd(Number(a[1]), Number(a[2]), true);
            else if (a[3] === "cancel") swipeEnd(Number(a[1]), Number(a[2]), false);
            else swipeProgress(Number(a[1]), Number(a[2]), Number(a[3]));
            break;
        }
        case "drag": beginDrag(Number(a[1])); dragEntry(Number(a[1]), Number(a[2]), Number(a[3])); break;
        case "resize": requestSize(Number(a[1]), Number(a[2]), Number(a[3]), false, false); break;
        case "resetview": {
            // 1:1 only: forget the pan history so canvas == frame for this activity.
            if (visible) break;
            viewX = 0; viewY = 0;
            targets[currentActivity] = { x: 0, y: 0 };
            break;
        }
        case "placeby": {
            // placeby CAPTION_SUBSTR X Y [W H]: position (and size) an entry by caption.
            for (let i = 0; i < entries.length; ++i) {
                const e = entries[i];
                if (e.window.caption.indexOf(a[1]) === -1) continue;
                e.x = Number(a[2]); e.y = Number(a[3]);
                if (a.length >= 6) requestSize(i, Number(a[4]), Number(a[5]), false, false);
                revision++;
                break;
            }
            break;
        }
        case "place": {
            const e = entries[Number(a[1])];
            if (e) { e.x = Number(a[2]); e.y = Number(a[3]); revision++; }
            break;
        }
        case "frames": {
            // frames DX DY [activityIndex]
            const id = a.length >= 4 ? activityIds[Number(a[3])] : currentActivity;
            dragTarget(id, Number(a[1]), Number(a[2]));
            break;
        }
        case "pick": pick(entries[Number(a[1])]); break;
        case "focus": focusWindow(entries[Number(a[1])]); break;
        case "goto": gotoActivity(activityIds[Number(a[1])]); break;
        case "zoomto": zoomToActivity(activityIds[Number(a[1])]); break;
        case "newactivityat": newActivityAt(entries[Number(a[1])]); break;
        case "activate": {
            const all = KWin.Workspace.stackingOrder;
            for (let i = 0; i < all.length; ++i) {
                if (all[i].caption.indexOf(a[1]) !== -1) { KWin.Workspace.activeWindow = all[i]; break; }
            }
            break;
        }
        case "activity": KWin.Workspace.currentActivity = activityIds[Number(a[1])]; break;
        case "addactivity": addActivity(); break;
        case "rmactivity": removeActivity(activityIds[Number(a[1])]); break;
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
        case "arrange": arrange(a[1], Number(a[2]), Number(a[3])); break;
        case "snap": {
            const on = a[2] === "on";
            if (a[1] === "edges") snapEdges = on; else if (a[1] === "corners") snapCorners = on; else if (a[1] === "grid") snapGrid = on;
            break;
        }
        case "begindrag": beginDrag(Number(a[1])); break;
        case "sendto": sendTo(a[1] === "none" ? null : activityIds[Number(a[1])]); break;
        case "marquee": selectInRect(Number(a[1]), Number(a[2]), Number(a[3]), Number(a[4])); break;
        case "state": break;
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
        let s = "kwin-canvas state visible=" + visible + (quiet ? " quiet" : "") + (passthroughLive ? " passthrough" : "") + (planeLive ? " plane" : "") + " zoom=" + zoom.toFixed(4) + " view=(" + viewX.toFixed(1) + "," + viewY.toFixed(1) + ") activity=" + labelOf(currentActivity) + " entries=" + entries.length
            + " popups=" + appPopups.length + " menus=" + canvasMenus + " nav=" + (navHeld ? "hold" : "-") + " snap=" + (snapEdges ? "E" : "-") + (snapCorners ? "C" : "-") + (snapGrid ? "G" : "-")
            + " screens=" + KWin.Workspace.screens.length + " backdrop=" + backdropTiles.length
            + " cam=" + (camHasGoal ? "goal" : (camLive() ? "glide" : "-"))
            + " draglag=" + Math.round(Math.sqrt(dragLagX * dragLagX + dragLagY * dragLagY)) + " lean=" + dragLean.toFixed(2)
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
            s += "\n  [" + i + "] " + (isSelected(e) ? "*" : " ") + e.window.caption + " canvas=(" + e.x.toFixed(0) + "," + e.y.toFixed(0) + " " + e.width + "x" + e.height + ") frame=(" + g.x + "," + g.y + ") activity=" + labelOf(e.activity);
        }
        console.log(s);
    }

    onConfigurationChanged: {
        rebuildBindings();
        readSwipeFingers();
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
        refreshActivities();
        lastDebugSeq = configuration.DebugSeq;
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
            enabled: !grip.viewItem.spaceHeld
            cursorShape: gripDrag.active && grip.cursor === Qt.ArrowCursor ? Qt.ClosedHandCursor : grip.cursor
            onHoveredChanged: grip.viewItem.hoverCount += hovered ? 1 : -1
            Component.onDestruction: if (hovered) grip.viewItem.hoverCount -= 1
        }
        DragHandler {
            id: gripDrag
            target: null
            enabled: !grip.viewItem.spaceHeld
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
                last = Qt.point(0, 0);
                if (active) grip.dragStarted(); else grip.dragEnded();
            }
            onActiveTranslationChanged: {
                const t = activeTranslation;
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
        // A pan button held down (PanHold): this screen is being navigated.
        // Three sources, one per stretch of the gesture: the
        // tap tracker knows the press the moment it lands and the release the
        // moment it lifts, whether or not the pointer ever moves — a pointer
        // parked at a screen edge is the whole gesture — the pan drag is
        // active for the stretch where the tracker has handed the gesture to
        // the drag, and a drag on a control counts itself (portalDrags) for the
        // stretch where the drag has cancelled the tracker. None outlives the
        // button.
        readonly property bool navHeld: navHold.pressed || panDrag.active || portalDrags > 0
        onNavHeldChanged: effect.navHolds += navHeld ? 1 : -1
        Component.onDestruction: if (navHeld) effect.navHolds -= 1
        enabled: !effect.quiet
        focus: true
        Connections {
            target: effect
            function onVisibleChanged() { if (effect.visible) view.hoverCount = 0; }
        }

        // The plane's base: opaque, so nothing shows through to the real
        // desktop under the effect wherever no wallpaper tile reaches (past
        // BackdropReach, or with no shell behind the canvas at all). Below
        // everything, tiles included: a padding tile's z is -1 (it belongs
        // under the output's own tile), which would still put it behind this
        // rect at z 0, and then the backdrop beyond the screens would never be
        // drawn at all.
        Rectangle {
            anchors.fill: parent
            z: -100
            color: effect.configuration.Background
        }

        // Backdrop: the desktop's wallpaper, at every output's place on the
        // current activity's frames and tiled outward from the screens. At 1:1
        // this is the wallpaper the desktop is showing, pixel for pixel, so a
        // slide at 1:1 moves a desktop that looks untouched.
        Repeater {
            model: effect.backdropTiles
            delegate: Item {
                id: tile
                required property var modelData
                readonly property var spec: modelData
                x: { effect.revision; return (effect.peekTarget(effect.currentActivity).x + spec.dx - effect.viewX) * effect.zoom - view.sg.x; }
                y: { effect.revision; return (effect.peekTarget(effect.currentActivity).y + spec.dy - effect.viewY) * effect.zoom - view.sg.y; }
                width: spec.w * effect.zoom
                height: spec.h * effect.zoom
                z: spec.z
                KWin.DesktopBackground {
                    anchors.fill: parent
                    output: tile.spec.o
                    desktop: KWin.Workspace.currentDesktop
                    activity: effect.currentActivity || "default"
                }
            }
        }

        // The dim over the backdrop, so the desks and the windows stay the
        // subject. Zero while the canvas slides at 1:1, where the plane has to
        // be the desktop and nothing else.
        Rectangle {
            anchors.fill: parent
            visible: effect.backdropMode() === "wallpaper" && !effect.quiet
            color: effect.configuration.Background
            opacity: effect.backdropDim()
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
            running: view.navHeld && effect.edgePan && effect.canvasOpen
            onTriggered: effect.edgePanStep(view.sg, interval / 1000)
        }

        // Zoom at the cursor, whether or not a pan button is held: a notch up
        // zooms in, a notch down zooms out. (With the pass-through plugin
        // loaded, a pointer over a client area belongs to the window, the wheel
        // included, and this handler never sees it.)
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
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
                    // looks like the desktop until the camera moves.
                    Rectangle {
                        anchors.fill: parent
                        visible: !frame.bare
                        color: activityFrames.accent
                        opacity: (activityFrames.current ? 0.10 : 0.06) * Math.min(1, Math.max(0, (1 - effect.zoom) * 4))
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: !frame.bare
                        color: "transparent"
                        border.width: activityFrames.current ? 2 : 1
                        border.color: activityFrames.accent
                        opacity: activityFrames.current ? 0.95 : 0.6
                    }

                    // A gesture on the frame's own area (windows sit above and
                    // take their own taps).
                    TapHandler {
                        enabled: !view.spaceHeld
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
                x: { effect.revision; return (effect.entries[index].x - effect.viewX) * effect.zoom - view.sg.x; }
                y: { effect.revision; return (effect.entries[index].y - effect.viewY) * effect.zoom - view.sg.y; }
                width: { effect.revision; return effect.entries[index].width * effect.zoom; }
                height: { effect.revision; return effect.entries[index].height * effect.zoom; }
                visible: !effect.quiet || entry.activity === effect.currentActivity
                z: 1000 + index
                // Weight: the window lifts while the hand holds it, trails and
                // leans with the hand, and springs back when the hand stops.
                // The entry is exact throughout; this is the picture only.
                readonly property bool heavy: effect.windowPhysics && !effect.quiet
                property bool lifted: body.active && heavy
                scale: lifted ? 1.03 : (body.hovered && heavy ? 1.008 : 1)
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

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    visible: !effect.quiet
                    readonly property bool sel: { effect.selectionRev; return effect.isSelected(thumb.entry); }
                    border.width: sel ? 3 : (body.hovered || body.active ? 2 : 1)
                    border.color: sel ? Kirigami.Theme.highlightColor
                                : (body.hovered || body.active ? effect.activityColor(thumb.entry.activity) : "#40ffffff")
                }

                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 2
                    text: thumb.entry.window.caption
                    color: "#ffffff"
                    font.pixelSize: 12
                    visible: effect.zoom < 0.6 || body.hovered
                    style: Text.Outline
                    styleColor: "#000000"
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
                    visible: !effect.quiet
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
            } else if (effect.bound("cancel", k)) {
                effect.cancel();
            } else if (effect.bound("apply", k)) {
                effect.enterHere();
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
            PC3.MenuItem { text: "Arrange horizontally"; icon.name: "view-split-left-right"; onTriggered: effect.arrange("horizontal") }
            PC3.MenuItem { text: "Arrange vertically";   icon.name: "view-split-top-bottom"; onTriggered: effect.arrange("vertical") }
            PC3.MenuItem { text: "Tile";                 icon.name: "view-grid";             onTriggered: effect.arrange("tile") }
            PC3.Menu {
                title: "Grid"
                icon.name: "view-grid"
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
        }

        // HUD: a Plasma toolbar, top centre. Camera state, the actions, help
        // with the bindings, and the settings pages that own them.
        Rectangle {
            id: hud
            z: 100000
            visible: view.screen === effect.primaryScreen && !effect.quiet
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
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.85)
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
                K { text: effect.keyLabel(effect.configuration.KeyApply) }      V { text: "enter the location under the screen centre" }
                K { text: effect.keyLabel(effect.configuration.KeyCancel) }     V { text: "back to where you were, nothing moved" }
                K { text: effect.keyLabel(effect.configuration.KeyHome) }       V { text: "look through this activity's frames" }
                K { text: effect.keyLabel(effect.configuration.KeyOrigin) }     V { text: "camera to the canvas origin" }
                K { text: effect.keyLabel(effect.configuration.KeyFit) }        V { text: "zoom to fit" }
            }
        }
    }
}
