/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    The canvas's minimap as a widget: the whole plane at a glance - the
    activities' frames in their palette colours, every window as a sheet,
    the screen's own rectangle - on the desktop, or small in a panel with
    the full map a click away. A click on a window flies to it and focuses
    it; a click on the ground brings that spot to the middle of the screen.

    The map is the canvas's own: the pass-through plugin's Map object
    (/KWinCanvas/Map) asks the effect, which is the one authority on where
    things sit on the plane, and says when anything on it moved. The widget
    reads again on that signal, so there is no polling and no process per
    read; only while the plugin is missing does it look again, every ten
    seconds.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    // Big enough on the desktop to read; in a panel the compact map stands in.
    switchWidth: Kirigami.Units.gridUnit * 8
    switchHeight: Kirigami.Units.gridUnit * 4
    toolTipMainText: i18n("Canvas Map")
    toolTipSubText: plane ? i18n("Click to open the map") : i18n("Needs the kwin-canvas pass-through plugin")

    // The last reading, parsed: {open, camera, frames, windows}, or null.
    property var plane: null
    // The world the map fits: the frames, the windows and the camera together.
    readonly property rect world: {
        if (!plane) return Qt.rect(0, 0, 1, 1);
        let l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
        const grow = function (x, y, w, h) {
            l = Math.min(l, x); t = Math.min(t, y);
            r = Math.max(r, x + w); b = Math.max(b, y + h);
        };
        for (const f of plane.frames) grow(f[0], f[1], f[2], f[3]);
        for (const c of plane.camera) grow(c[0], c[1], c[2], c[3]);
        for (const w of plane.windows) grow(w.x, w.y, w.w, w.h);
        if (l === Infinity) return Qt.rect(0, 0, 1, 1);
        return Qt.rect(l, t, Math.max(1, r - l), Math.max(1, b - t));
    }
    readonly property real aspect: Math.max(0.5, Math.min(6, world.width / world.height))

    readonly property var mapObject: ({ service: "org.kde.KWin", path: "/KWinCanvas/Map", iface: "org.kde.kwin.canvas.Map" })
    function message(member, args, signature) {
        return { service: mapObject.service, path: mapObject.path, iface: mapObject.iface,
                 member: member, arguments: args, signature: signature };
    }

    // One read in flight at a time; a change that lands meanwhile asks for
    // one more read after it, never a queue.
    property bool reading: false
    property bool readAgain: false
    function read() {
        if (reading) { readAgain = true; return; }
        reading = true;
        const reply = DBus.SessionBus.asyncCall(message("read", [], ""));
        reply.finished.connect(() => {
            let next = null;
            if (!reply.isError) {
                try { next = JSON.parse(String(reply.value)); } catch (err) { next = null; }
            }
            root.plane = next && next.frames ? next : null;
            // Destroyed here: the connection holds the reply, which would
            // otherwise outlive the read.
            reply.destroy();
            root.reading = false;
            if (root.readAgain) { root.readAgain = false; root.read(); }
        });
    }
    // A click's call answers nothing worth reading; the reply is let go when it lands.
    // The signature is the whole argument list as one tuple: the module encodes the
    // arguments against it ("dd" sends none), and without one it introspects first.
    function send(member, args, signature) {
        const reply = DBus.SessionBus.asyncCall(message(member, args, signature));
        reply.finished.connect(() => reply.destroy());
    }
    function go(x, y) { send("go", [x, y], "(dd)"); }
    function focusWindow(id) { send("focus", [id], "(s)"); }

    Component.onCompleted: read()
    DBus.SignalWatcher {
        service: root.mapObject.service
        path: root.mapObject.path
        iface: root.mapObject.iface
        function dbuschanged() { root.read(); }
    }
    // KWin restarted: the map is a new object, and the plugin registers it a
    // moment after KWin takes its name, which the retry below covers.
    DBus.DBusServiceWatcher {
        watchedService: root.mapObject.service
        onRegisteredChanged: if (registered) root.read()
    }
    Timer {
        interval: 10000
        repeat: true
        running: root.plane === null
        onTriggered: root.read()
    }

    // The map itself, for both forms: the compact one in a panel is a glance
    // that opens the full map, the full one takes the clicks.
    component PlaneMap: Item {
        id: map
        property bool interactive: true
        readonly property real pad: interactive ? Kirigami.Units.smallSpacing * 2 : 1
        readonly property real sc: Math.min((width - 2 * pad) / root.world.width, (height - 2 * pad) / root.world.height)
        readonly property real ox: (width - root.world.width * sc) / 2
        readonly property real oy: (height - root.world.height * sc) / 2
        function mx(x) { return ox + (x - root.world.x) * sc; }
        function my(y) { return oy + (y - root.world.y) * sc; }
        // The topmost window under a point of the map, or null.
        function windowAt(px, py) {
            if (!root.plane) return null;
            const ws = root.plane.windows;
            for (let i = ws.length - 1; i >= 0; --i) {
                const w = ws[i];
                const x = mx(w.x), y = my(w.y);
                if (px >= x && px < x + Math.max(2, w.w * sc) && py >= y && py < y + Math.max(2, w.h * sc)) return w;
            }
            return null;
        }

        Rectangle {
            anchors.fill: parent
            radius: map.interactive ? Kirigami.Units.cornerRadius : 3
            color: Qt.rgba(0.07, 0.07, 0.09, 0.42)
            border.width: map.interactive ? 1 : 0
            border.color: "#3affffff"
        }
        Repeater {
            model: root.plane ? root.plane.frames : []
            delegate: Rectangle {
                required property var modelData
                readonly property color accent: modelData[4]
                x: map.mx(modelData[0])
                y: map.my(modelData[1])
                width: modelData[2] * map.sc
                height: modelData[3] * map.sc
                color: Qt.rgba(accent.r, accent.g, accent.b, 0.30)
                border.width: 1
                border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.75)
            }
        }
        // The sheets, bottom to top. Another activity's windows are fainter:
        // they are on the plane, but not on the desk the screen shows.
        Repeater {
            model: root.plane ? root.plane.windows : []
            delegate: Rectangle {
                required property var modelData
                x: map.mx(modelData.x)
                y: map.my(modelData.y)
                width: Math.max(1.6, modelData.w * map.sc)
                height: Math.max(1.6, modelData.h * map.sc)
                radius: 1
                color: Qt.rgba(1, 1, 1, modelData.here ? 0.5 : 0.22)
                border.width: map.interactive ? 0.6 : 0
                border.color: modelData.active ? "#e8ffffff" : (hover.hoveredId === modelData.id ? "#b8ffffff" : "#4affffff")
            }
        }
        // What the screens show now: a soft halo under a white outline, the
        // lens's camera rectangle.
        Repeater {
            model: root.plane ? root.plane.camera : []
            delegate: Rectangle {
                required property var modelData
                x: map.mx(modelData[0])
                y: map.my(modelData[1])
                width: modelData[2] * map.sc
                height: modelData[3] * map.sc
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                border.color: "#e8ffffff"
            }
        }

        HoverHandler {
            id: hover
            enabled: map.interactive
            property string hoveredId: ""
            property string hoveredCaption: ""
            cursorShape: Qt.PointingHandCursor
            onPointChanged: {
                const w = hovered ? map.windowAt(point.position.x, point.position.y) : null;
                hoveredId = w ? w.id : "";
                hoveredCaption = w ? w.caption : "";
            }
            onHoveredChanged: if (!hovered) { hoveredId = ""; hoveredCaption = ""; }
        }
        PlasmaComponents3.ToolTip.text: hover.hoveredCaption
        PlasmaComponents3.ToolTip.visible: map.interactive && hover.hoveredCaption !== ""
        PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay

        TapHandler {
            enabled: map.interactive && root.plane !== null
            onTapped: (eventPoint) => {
                const p = eventPoint.position;
                const w = map.windowAt(p.x, p.y);
                if (w) root.focusWindow(w.id);
                else root.go(root.world.x + (p.x - map.ox) / map.sc, root.world.y + (p.y - map.oy) / map.sc);
                // The popup has done its work: the desk is where the eye goes next.
                if (root.compactRepresentationItem && root.compactRepresentationItem.visible) root.expanded = false;
            }
        }
    }

    compactRepresentation: MouseArea {
        readonly property bool horizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        Layout.minimumWidth: horizontal ? Math.round(height * root.aspect) : -1
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: horizontal ? -1 : Math.round(width / root.aspect)
        Layout.preferredHeight: Layout.minimumHeight
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        PlaneMap {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing / 2
            interactive: false
            visible: root.plane !== null
        }
        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            visible: root.plane === null
            opacity: 0.5
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 10
        Layout.minimumHeight: Kirigami.Units.gridUnit * 5
        // A wide plane (an ultrawide screen, desks laid out in a row) gets a
        // wider map rather than a thinner strip.
        Layout.preferredWidth: Kirigami.Units.gridUnit * Math.min(48, Math.max(20, 10 * root.aspect))
        Layout.preferredHeight: Math.max(Kirigami.Units.gridUnit * 8, Math.round(Layout.preferredWidth / root.aspect))

        PlaneMap {
            anchors.fill: parent
            visible: root.plane !== null
        }
        PlasmaComponents3.Label {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: root.plane === null
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: i18n("The map needs the kwin-canvas effect and its pass-through plugin (kwin-canvas fix-plugin).")
            opacity: 0.7
        }
    }
}
