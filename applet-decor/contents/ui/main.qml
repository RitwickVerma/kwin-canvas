/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    The panel twin of the window decoration's pill. It shows the focused
    window's caption and the same glyphs the pill draws - the same marks,
    the same circles, the same hover and press pops, the same accent for
    the float (the on-all-desktops pin) and the maximize - in the same
    order the native titlebar buttons give them, so the panel and the
    window speak one language.
    The glyphs act on the focused window through the pass-through
    plugin's windowAction channel, which works with the canvas closed
    too, including on maximized windows where the pill stays tucked
    away.
*/

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    // The plugin's state reply carries the focused window as a trailing
    // " win=internalId|caption|max|keep|all" token - the keep-above and
    // the on-all-desktops (the float) flags last.
    property string winCaption: ""
    property bool winMax: false
    property bool winAbove: false
    property bool winFloat: false

    // The native titlebar-buttons configuration, the same source the
    // pill reads - the left set first, then the right - so the applet's
    // glyph order is the pill's glyph order.
    property string buttonsLeft: ""
    property string buttonsRight: ""
    readonly property var glyphs: {
        const s = buttonsLeft + buttonsRight;
        const out = [];
        for (let i = 0; i < s.length; i++) {
            const c = s.charAt(i);
            if (c === "X" || c === "I" || c === "A" || c === "S" || c === "F") out.push(c);
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
                    root.winCaption = "";
                    root.winMax = false;
                    root.winFloat = false;
                    return;
                }
                const p = out.slice(i + 5).trim().split("|");
                root.winCaption = p.length > 1 ? p[1] : "";
                root.winMax = p.length > 2 && p[2] === "1";
                root.winAbove = p.length > 3 && p[3] === "1";
                root.winFloat = p.length > 4 && p[4] === "1";
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
            executable.run("kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft");
            executable.run("kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight");
        }
    }

    compactRepresentation: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: 30

        Row {
            id: row
            spacing: 6
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                leftMargin: 4
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.winCaption !== ""
                text: root.winCaption
                elide: Text.ElideRight
                width: Math.min(220, implicitWidth)
                color: PlasmaCore.Theme.textColor
                opacity: 0.75
                font.pixelSize: 11
                renderType: Text.NativeRendering
            }

            Repeater {
                model: root.glyphs
                delegate: glyphDelegate
            }
        }
    }

    // One glyph, drawn by its letter: the same circle, the same marks,
    // the same pops, the same accents as the decoration's pill.
    Component {
        id: glyphDelegate
        Item {
            required property string modelData
            property bool hovered: false
            property bool pressed: false
            readonly property bool lit: (modelData === "S" && root.winFloat) || (modelData === "F" && root.winAbove) || (modelData === "A" && root.winMax)
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
            // "on all desktops" pin), F the pin head (the keep-above).
            Canvas {
                id: mark
                anchors.centerIn: parent
                width: 10
                height: 10
                onPaint: {
                    const ctx = getContext("2d");
                    const code = parent.modelData;
                    const lit = parent.lit;
                    ctx.strokeStyle = lit ? "#2a6ddf" : "#ffffff";
                    ctx.fillStyle = lit ? "#2a6ddf" : "transparent";
                    ctx.lineWidth = code === "S" ? 1.3 : 1.2;
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
                        ctx.arc(5, 3.2, 1.9, 0, Math.PI * 2);
                        if (lit) ctx.fill();
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(5, 5.1);
                        ctx.lineTo(5, 8.5);
                        ctx.stroke();
                    }
                }
                Connections {
                    target: root
                    function onWinFloatChanged() {
                        mark.requestPaint();
                    }
                    function onWinAboveChanged() {
                        mark.requestPaint();
                    }
                    function onWinMaxChanged() {
                        mark.requestPaint();
                    }
                }
            }

            PlasmaComponents3.ToolTip.text: {
                if (parent.modelData === "X") return i18n("Close the window");
                if (parent.modelData === "I") return i18n("Minimize the window");
                if (parent.modelData === "A") return i18n("Maximize or restore the window");
                if (parent.modelData === "S") return i18n("Float the window: pin it to all desktops");
                return i18n("Keep the window above the others");
            }
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Qt.styleHints.mousePressAndHoldInterval

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
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
                }
            }
        }
    }

    fullRepresentation: compactRepresentation
}
