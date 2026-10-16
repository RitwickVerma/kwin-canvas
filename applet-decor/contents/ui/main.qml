/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    The panel twin of the window decoration's pill. It shows the same
    glyphs the pill draws - the same marks, the same circles, the same
    hover and press pops, the same accents - in the same order the native
    titlebar buttons give them, so the panel and the window speak one
    language. Every configured button gets a
    glyph: X the close, I the minimize, A the maximize, S the float, F
    the keep-above, B the keep-below, E the exclude-from-capture, and a
    spacer becomes a gap. The menu and the help codes are left out
    honestly: the in-process window API has no menu or help call, so the
    panel cannot act on them (the decoration's own pill can, through the
    decoration's request methods).
    The glyphs act on the focused window through the pass-through
    plugin's windowAction channel, which works with the canvas closed
    too, including on maximized windows where the pill stays tucked
    away.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    // The panel sizes the applet from the Layout attachments on the root.
    // The width is mirrored out of the representation below (a root
    // property cannot fail the load by naming a lazy representation's
    // id), and it starts at a sane pill width so the very first layout
    // pass already has a real slot - the mirror refines it once the
    // button order arrives.
    clip: true
    Layout.fillHeight: plasmoid.formFactor === PlasmaCore.Types.Horizontal
    Layout.fillWidth: plasmoid.formFactor === PlasmaCore.Types.Vertical
    Layout.minimumWidth: plasmoid.formFactor === PlasmaCore.Types.Horizontal ? appletWidth : -1
    Layout.minimumHeight: -1
    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight
    Layout.maximumWidth: Layout.minimumWidth
    Layout.maximumHeight: Layout.minimumHeight
    property int appletWidth: 200

    // The plugin's state reply carries the focused window as a trailing
    // " win=internalId|caption|max|all|above|below|capture" token - the
    // on-all-desktops (the float), the keep-above, the keep-below and
    // the exclude-from-capture flags last.
    property bool winMax: false
    property bool winFloat: false
    property bool winAbove: false
    property bool winBelow: false
    property bool winCapture: false

    // The native titlebar-buttons configuration, the same source the
    // pill reads - the left set first, then the right - so the applet's
    // glyph order is the pill's glyph order. The menu, the app-menu and
    // the help letters are skipped: the panel's channel cannot act on
    // them (see the header).
    property string buttonsLeft: ""
    property string buttonsRight: ""
    readonly property var glyphs: {
        const s = buttonsLeft + buttonsRight;
        const out = [];
        for (let i = 0; i < s.length; i++) {
            const c = s.charAt(i);
            if (c === "X" || c === "I" || c === "A" || c === "S" || c === "F" || c === "B" || c === "E" || c === "_") out.push(c);
        }
        return out;
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            const out = data.stdout || "";
            if (sourceName.indexOf("Passthrough.state") >= 0) {
                const i = out.indexOf(" win=");
                if (i < 0) {
                    root.winMax = false;
                    root.winFloat = false;
                    root.winAbove = false;
                    root.winBelow = false;
                    root.winCapture = false;
                    return;
                }
                const p = out.slice(i + 5).trim().split("|");
                root.winMax = p.length > 2 && p[2] === "1";
                root.winFloat = p.length > 3 && p[3] === "1";
                root.winAbove = p.length > 4 && p[4] === "1";
                root.winBelow = p.length > 5 && p[5] === "1";
                root.winCapture = p.length > 6 && p[6] === "1";
            } else if (sourceName.indexOf("ButtonsOnLeft") >= 0) {
                root.buttonsLeft = out.trim();
            } else if (sourceName.indexOf("ButtonsOnRight") >= 0) {
                root.buttonsRight = out.trim();
            }
        }
        function run(cmd) {
            connectSource(cmd);
        }
        function action(name) {
            run("qdbus6 org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.windowAction " + name);
        }
    }

    // The focused window + its states, polled once a second; the native
    // button order, polled on a slower beat (it only changes when the
    // titlebar buttons KCM is applied).
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: executable.run("qdbus6 org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state")
    }
    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: {
            executable.run("kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft --default MS");
            executable.run("kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight --default HIAX");
        }
    }
    // The first layout happens before either timer fires: the panel sizes
    // the applet from its implicit width at creation, so the state and
    // the button order must be fetched immediately - otherwise the width
    // computes zero and the applet paints over its neighbours.
    Component.onCompleted: {
        executable.run("qdbus6 org.kde.KWin /KWinCanvas org.kde.kwin.canvas.Passthrough.state");
        executable.run("kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft --default MS");
        executable.run("kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight --default HIAX");
    }

    // The width is a function of the state, not of the row's own layout:
    // a glyph occupies 22 px plus the 6 px spacing (28 per glyph, the
    // trailing spacing dropped) and the 4 px side margins close the sum -
    // so the slot is correct from the first layout, before either poll
    // has landed.
    fullRepresentation: Item {
        id: content
        implicitWidth: 8 + (root.glyphs.length * 28 - (root.glyphs.length > 0 ? 6 : 0))
        implicitHeight: 30
        onImplicitWidthChanged: root.appletWidth = implicitWidth
        Component.onCompleted: root.appletWidth = implicitWidth

        Row {
            id: row
            spacing: 6
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                leftMargin: 4
            }

            Repeater {
                model: root.glyphs
                delegate: glyphDelegate
            }
        }
    }
    compactRepresentation: fullRepresentation

    // One glyph, drawn by its letter: the same circle, the same marks,
    // the same pops, the same accents as the decoration's pill. A
    // spacer renders as an empty gap.
    Component {
        id: glyphDelegate
        Item {
            required property string modelData
            property bool hovered: false
            property bool pressed: false
            readonly property bool lit: (modelData === "S" && root.winFloat) || (modelData === "A" && root.winMax) || (modelData === "F" && root.winAbove) || (modelData === "B" && root.winBelow) || (modelData === "E" && root.winCapture)
            scale: pressed ? 0.86 : (hovered ? 1.2 : 1)
            width: 22
            height: 22
            Behavior on scale {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutBack
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 16
                height: 16
                radius: 8
                visible: parent.modelData !== "_"
                color: parent.pressed ? Qt.rgba(1, 1, 1, 0.42) : (parent.hovered ? Qt.rgba(1, 1, 1, 0.28) : (parent.lit ? Qt.rgba(0.16, 0.43, 0.87, 0.30) : "transparent"))
                Behavior on color {
                    ColorAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }
                border.width: 1
                border.color: parent.hovered || parent.pressed ? Qt.rgba(1, 1, 1, 0.95) : (parent.lit ? "#2a6ddf" : Qt.rgba(1, 1, 1, 0.6))
                Behavior on border.color {
                    ColorAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // The marks: X the crossed strokes, I the bar, A the hollow
            // square (the restore pair when maximized, in the accent),
            // S the up arrow (filled in the accent when floating - the
            // "on all desktops" pin), F the chevron pushing up over its
            // base, B the mirrored push down, E the screen with the
            // capture crossed out.
            Canvas {
                id: mark
                anchors.centerIn: parent
                width: 10
                height: 10
                visible: parent.modelData !== "_"
                onPaint: {
                    const ctx = getContext("2d");
                    const code = parent.modelData;
                    const lit = parent.lit;
                    ctx.strokeStyle = lit ? "#2a6ddf" : "#ffffff";
                    ctx.fillStyle = lit ? "#2a6ddf" : "#ffffff";
                    ctx.lineWidth = (code === "S" || code === "F" || code === "B") ? 1.3 : 1.2;
                    if (code === "X") {
                        ctx.beginPath();
                        ctx.moveTo(1.5, 1.5);
                        ctx.lineTo(8.5, 8.5);
                        ctx.moveTo(8.5, 1.5);
                        ctx.lineTo(1.5, 8.5);
                        ctx.stroke();
                    } else if (code === "I") {
                        ctx.beginPath();
                        ctx.moveTo(1, 5);
                        ctx.lineTo(9, 5);
                        ctx.stroke();
                    } else if (code === "A") {
                        if (lit) {
                            ctx.strokeRect(1.2, 3.2, 5.6, 5.6);
                            ctx.strokeRect(3.2, 1.2, 5.6, 5.6);
                        } else {
                            ctx.strokeRect(1.5, 1.5, 7, 7);
                        }
                    } else if (code === "S") {
                        ctx.beginPath();
                        ctx.moveTo(1.5, 7);
                        ctx.lineTo(5, 2.5);
                        ctx.lineTo(8.5, 7);
                        ctx.closePath();
                        if (lit) ctx.fill();
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(5, 2.5);
                        ctx.lineTo(5, 8);
                        ctx.stroke();
                    } else if (code === "F") {
                        ctx.beginPath();
                        ctx.moveTo(1.5, 8.5);
                        ctx.lineTo(8.5, 8.5);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(2, 6.5);
                        ctx.lineTo(5, 1.5);
                        ctx.lineTo(8, 6.5);
                        if (lit) {
                            ctx.closePath();
                            ctx.fill();
                        }
                        ctx.stroke();
                    } else if (code === "B") {
                        ctx.beginPath();
                        ctx.moveTo(1.5, 1.5);
                        ctx.lineTo(8.5, 1.5);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(2, 3.5);
                        ctx.lineTo(5, 8.5);
                        ctx.lineTo(8, 3.5);
                        if (lit) {
                            ctx.closePath();
                            ctx.fill();
                        }
                        ctx.stroke();
                    } else if (code === "E") {
                        // The screen with the capture crossed out: the
                        // exclusion reads as the diagonal slash over the
                        // window's picture.
                        ctx.strokeRect(1.5, 2, 7, 5.5);
                        ctx.beginPath();
                        ctx.moveTo(1.6, 7.2);
                        ctx.lineTo(8.4, 2.2);
                        ctx.stroke();
                    }
                }
                Connections {
                    target: root
                    function onWinFloatChanged() {
                        mark.requestPaint();
                    }
                    function onWinMaxChanged() {
                        mark.requestPaint();
                    }
                    function onWinAboveChanged() {
                        mark.requestPaint();
                    }
                    function onWinBelowChanged() {
                        mark.requestPaint();
                    }
                    function onWinCaptureChanged() {
                        mark.requestPaint();
                    }
                }
            }

            PlasmaComponents3.ToolTip.text: {
                if (modelData === "X") return i18n("Close the window");
                if (modelData === "I") return i18n("Minimize the window");
                if (modelData === "A") return i18n("Maximize or restore the window");
                if (modelData === "S") return i18n("Float the window: pin it to all desktops");
                if (modelData === "F") return i18n("Keep the window above the others");
                if (modelData === "B") return i18n("Keep the window below the others");
                return i18n("Hide the window from screen capture");
            }
            PlasmaComponents3.ToolTip.visible: hovered && modelData !== "_"
            PlasmaComponents3.ToolTip.delay: Qt.styleHints.mousePressAndHoldInterval

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                enabled: parent.modelData !== "_"
                onEntered: parent.hovered = true
                onExited: parent.hovered = false
                onPressed: parent.pressed = true
                onReleased: parent.pressed = false
                onClicked: {
                    if (parent.modelData === "X") executable.action("close");
                    else if (parent.modelData === "I") executable.action("minimize");
                    else if (parent.modelData === "A") executable.action("maximize");
                    else if (parent.modelData === "S") executable.action("float");
                    else if (parent.modelData === "F") executable.action("keepabove");
                    else if (parent.modelData === "B") executable.action("keepbelow");
                    else if (parent.modelData === "E") executable.action("capture");
                }
            }
        }
    }

    // The single representation is the content itself: the row of the
    // caption and the glyphs, sized by the Layout attachments above.
}
