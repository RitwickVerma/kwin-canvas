/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    The map: the plane drawn with its empty ground squeezed (layout.js), so
    every cluster is legible however far apart they sit. Layers, bottom to
    top: the folds (a dashed line where empty ground was squeezed), the
    activities' frames, each cluster's tinted card, the windows' sheets, the
    screens' frames, the clusters' labels, and what the hand is doing.

    The hand: a click on a window goes to it, on the ground brings that spot
    to the middle of the screen, on a cluster's label goes to the cluster. A
    drag moves the window to where it is dropped (into another cluster too); a
    drag of a screen's frame moves the desk there; with the map zoomed, a drag
    of the ground pans it. A middle click brings a window here; a right click
    offers going, bringing, minimizing, keeping above and closing. The wheel
    zooms the map about the pointer. The keyboard (main.qml's search field)
    walks the windows with the arrows and goes with Enter.
*/

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "../code/layout.js" as MapLayout

Item {
    id: view

    // The reading (main.qml's plane) and main.qml's root for the actions and the icons.
    property var plane: null
    property var ctl: null
    property bool interactive: true
    property bool previews: false
    property bool toScale: false
    property bool showMinimized: true
    property string filter: ""
    // The keyboard's pick, the window under the pointer, the window being dragged.
    property string selectedId: ""
    property string hoveredId: ""
    property string dragId: ""
    // The cluster under the pointer (its label hovered, or a dragged window over its card), or 0.
    property int hotCluster: 0
    // A click did its job (went somewhere): the popup can close.
    signal activated()

    clip: true
    readonly property int iconsRev: ctl ? ctl.iconsRev : 0
    readonly property color ink: Kirigami.Theme.textColor
    readonly property color accent: Kirigami.Theme.highlightColor

    // ---- the geometry ----
    readonly property var lay: MapLayout.planeLayout(plane, toScale)
    readonly property real aspect: lay.x.length / Math.max(1, lay.y.length)
    readonly property real pad: interactive ? Kirigami.Units.gridUnit : 2
    // The tray of minimized windows takes the map's foot when it shows; the plane fits above it.
    readonly property real footRoom: tray.visible ? tray.height + Kirigami.Units.smallSpacing : 0
    readonly property real fit: Math.max(1e-6, Math.min((width - 2 * pad) / lay.x.length, (height - footRoom - 2 * pad) / lay.y.length))
    // The map's own zoom, about a point: k times the fit, centred on (cu, cv) of the map's axes.
    property real zoomK: 1
    property real cu: 0
    property real cv: 0
    readonly property bool zoomed: zoomK > 1.001
    readonly property real s: fit * zoomK
    readonly property real centreU: zoomed ? cu : lay.x.length / 2
    readonly property real centreV: zoomed ? cv : lay.y.length / 2
    function mx(x) { return width / 2 + (lay.x.to(x) - centreU) * s; }
    function my(y) { return (height - footRoom) / 2 + (lay.y.to(y) - centreV) * s; }
    function planeX(px) { return lay.x.from(centreU + (px - width / 2) / s); }
    function planeY(py) { return lay.y.from(centreV + (py - (height - footRoom) / 2) / s); }
    function resetView() { zoomK = 1; }

    // Sheets glide when the plane moves a window, not while the map itself is zoomed, panned or
    // resized, which moves every sheet at once and has to follow the hand.
    property bool glide: true
    // Every layer that moves with the plane glides for this long and on the same curve, so the
    // screens' frames, the cards, the labels and the windows stay in register throughout.
    readonly property int glideMs: Kirigami.Units.longDuration
    function holdGlide() { glide = false; glideTimer.restart(); }
    Timer { id: glideTimer; interval: 220; onTriggered: view.glide = true }
    onWidthChanged: holdGlide()
    onHeightChanged: holdGlide()

    function matchesFilter(caption, app) { return filter === "" || MapLayout.matches(filter, caption, app); }
    // Eight tints that read on light and dark glass, one per cluster number.
    readonly property var tints: ["#4ea3ff", "#ff8a4c", "#55d38a", "#c77dff", "#ffc94d", "#3fd6cf", "#ff6b8b", "#9aa7ff"]
    function tintOf(n) { return tints[Math.max(0, n - 1) % tints.length]; }

    // ---- the models: the windows by id and the clusters by number, updated in place ----
    // Rows keep their delegates across readings (a reading comes up to ten times a second while
    // a window is dragged), so a live picture is not restarted by every focus change.
    ListModel { id: winModel }
    ListModel { id: clusterModel }
    function syncModel(model, items, key) {
        const want = {};
        for (let i = 0; i < items.length; ++i) want[items[i][key]] = true;
        for (let r = model.count - 1; r >= 0; --r) if (!want[model.get(r)[key]]) model.remove(r);
        const have = {};
        for (let r = 0; r < model.count; ++r) have[model.get(r)[key]] = r;
        for (let i = 0; i < items.length; ++i) {
            const r = have[items[i][key]];
            if (r === undefined) model.append(items[i]);
            else model.set(r, items[i]);
        }
    }
    function sync() {
        const ws = plane ? plane.windows : [];
        const items = [];
        for (let i = 0; i < ws.length; ++i) {
            const w = ws[i];
            // Minimized windows are not on the plane: the tray holds them.
            if (w.min) continue;
            items.push({ wid: String(w.id), caption: String(w.caption || ""), app: String(w.app || ""),
                         px: w.x, py: w.y, pw: w.w, ph: w.h, active: w.active ? 1 : 0,
                         here: w.here === 0 ? 0 : 1, min: w.min ? 1 : 0, above: w.above ? 1 : 0, pin: w.pin ? 1 : 0,
                         nocap: w.nocap ? 1 : 0, c: w.c || 0, order: i, rank: 999 });
        }
        // The live pictures go to the biggest windows first, a dozen at most.
        const byArea = items.filter(function (it) { return !it.min && !it.nocap; })
                            .sort(function (a, b) { return b.pw * b.ph - a.pw * a.ph; });
        for (let k = 0; k < byArea.length; ++k) byArea[k].rank = k;
        syncModel(winModel, items, "wid");
        const cs = plane && plane.clusters ? plane.clusters : [];
        syncModel(clusterModel, cs.map(function (c) {
            return { n: c.n, name: String(c.name || ""), px: c.x, py: c.y, pw: c.w, ph: c.h, count: c.count || 0,
                     landId: String(c.focus || ""), active: c.active ? 1 : 0 };
        }), "n");
        if (selectedId && rowOf(selectedId) === null) selectedId = "";
        if (hoveredId && rowOf(hoveredId) === null) hoveredId = "";
    }
    onPlaneChanged: sync()
    // A reading that was there before the view (the popup opened after it came) is drawn at once.
    Component.onCompleted: sync()
    function rowOf(id) {
        for (let r = 0; r < winModel.count; ++r) if (winModel.get(r).wid === id) return winModel.get(r);
        return null;
    }

    // ---- what is where on the map ----
    function sheetAt(px, py) {
        let best = null;
        for (let r = 0; r < winModel.count; ++r) {
            const w = winModel.get(r);
            const x = mx(w.px), y = my(w.py);
            if (px >= x && px < Math.max(x + 3, mx(w.px + w.pw)) && py >= y && py < Math.max(y + 3, my(w.py + w.ph))
                && (!best || w.order > best.order)) best = w;
        }
        return best;
    }
    function cameraAt(px, py) {
        const cams = plane ? plane.camera : [];
        for (let i = 0; i < cams.length; ++i) {
            const c = cams[i];
            if (px >= mx(c[0]) && px < mx(c[0] + c[2]) && py >= my(c[1]) && py < my(c[1] + c[3])) return i;
        }
        return -1;
    }
    function clusterAt(px, py) {
        for (let r = 0; r < clusterModel.count; ++r) {
            const c = clusterModel.get(r);
            if (px >= mx(c.px) && px < mx(c.px + c.pw) && py >= my(c.py) && py < my(c.py + c.ph)) return c.n;
        }
        return 0;
    }

    // ---- the keyboard ----
    function drawnRects(onlyMatches) {
        const out = [];
        for (let r = 0; r < winModel.count; ++r) {
            const w = winModel.get(r);
            if (onlyMatches && !matchesFilter(w.caption, w.app)) continue;
            out.push({ id: w.wid, x: mx(w.px), y: my(w.py), w: mx(w.px + w.pw) - mx(w.px), h: my(w.py + w.ph) - my(w.py),
                       active: w.active, order: w.order });
        }
        return out;
    }
    function topmostMatch() {
        const rs = drawnRects(true);
        let best = null;
        for (let i = 0; i < rs.length; ++i) if (!best || rs[i].order > best.order) best = rs[i];
        return best ? best.id : "";
    }
    onFilterChanged: selectedId = filter === "" ? "" : topmostMatch()
    function step(dir) {
        const rs = drawnRects(true);
        if (!rs.length) return;
        let from = null;
        for (let i = 0; i < rs.length; ++i) if (rs[i].id === selectedId) from = rs[i];
        if (!from) for (let i = 0; i < rs.length; ++i) if (rs[i].active) from = rs[i];
        if (!from) { selectedId = topmostMatch(); return; }
        const id = MapLayout.stepTowards(from, rs, dir);
        selectedId = id || from.id;
    }
    function enter() {
        const id = selectedId || topmostMatch();
        if (!id || !ctl) return;
        ctl.focusWindow(id);
        activated();
    }

    // ---- the layers ----
    // The drawn plane in one item, so the frosted label can blur what lies under it.
    Item {
        id: scene
        anchors.fill: parent
        // The folds: where empty ground was squeezed, a faint dashed seam across the map.
        Repeater {
            model: view.interactive ? view.lay.x.folds.length : 0
            delegate: Shape {
                required property int index
                x: view.width / 2 + (view.lay.x.folds[index] - view.centreU) * view.s
                Behavior on x { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                width: 1
                height: view.height
                ShapePath {
                    strokeColor: Qt.rgba(view.ink.r, view.ink.g, view.ink.b, 0.18)
                    strokeWidth: 1
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2, 5]
                    fillColor: "transparent"
                    PathLine { x: 0; y: view.height }
                }
            }
        }
        Repeater {
            model: view.interactive ? view.lay.y.folds.length : 0
            delegate: Shape {
                required property int index
                y: (view.height - view.footRoom) / 2 + (view.lay.y.folds[index] - view.centreV) * view.s
                Behavior on y { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                width: view.width
                height: 1
                ShapePath {
                    strokeColor: Qt.rgba(view.ink.r, view.ink.g, view.ink.b, 0.18)
                    strokeWidth: 1
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2, 5]
                    fillColor: "transparent"
                    PathLine { x: view.width; y: 0 }
                }
            }
        }

        // The activities' frames, in their palette colours (by index: every reading is a new array).
        Repeater {
            model: view.plane ? view.plane.frames.length : 0
            delegate: Rectangle {
                required property int index
                readonly property var f: (view.plane && view.plane.frames[index]) || [0, 0, 0, 0, "#000000", 0]
                readonly property color tint: f[4]
                x: view.mx(f[0])
                y: view.my(f[1])
                width: view.mx(f[0] + f[2]) - view.mx(f[0])
                height: view.my(f[1] + f[3]) - view.my(f[1])
                Behavior on x { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                z: 2
                radius: 4
                color: Qt.rgba(tint.r, tint.g, tint.b, 0.12)
                border.width: 1
                border.color: Qt.rgba(tint.r, tint.g, tint.b, f[5] ? 0.8 : 0.4)
            }
        }

        // The clusters' cards: a tinted pane of glass behind each cluster's windows.
        Repeater {
            model: clusterModel
            delegate: Item {
                id: card
                required property int n
                required property real px
                required property real py
                required property real pw
                required property real ph
                required property int active
                readonly property color tint: view.tintOf(n)
                readonly property real margin: view.interactive ? Math.max(5, Math.min(14, view.s * 180)) : 1.5
                readonly property bool hot: view.hotCluster === n
                x: view.mx(px) - margin
                y: view.my(py) - margin
                width: view.mx(px + pw) - view.mx(px) + 2 * margin
                height: view.my(py + ph) - view.my(py) + 2 * margin
                Behavior on x { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                z: 3
                RectangularShadow {
                    anchors.fill: pane
                    visible: card.active === 1 && view.interactive
                    radius: pane.radius
                    blur: 16
                    color: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.35)
                }
                Rectangle {
                    id: pane
                    anchors.fill: parent
                    radius: Math.min(12, Math.min(width, height) / 5)
                    color: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, card.hot ? 0.24 : (card.active === 1 ? 0.17 : 0.1))
                    border.width: card.hot || card.active === 1 ? 1.5 : 1
                    border.color: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, card.hot || card.active === 1 ? 0.95 : 0.5)
                    Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                }
            }
        }

        // The windows.
        Repeater {
            model: winModel
            delegate: WindowSheet { map: view }
        }

        // The screens: what each one shows now. A drag of one moves the desk there.
        Repeater {
            model: view.plane ? view.plane.camera.length : 0
            delegate: Rectangle {
                required property int index
                readonly property var c: (view.plane && view.plane.camera[index]) || [0, 0, 0, 0]
                x: view.mx(c[0])
                y: view.my(c[1])
                // From where it is going, as the windows' sheets (x glides).
                width: Math.max(4, view.mx(c[0] + c[2]) - view.mx(c[0]))
                height: Math.max(4, view.my(c[1] + c[3]) - view.my(c[1]))
                Behavior on x { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
                z: 500
                radius: 3
                color: Qt.rgba(view.ink.r, view.ink.g, view.ink.b, hand.dragKind === "camera" && hand.dragIndex === index ? 0.02 : 0.05)
                border.width: view.interactive ? 1.5 : 1
                border.color: Qt.rgba(view.ink.r, view.ink.g, view.ink.b, 0.9)
            }
        }
    }

    // ---- the hand ----
    MouseArea {
        id: hand
        anchors.fill: parent
        z: 550
        enabled: view.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: dragKind === "pan" || dragKind === "camera" ? Qt.ClosedHandCursor
                   : (view.hoveredId !== "" ? Qt.PointingHandCursor : (overCamera ? Qt.OpenHandCursor : Qt.ArrowCursor))

        property point at: Qt.point(0, 0)
        property point now: Qt.point(0, 0)
        property int button: Qt.NoButton
        property string pressId: ""
        property int pressCamera: -1
        // "" (a click, so far), "sheet", "camera" or "pan".
        property string dragKind: ""
        property int dragIndex: -1
        // The grab: the pointer's offset from what it holds, on the plane and drawn.
        property real grabX: 0
        property real grabY: 0
        property real offX: 0
        property real offY: 0
        property real ghostW: 0
        property real ghostH: 0
        property real startCu: 0
        property real startCv: 0
        property bool overCamera: false

        function hover(px, py) {
            const w = view.sheetAt(px, py);
            view.hoveredId = w ? w.wid : "";
            overCamera = !w && view.cameraAt(px, py) >= 0;
        }
        onPositionChanged: (mouse) => {
            now = Qt.point(mouse.x, mouse.y);
            if (!pressed) { hover(mouse.x, mouse.y); return; }
            if (button !== Qt.LeftButton) return;
            if (dragKind === "" && Math.hypot(mouse.x - at.x, mouse.y - at.y) > Kirigami.Units.smallSpacing * 2) {
                const w = pressId !== "" ? view.rowOf(pressId) : null;
                if (w && !w.min && !w.pin) {
                    dragKind = "sheet";
                    view.dragId = w.wid;
                    grabX = view.planeX(at.x) - w.px;
                    grabY = view.planeY(at.y) - w.py;
                    offX = at.x - view.mx(w.px);
                    offY = at.y - view.my(w.py);
                    ghostW = Math.max(3, view.mx(w.px + w.pw) - view.mx(w.px));
                    ghostH = Math.max(3, view.my(w.py + w.ph) - view.my(w.py));
                } else if (pressId === "" && pressCamera >= 0) {
                    const c = view.plane.camera[pressCamera];
                    dragKind = "camera";
                    dragIndex = pressCamera;
                    grabX = view.planeX(at.x) - (c[0] + c[2] / 2);
                    grabY = view.planeY(at.y) - (c[1] + c[3] / 2);
                    offX = at.x - view.mx(c[0]);
                    offY = at.y - view.my(c[1]);
                    ghostW = view.mx(c[0] + c[2]) - view.mx(c[0]);
                    ghostH = view.my(c[1] + c[3]) - view.my(c[1]);
                } else if (pressId === "" && view.zoomed) {
                    dragKind = "pan";
                    startCu = view.cu;
                    startCv = view.cv;
                }
                view.hoveredId = "";
            }
            if (dragKind === "sheet") view.hotCluster = view.clusterAt(mouse.x, mouse.y);
            else if (dragKind === "pan") {
                view.holdGlide();
                view.cu = startCu - (mouse.x - at.x) / view.s;
                view.cv = startCv - (mouse.y - at.y) / view.s;
            }
        }
        onPressed: (mouse) => {
            at = Qt.point(mouse.x, mouse.y);
            now = at;
            button = mouse.button;
            const w = view.sheetAt(mouse.x, mouse.y);
            pressId = w ? w.wid : "";
            pressCamera = w ? -1 : view.cameraAt(mouse.x, mouse.y);
            dragKind = "";
        }
        onReleased: (mouse) => {
            const kind = dragKind;
            dragKind = "";
            dragIndex = -1;
            view.dragId = "";
            view.hotCluster = 0;
            if (kind === "sheet") {
                view.ctl.act("move", { id: pressId, x: Math.round(view.planeX(mouse.x) - grabX), y: Math.round(view.planeY(mouse.y) - grabY) });
                return;
            }
            if (kind === "camera") {
                view.ctl.go(view.planeX(mouse.x) - grabX, view.planeY(mouse.y) - grabY);
                return;
            }
            if (kind === "pan") return;
            if (button === Qt.RightButton) {
                const row = pressId !== "" ? view.rowOf(pressId) : null;
                if (row) menu.show(row, mouse.x, mouse.y);
                return;
            }
            if (button === Qt.MiddleButton) {
                if (pressId !== "") { view.ctl.act("bring", { id: pressId }); view.activated(); }
                return;
            }
            if (pressId !== "") view.ctl.focusWindow(pressId);
            else view.ctl.go(view.planeX(mouse.x), view.planeY(mouse.y));
            view.activated();
        }
        onCanceled: {
            dragKind = "";
            view.dragId = "";
            view.hotCluster = 0;
        }
        onExited: if (!pressed) { view.hoveredId = ""; overCamera = false; }
        onWheel: (wheel) => {
            const d = wheel.angleDelta.y;
            if (d === 0) return;
            const u = view.centreU + (wheel.x - view.width / 2) / view.s;
            const v = view.centreV + (wheel.y - (view.height - view.footRoom) / 2) / view.s;
            const k = Math.max(1, Math.min(16, view.zoomK * Math.pow(1.0015, d)));
            view.holdGlide();
            if (k <= 1.001) { view.zoomK = 1; return; }
            view.cu = u - (wheel.x - view.width / 2) / (view.fit * k);
            view.cv = v - (wheel.y - (view.height - view.footRoom) / 2) / (view.fit * k);
            view.zoomK = k;
        }
    }

    // The clusters' labels: the canvas's number for the cluster and its name; a click goes there.
    Repeater {
        model: view.interactive ? clusterModel : null
        delegate: Rectangle {
            id: chip
            required property int n
            required property string name
            required property real px
            required property real py
            required property int count
            // The window a click on the cluster lands on ("focus" in the reading; an Item's own
            // focus is final and cannot be a role's name).
            required property string landId
            required property int active
            readonly property color tint: view.tintOf(n)
            readonly property bool dark: tint.r * 0.299 + tint.g * 0.587 + tint.b * 0.114 < 0.62
            readonly property real margin: Math.max(5, Math.min(14, view.s * 180))
            x: Math.max(2, Math.min(view.width - width - 2, view.mx(px) - margin))
            y: Math.max(2, view.my(py) - margin - height * 0.6)
            Behavior on x { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: view.glide; NumberAnimation { duration: view.glideMs; easing.type: Easing.OutCubic } }
            z: 600
            height: label.implicitHeight + 4
            width: label.width + 10
            radius: height / 2
            color: Qt.rgba(tint.r, tint.g, tint.b, chipHover.hovered ? 1 : 0.88)
            // One label, the number bold: two labels in a row sat on different baselines.
            PlasmaComponents3.Label {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                x: 5
                width: Math.min(implicitWidth, Kirigami.Units.gridUnit * 10)
                font: Kirigami.Theme.smallFont
                color: chip.dark ? "white" : "#1b1b1b"
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: {
                    view.iconsRev;
                    const name = view.ctl ? view.ctl.clusterLabel({ name: chip.name, focus: chip.landId, count: chip.count }) : "";
                    const safe = String(name).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                    return "<b>" + chip.n + "</b>" + (safe ? "&nbsp;&nbsp;" + safe : "");
                }
            }
            HoverHandler {
                id: chipHover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: view.hotCluster = hovered ? chip.n : (view.hotCluster === chip.n ? 0 : view.hotCluster)
            }
            TapHandler {
                onTapped: { view.ctl.goCluster(chip.n); view.activated(); }
            }
        }
    }

    // Minimized windows are not on the plane, so not on the map's ground: a tray along its foot
    // holds them, the most recently minimized first, and a click brings one back and goes to it.
    readonly property var minimized: {
        const out = [];
        const ws = plane ? plane.windows : [];
        for (let i = ws.length - 1; i >= 0; --i) if (ws[i].min) out.push(ws[i]);
        return out;
    }
    Rectangle {
        id: tray
        visible: view.interactive && view.showMinimized && view.minimized.length > 0
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Kirigami.Units.smallSpacing
        z: 600
        height: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing * 2
        width: Math.min(view.width - Kirigami.Units.smallSpacing * 2, trayRow.implicitWidth + Kirigami.Units.largeSpacing)
        radius: height / 2
        clip: true
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.72)
        border.width: 1
        border.color: Qt.rgba(view.ink.r, view.ink.g, view.ink.b, 0.2)
        Row {
            id: trayRow
            anchors.verticalCenter: parent.verticalCenter
            x: Kirigami.Units.largeSpacing / 2
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.small
                height: width
                opacity: 0.55
                source: "window-minimize"
            }
            Repeater {
                model: view.minimized.length
                delegate: Kirigami.Icon {
                    id: trayIcon
                    required property int index
                    readonly property var w: view.minimized[index] || ({ id: "", app: "", caption: "" })
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: width
                    active: trayHover.hovered
                    source: { view.iconsRev; return view.ctl ? view.ctl.iconFor(w.id, w.app) : ""; }
                    HoverHandler { id: trayHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: { view.ctl.focusWindow(trayIcon.w.id); view.activated(); }
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: (point) => {
                            const p = trayIcon.mapToItem(view, point.position.x, point.position.y);
                            menu.show(trayIcon.w, p.x, p.y);
                        }
                    }
                    PlasmaComponents3.ToolTip.text: i18n("%1 · click to bring it back", w.caption)
                    PlasmaComponents3.ToolTip.visible: trayHover.hovered
                    PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }
        }
    }

    // A dragged window or screen frame, under the hand.
    Rectangle {
        visible: hand.dragKind === "sheet" || hand.dragKind === "camera"
        x: hand.now.x - hand.offX
        y: hand.now.y - hand.offY
        width: hand.ghostW
        height: hand.ghostH
        z: 700
        radius: 4
        color: hand.dragKind === "sheet" ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.35) : Qt.rgba(view.ink.r, view.ink.g, view.ink.b, 0.08)
        border.width: 1.5
        border.color: hand.dragKind === "sheet" ? view.accent : view.ink
        layer.enabled: visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.6
            shadowOpacity: 0.5
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            readonly property real size: Math.min(32, Math.min(parent.width, parent.height) * 0.5)
            width: size
            height: size
            visible: hand.dragKind === "sheet" && size >= 9
            source: { const w = view.dragId ? view.rowOf(view.dragId) : null; return w && view.ctl ? view.ctl.iconFor(w.wid, w.app) : ""; }
        }
    }

    // What the pointer is on: the window's icon, caption and app, and what the hand can do, on
    // frosted glass: the map under the label, blurred.
    Rectangle {
        id: tip
        readonly property var w: { view.iconsRev; return view.hoveredId ? view.rowOf(view.hoveredId) : null; }
        visible: view.interactive && w !== null && hand.dragKind === ""
        z: 800
        x: Math.max(4, Math.min(view.width - width - 4, hand.now.x + 14))
        y: hand.now.y + 18 + height > view.height ? hand.now.y - height - 8 : hand.now.y + 18
        width: Math.min(view.width - 8, tipColumn.implicitWidth + Kirigami.Units.largeSpacing * 2)
        height: tipColumn.implicitHeight + Kirigami.Units.smallSpacing * 2
        radius: Kirigami.Units.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(view.ink.r, view.ink.g, view.ink.b, 0.2)
        MultiEffect {
            anchors.fill: parent
            source: ShaderEffectSource {
                sourceItem: scene
                sourceRect: Qt.rect(tip.x, tip.y, tip.width, tip.height)
                live: tip.visible
                hideSource: false
            }
            visible: tip.visible
            blurEnabled: true
            blur: 1.0
            blurMax: 32
            maskEnabled: true
            maskSource: tipMask
        }
        Rectangle {
            id: tipMask
            anchors.fill: parent
            radius: parent.radius
            visible: false
            layer.enabled: true
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.8)
        }
        Column {
            id: tipColumn
            anchors.centerIn: parent
            width: Math.min(implicitWidth, view.width - 8 - Kirigami.Units.largeSpacing * 2)
            spacing: 2
            Row {
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    source: tip.w && view.ctl ? view.ctl.iconFor(tip.w.wid, tip.w.app) : ""
                }
                PlasmaComponents3.Label {
                    text: tip.w ? tip.w.caption : ""
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, Kirigami.Units.gridUnit * 20)
                }
            }
            PlasmaComponents3.Label {
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: tip.w && tip.w.min ? i18n("Minimized · click to bring it back")
                                         : i18n("Click: go · Drag: move · Middle: bring here · Right: more")
            }
        }
    }

    // A window's other actions.
    PlasmaExtras.Menu {
        id: menu
        visualParent: view
        property string wid: ""
        property bool minimized: false
        property bool kept: false
        function show(w, x, y) {
            wid = String(w.wid !== undefined ? w.wid : w.id);
            minimized = !!w.min;
            kept = !!w.above;
            open(x, y);
        }
        PlasmaExtras.MenuItem {
            text: i18n("Go to window")
            icon: "go-jump"
            onClicked: { view.ctl.focusWindow(menu.wid); view.activated(); }
        }
        PlasmaExtras.MenuItem {
            text: i18n("Bring here")
            icon: "transform-move"
            onClicked: { view.ctl.act("bring", { id: menu.wid }); view.activated(); }
        }
        PlasmaExtras.MenuItem {
            text: menu.minimized ? i18n("Restore") : i18n("Minimize")
            icon: "window-minimize"
            onClicked: view.ctl.act("minimize", { id: menu.wid })
        }
        PlasmaExtras.MenuItem {
            text: i18n("Keep above others")
            icon: "window-keep-above"
            checkable: true
            checked: menu.kept
            onClicked: view.ctl.act("above", { id: menu.wid })
        }
        PlasmaExtras.MenuItem { separator: true }
        PlasmaExtras.MenuItem {
            text: i18n("Close")
            icon: "window-close"
            onClicked: view.ctl.act("close", { id: menu.wid })
        }
    }
}
