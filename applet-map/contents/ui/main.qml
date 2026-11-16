/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    The canvas's map as a widget: every cluster and every window of the plane
    at a glance, and a hand on it. In a panel it is a row of cluster buttons
    (or a small map) with the full map a click away; on the desktop it is the
    map itself.

    The map keeps the windows and the screens to scale and squeezes the empty
    ground between clusters (layout.js), so a cluster thousands of pixels away
    is as legible as the one on the screen. Each window is a glass sheet with
    its app's icon, or its live picture while the map is open; each cluster a
    tinted card with the number the canvas's digit keys use and its name.
    A click on a window goes to it, a drag moves it on the plane, a middle
    click brings it here, a right click offers the rest; a click on a
    cluster's label goes to the cluster, a drag of the screen's frame moves
    the desk, the wheel zooms the map, and typing searches.

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
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    // Glass on the desktop by default; the desktop's own menu offers the other backgrounds.
    Plasmoid.backgroundHints: PlasmaCore.Types.TranslucentBackground | PlasmaCore.Types.ConfigurableBackground
    // Big enough on the desktop to read; in a panel the compact form stands in.
    switchWidth: Kirigami.Units.gridUnit * 10
    switchHeight: Kirigami.Units.gridUnit * 6
    toolTipMainText: i18n("Canvas Map")
    toolTipSubText: plane ? summary : i18n("Needs the kwin-canvas pass-through plugin")

    // The last reading, parsed: {v, open, game, camera, frames, windows, clusters}, or null.
    property var plane: null
    readonly property var windows: plane ? plane.windows : []
    readonly property var clusters: plane && plane.clusters ? plane.clusters : []
    // The cluster the focused window is in, or 0.
    readonly property int activeCluster: {
        for (let i = 0; i < clusters.length; ++i) if (clusters[i].active) return clusters[i].n;
        return 0;
    }
    readonly property string summary: {
        let shown = 0, minimized = 0;
        for (let i = 0; i < windows.length; ++i) if (windows[i].min) minimized++; else shown++;
        const parts = [i18np("%1 cluster", "%1 clusters", clusters.length), i18np("%1 window", "%1 windows", shown)];
        if (minimized) parts.push(i18n("%1 minimized", minimized));
        return parts.join(" · ");
    }
    readonly property bool inPanel: Plasmoid.formFactor === PlasmaCore.Types.Horizontal || Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // ---- the bus ----
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
    // The signature is the whole argument list as one tuple: the module encodes the
    // arguments against it ("dd" sends none), and without one it introspects first.
    function send(member, args, signature, then) {
        const reply = DBus.SessionBus.asyncCall(message(member, args, signature));
        reply.finished.connect(() => {
            if (then) then(reply.isError ? null : String(reply.value));
            reply.destroy();
        });
    }
    function go(x, y) { send("go", [x, y], "(dd)"); }
    function focusWindow(id) { send("focus", [id], "(s)"); }
    // The effect's other actions (move, bring, minimize, above, close, cluster): what went wrong
    // comes back as text and is shown on the map; a plugin without act is named as the cause.
    function act(verb, args) {
        send("act", [verb, JSON.stringify(args)], "(ss)", function (answer) {
            if (answer === null) root.say(i18n("Update the pass-through plugin for this (kwin-canvas fix-plugin)"));
            else if (answer !== "") root.say(answer);
        });
    }
    // An action with a way back for a plugin or an effect without it: `fallback` runs instead of
    // showing what went wrong.
    function actOr(verb, args, fallback) {
        send("act", [verb, JSON.stringify(args)], "(ss)", function (answer) {
            if (answer === null || answer.indexOf("does not know") >= 0) fallback();
            else if (answer !== "") root.say(answer);
        });
    }
    // A line on the map for a few seconds.
    property string notice: ""
    function say(text) { notice = text; noticeTimer.restart(); }
    Timer { id: noticeTimer; interval: 3500; onTriggered: root.notice = "" }

    // The map watches the windows only while a widget holds it: held from here on, let go when
    // the widget is removed (and by the plugin itself when plasmashell's connection goes). Each
    // widget holds with its own token, so two maps let go one by one.
    readonly property string holdToken: Plasmoid.id + "-" + Math.floor(Math.random() * 1e9)
    function hold() { send("hold", [holdToken], "(s)"); }
    Component.onCompleted: { hold(); read(); }
    // Fired as the widget goes: the reply is not waited for, the widget will not be there.
    Component.onDestruction: DBus.SessionBus.asyncCall(message("release", [holdToken], "(s)"))
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
        onRegisteredChanged: if (registered) { root.hold(); root.read(); }
    }
    Timer {
        interval: 10000
        repeat: true
        running: root.plane === null
        // The plugin came late (its Map object registers after KWin takes its name): hold now too.
        onTriggered: { root.hold(); root.read(); }
    }

    // ---- the icons ----
    // Plasma's task manager knows every window's icon; it is asked in a file of its own, so a
    // system without it loses the icons (the app's own name stands in), not the widget.
    Loader { id: appIcons; source: "AppIcons.qml" }
    readonly property int iconsRev: appIcons.item ? appIcons.item.rev : 0
    function iconFor(id, app) {
        const icon = appIcons.item ? appIcons.item.iconFor(id) : null;
        return icon ? icon : (app ? String(app).toLowerCase() : "application-x-executable");
    }
    function appNameFor(id, app) {
        const name = appIcons.item ? appIcons.item.appNameFor(id) : "";
        return name ? name : String(app || "");
    }
    // A cluster's label: its name on the canvas, else its focus window's app.
    function clusterLabel(c) {
        if (c.name) return c.name;
        for (let i = 0; i < windows.length; ++i) {
            if (windows[i].id === c.focus) {
                const app = appNameFor(windows[i].id, windows[i].app);
                return c.count > 1 ? i18n("%1 +%2", app, c.count - 1) : app;
            }
        }
        return "";
    }
    // Go to cluster n. Closed, that is its last-used window, which the plugin's oldest call
    // reaches (a plugin from before act() still does this); open, the canvas's own cluster flight.
    function goCluster(n) {
        for (let i = 0; i < clusters.length; ++i) {
            if (clusters[i].n !== n) continue;
            if (plane && plane.open) act("cluster", { n: n });
            else focusWindow(clusters[i].focus);
            return;
        }
        say(i18n("There is no cluster %1", n));
    }
    // The cluster after (+1) or before (-1) the focused one, by number, round the end. A step taken
    // in the last second and a half counts from where it went: the reading that lights the new
    // cluster comes after the fly, and quick steps would otherwise all count from the old one.
    property int steppedTo: 0
    property real steppedAt: 0
    function stepCluster(dir) {
        if (!clusters.length) return;
        const from = steppedTo !== 0 && Date.now() - steppedAt < 1500 ? steppedTo : activeCluster;
        let k = 0;
        for (let i = 0; i < clusters.length; ++i) if (clusters[i].n === from) k = i + dir;
        if (from === 0) k = dir > 0 ? 0 : clusters.length - 1;
        k = (k + clusters.length) % clusters.length;
        steppedTo = clusters[k].n;
        steppedAt = Date.now();
        goCluster(clusters[k].n);
    }

    // Live pictures cost a screencast each, so they run only while the map is looked at: the
    // panel's popup while it is open, the desktop's map while the pointer is on it, never while a
    // game has the focus, and only when the setting allows them.
    property bool desktopHovered: false
    readonly property bool previewsOn: Plasmoid.configuration.livePreviews && plane !== null && !plane.game
        && (inPanel ? root.expanded : desktopHovered)

    compactRepresentation: Item {
        id: compact
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property bool asMap: Plasmoid.configuration.panelView === "map" || root.plane === null
        Layout.minimumWidth: vertical ? -1 : (asMap ? Math.round(height * Math.max(1, Math.min(4, mini.aspect))) : pager.implicitWidth)
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: vertical ? (asMap ? Math.round(width / Math.max(1, Math.min(4, mini.aspect))) : pager.implicitHeight) : -1
        Layout.preferredHeight: Layout.minimumHeight

        ClusterPager {
            id: pager
            anchors.fill: parent
            visible: !compact.asMap
            vertical: compact.vertical
            ctl: root
        }
        MapView {
            id: mini
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing / 2
            visible: compact.asMap && root.plane !== null
            interactive: false
            plane: root.plane
            ctl: root
            toScale: Plasmoid.configuration.toScale
            showMinimized: false
        }
        MouseArea {
            anchors.fill: parent
            visible: compact.asMap
            onClicked: root.expanded = !root.expanded
        }
        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
            visible: root.plane === null
            opacity: 0.5
        }
    }

    fullRepresentation: Item {
        id: full
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.minimumHeight: Kirigami.Units.gridUnit * 9
        // A wide plane gets a wider map rather than a thinner strip.
        Layout.preferredWidth: Kirigami.Units.gridUnit * Math.min(52, Math.max(24, 11 * Math.min(5, map.aspect)))
        Layout.preferredHeight: Math.max(Kirigami.Units.gridUnit * 12, Math.round(Layout.preferredWidth / Math.min(5, map.aspect)) + header.implicitHeight)

        // The header earns its room on a map of any size; on a small desktop map it shows while the
        // pointer is on the map or a search is typed.
        readonly property bool roomy: height >= Kirigami.Units.gridUnit * 12
        readonly property bool showHeader: root.inPanel || roomy || hover.hovered || search.text !== ""
        HoverHandler {
            id: hover
            onHoveredChanged: root.desktopHovered = hovered
        }

        Connections {
            target: root
            // The popup opens on a fresh search with the keyboard in it.
            function onExpandedChanged() {
                if (!root.expanded) return;
                search.text = "";
                map.resetView();
                search.forceActiveFocus();
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                id: header
                Layout.fillWidth: true
                visible: full.showHeader
                spacing: Kirigami.Units.smallSpacing
                PlasmaExtras.SearchField {
                    id: search
                    Layout.fillWidth: true
                    placeholderText: i18n("Search windows…")
                    onTextChanged: map.filter = text
                    onAccepted: map.enter()
                    Keys.onPressed: (event) => {
                        const dirs = { [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down" };
                        if (dirs[event.key] && (text === "" || event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                            map.step(dirs[event.key]);
                            event.accepted = true;
                        } else if (text === "" && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                            // The canvas's digit keys: straight to cluster N.
                            root.goCluster(event.key - Qt.Key_0);
                            if (root.inPanel) root.expanded = false;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape && map.dragging) {
                            map.cancelDrag();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape && text !== "") {
                            text = "";
                            event.accepted = true;
                        }
                    }
                }
                PlasmaComponents3.Label {
                    text: root.summary
                    opacity: 0.7
                    elide: Text.ElideRight
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 12
                    visible: full.width > Kirigami.Units.gridUnit * 22
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "zoom-fit-best"
                    visible: map.zoomed
                    onClicked: map.resetView()
                    PlasmaComponents3.ToolTip.text: i18n("Show the whole plane")
                    PlasmaComponents3.ToolTip.visible: hovered
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "measure"
                    checkable: true
                    checked: Plasmoid.configuration.toScale
                    onToggled: Plasmoid.configuration.toScale = checked
                    PlasmaComponents3.ToolTip.text: checked ? i18n("To scale: far clusters are small. Click to bring them close")
                                                            : i18n("Empty ground is squeezed so every cluster reads. Click to draw to scale")
                    PlasmaComponents3.ToolTip.visible: hovered
                }
            }

            MapView {
                id: map
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.plane !== null
                plane: root.plane
                ctl: root
                previews: root.previewsOn
                toScale: Plasmoid.configuration.toScale
                showMinimized: Plasmoid.configuration.showMinimized
                // The popup has done its work: the desk is where the eye goes next.
                onActivated: if (root.inPanel) root.expanded = false
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.plane === null
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                text: i18n("The map needs the kwin-canvas effect and its pass-through plugin (kwin-canvas fix-plugin).")
                opacity: 0.7
            }
        }

        // What an action had to say, over the map's foot.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Kirigami.Units.largeSpacing
            visible: root.notice !== ""
            width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, noticeText.implicitWidth + Kirigami.Units.largeSpacing * 2)
            height: noticeText.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: height / 2
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.92)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
            z: 1000
            PlasmaComponents3.Label {
                id: noticeText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - Kirigami.Units.largeSpacing * 2)
                elide: Text.ElideRight
                text: root.notice
            }
        }
    }
}
