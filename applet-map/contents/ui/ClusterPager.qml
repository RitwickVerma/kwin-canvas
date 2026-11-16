/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    The map in a panel: one button per cluster, a pager for the plane. Each
    carries the cluster's number (the canvas's digit key for it) and the icons
    of the windows it holds, the most recently raised first; the cluster the
    focused window is in is lit. A click goes to the cluster, the wheel steps
    through them, and the map glyph at the end opens the full map.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: pager

    property bool vertical: false
    // main.qml's root: the clusters, the windows, the icons and the actions.
    property var ctl: null

    readonly property real thickness: vertical ? width : height
    readonly property real pill: Math.max(16, thickness - Kirigami.Units.smallSpacing)
    readonly property real iconSize: Math.max(12, Math.round(pill * 0.58))
    implicitWidth: vertical ? thickness : flow.implicitWidth
    implicitHeight: vertical ? flow.implicitHeight : thickness

    // A cluster's windows, the most recently raised first (the plane lists them bottom to top).
    function windowsOf(n) {
        const out = [];
        const ws = ctl ? ctl.windows : [];
        for (let i = ws.length - 1; i >= 0; --i) if (ws[i].c === n) out.push(ws[i]);
        return out;
    }

    // One step a notch: a touchpad or a high-resolution wheel sends many small deltas for one
    // notch's travel, which are summed to a notch (120) before a step.
    property real wheelSum: 0
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            const d = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
            if (d === 0 || !pager.ctl) return;
            if (pager.wheelSum !== 0 && Math.sign(d) !== Math.sign(pager.wheelSum)) pager.wheelSum = 0;
            pager.wheelSum += d;
            while (Math.abs(pager.wheelSum) >= 120) {
                pager.ctl.stepCluster(pager.wheelSum < 0 ? 1 : -1);
                pager.wheelSum -= 120 * Math.sign(pager.wheelSum);
            }
        }
    }

    GridLayout {
        id: flow
        anchors.centerIn: parent
        flow: pager.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: pager.vertical ? -1 : 1
        columns: pager.vertical ? 1 : -1
        rowSpacing: Kirigami.Units.smallSpacing
        columnSpacing: Kirigami.Units.smallSpacing

        // By count, each delegate reading its own cluster: every reading is a new array, and an
        // array model would remake every button (and drop its hover) on each one.
        Repeater {
            model: pager.ctl ? pager.ctl.clusters.length : 0
            delegate: Rectangle {
                id: pill
                required property int index
                readonly property var modelData: (pager.ctl && pager.ctl.clusters[index]) || ({ n: 0, active: 0, count: 0, name: "", focus: "" })
                readonly property bool lit: modelData.active === 1
                readonly property var members: { pager.ctl.iconsRev; return pager.windowsOf(modelData.n); }
                readonly property int shownIcons: Math.min(3, members.length)
                Layout.preferredHeight: pager.pill
                Layout.preferredWidth: pager.vertical ? pager.pill
                    : Math.round(number.implicitWidth + Kirigami.Units.smallSpacing * 3 + shownIcons * (pager.iconSize + 2))
                radius: Math.min(height, width) / 2.6
                color: lit ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.32)
                           : (tap.hovered ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.14)
                                          : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06))
                border.width: 1
                border.color: lit ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                Row {
                    anchors.centerIn: parent
                    spacing: 2
                    PlasmaComponents3.Label {
                        id: number
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(pill.modelData.n)
                        font.bold: pill.lit
                        rightPadding: pager.vertical ? 0 : Kirigami.Units.smallSpacing
                    }
                    Repeater {
                        model: pager.vertical ? 0 : pill.shownIcons
                        delegate: Kirigami.Icon {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: pager.iconSize
                            height: pager.iconSize
                            source: pager.ctl.iconFor(pill.members[index].id, pill.members[index].app)
                        }
                    }
                }

                HoverHandler { id: tap }
                TapHandler {
                    onTapped: pager.ctl.goCluster(pill.modelData.n)
                }
                PlasmaComponents3.ToolTip.text: {
                    const head = pager.ctl.clusterLabel(pill.modelData) || i18n("Cluster %1", pill.modelData.n);
                    const lines = pill.members.slice(0, 8).map(function (w) { return "• " + w.caption; });
                    if (pill.members.length > 8) lines.push(i18n("and %1 more", pill.members.length - 8));
                    return "#" + pill.modelData.n + "  " + head + "\n" + lines.join("\n");
                }
                PlasmaComponents3.ToolTip.visible: tap.hovered
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }

        // The full map.
        PlasmaComponents3.ToolButton {
            Layout.preferredHeight: pager.pill
            Layout.preferredWidth: pager.pill
            icon.name: "map-flat"
            // Shown down while the map is open; not checkable, so the click cannot unbind it.
            checked: pager.ctl ? pager.ctl.expanded : false
            onClicked: pager.ctl.expanded = !pager.ctl.expanded
            PlasmaComponents3.ToolTip.text: pager.ctl ? pager.ctl.summary : ""
            PlasmaComponents3.ToolTip.visible: hovered
        }
    }
}
