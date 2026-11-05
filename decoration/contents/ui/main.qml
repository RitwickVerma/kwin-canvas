/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
/*
    The canvas's window frame is the window and one bar. No border on the
    sides or at the bottom (the resize band lies outside the window), and
    on top a 32 px title bar in the colour scheme's own title bar colours,
    active and inactive, with the canvas's glyphs and the caption. The bar
    is drawn edge to edge, so an effect that shapes the frame (Rounded
    Corners, an outline) rounds and rings the window the eye sees: with the
    old transparent band the effect's top corners fell on nothing, and the
    window under it kept square top corners. The whole bar drags the
    window. This is the decoration, so it is the window's frame in the
    normal desktop too, not only on the plane.

    The bar wears the native configuration: System Settings' titlebar
    buttons decide which glyphs it shows, on which side and in what order,
    and moving them reshapes the bar without a re-login. Every button the
    QML bridge reports gets a glyph: X the close, I the minimize, A the
    maximize, S the float (the on-all-desktops pin), M the menu, F the
    keep-above, B the keep-below, H the help, and a configured spacer
    becomes a gap. One button cannot be drawn here: the
    exclude-from-capture glyph, because this KWin's QML bridge predates
    the button and drops it from the list entirely.
*/
import QtQuick
import org.kde.kwin.decoration

Decoration {
    id: root
    alpha: true

    readonly property bool activeWindow: decoration.client.active
    // The states the glyphs show: a floated window's pin and a maximized
    // window's restore pair wear the accent; so do the keep-above and
    // keep-below marks when on. Float is on all desktops (the same test the
    // canvas uses); keep above and keep below are their own marks.
    readonly property bool floating: decoration.client.onAllDesktops
    readonly property bool maximized: decoration.client.maximized
    readonly property bool above: decoration.client.keepAbove
    readonly property bool below: decoration.client.keepBelow
    // The colour scheme's title bar and its text, each for the window's
    // active or inactive state (the options follow the client's focus).
    readonly property color ink: options.fontColor
    readonly property int band: 32

    // The native titlebar-buttons configuration: which glyphs the bar shows,
    // on which side, in the user's own order, so the bar is the system's
    // buttons drawn in the canvas's glyphs. Every code the QML bridge
    // reports maps to a glyph; a spacer maps to an empty gap. The
    // exclude-from-capture button never arrives (the bridge's enum
    // predates it) and the application-menu and shade codes have no room
    // here, so those are left out by the bridge's own shape.
    DecorationOptions {
        id: options
        deco: decoration
    }
    function glyphCodes(set) {
        const out = [];
        for (let i = 0; i < set.length; i++) {
            const t = set[i];
            if (t === DecorationOptions.DecorationButtonClose) out.push("X");
            else if (t === DecorationOptions.DecorationButtonMinimize) out.push("I");
            else if (t === DecorationOptions.DecorationButtonMaximizeRestore) out.push("A");
            else if (t === DecorationOptions.DecorationButtonOnAllDesktops) out.push("S");
            else if (t === DecorationOptions.DecorationButtonMenu) out.push("M");
            else if (t === DecorationOptions.DecorationButtonKeepAbove) out.push("F");
            else if (t === DecorationOptions.DecorationButtonKeepBelow) out.push("B");
            else if (t === DecorationOptions.DecorationButtonQuickHelp) out.push("H");
            else if (t === DecorationOptions.DecorationButtonExplicitSpacer) out.push("_");
        }
        return out;
    }
    readonly property var leftButtons: glyphCodes(options.titleButtonsLeft)
    readonly property var rightButtons: glyphCodes(options.titleButtonsRight)
    // The ink as a canvas style, at an alpha.
    function css(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")";
    }

    // The title item: the whole bar drags the window (and takes the title
    // bar's clicks, double-click and wheel as configured).
    Item {
        id: dragBand
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: root.band
    }

    // The bar. A maximized window is full-bleed and has none (its title is
    // 0 below); the band above it would only sit under the client.
    Rectangle {
        id: bar
        anchors.fill: dragBand
        visible: !root.maximized
        color: options.titleBarColor
        Behavior on color {
            ColorAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }
        }

        Row {
            id: leftRow
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
                model: root.leftButtons
                delegate: glyphDelegate
            }
        }
        Row {
            id: rightRow
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
                model: root.rightButtons
                delegate: glyphDelegate
            }
        }
        // The caption, centred on the bar and kept clear of both button
        // rows, so it sits in the middle whichever side the buttons are on.
        Text {
            anchors.centerIn: parent
            width: Math.max(0, Math.min(implicitWidth, parent.width - 2 * Math.max(leftRow.width, rightRow.width) - 2 * 20))
            text: decoration.client.caption
            textFormat: Text.PlainText
            font: options.titleFont
            color: root.ink
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignHCenter
            Behavior on color {
                ColorAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // One glyph, drawn by its code: the circle carries the hover and
    // press fills, and the state marks wear the accent when their state
    // is on. A spacer renders as an empty gap - no circle, no mark.
    Component {
        id: glyphDelegate
        Item {
            required property string modelData
            property bool hovered: false
            property bool pressed: false
            readonly property bool lit: (modelData === "S" && root.floating) || (modelData === "A" && root.maximized) || (modelData === "F" && root.above) || (modelData === "B" && root.below)
            readonly property color ink: root.ink
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
                color: parent.pressed ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.36) : (parent.hovered ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.22) : (parent.lit ? Qt.rgba(0.16, 0.43, 0.87, 0.30) : "transparent"))
                Behavior on color {
                    ColorAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }
                border.width: 1
                border.color: parent.hovered || parent.pressed ? root.ink : (parent.lit ? "#2a6ddf" : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7))
                Behavior on border.color {
                    ColorAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // The marks: X the crossed strokes, I the bar, A the hollow
            // square (the restore pair when maximized, in the accent),
            // S the pushpin (filled in the accent when floating - the
            // "on all desktops" pin), M three dots, F the chevron
            // pushing up over its base, B the mirrored push down, H the
            // question mark.
            Canvas {
                id: mark
                anchors.centerIn: parent
                width: 10
                height: 10
                visible: parent.modelData !== "_"
                onPaint: {
                    const ctx = getContext("2d");
                    // Each paint starts from a clear canvas: a filled glyph (the lit pin, the
                    // keep-above) left its fill behind when it went out.
                    ctx.clearRect(0, 0, width, height);
                    const code = parent.modelData;
                    const lit = parent.lit;
                    ctx.strokeStyle = lit ? "#2a6ddf" : root.css(root.ink, 1);
                    ctx.fillStyle = lit ? "#2a6ddf" : root.css(root.ink, 1);
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
                        // The pushpin: a round head over a needle, so the
                        // float never reads as the keep-above chevron.
                        ctx.beginPath();
                        ctx.arc(5, 3.4, 2.1, 0, Math.PI * 2);
                        if (lit) ctx.fill();
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(5, 5.6);
                        ctx.lineTo(5, 9);
                        ctx.stroke();
                    } else if (code === "F") {
                        // The push to the top: the base bar with the
                        // chevron above it.
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
                        // The push to the bottom: the mirrored chevron
                        // under its base bar.
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
                    } else if (code === "M") {
                        ctx.beginPath();
                        ctx.arc(5, 2, 0.9, 0, Math.PI * 2);
                        ctx.arc(5, 5, 0.9, 0, Math.PI * 2);
                        ctx.arc(5, 8, 0.9, 0, Math.PI * 2);
                        ctx.fill();
                    } else if (code === "H") {
                        ctx.beginPath();
                        ctx.moveTo(3.3, 2.2);
                        ctx.quadraticCurveTo(5, 0.7, 6.7, 2.2);
                        ctx.quadraticCurveTo(7.4, 3.4, 5, 4.8);
                        ctx.lineTo(5, 6.4);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.arc(5, 8.1, 0.8, 0, Math.PI * 2);
                        ctx.fill();
                    }
                }
                // Repaint on the delegate's own lit and ink, which is what onPaint reads:
                // a Connections on root could run before lit re-evaluated, and paint the
                // old state until something else forced another paint. The ink changes
                // with the focus and the colour scheme.
                Connections {
                    target: mark.parent
                    function onLitChanged() { mark.requestPaint(); }
                    function onInkChanged() { mark.requestPaint(); }
                }
            }

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
                    if (parent.modelData === "X") decoration.requestClose();
                    else if (parent.modelData === "I") decoration.requestMinimize();
                    else if (parent.modelData === "A") decoration.requestToggleMaximization(Qt.LeftButton);
                    else if (parent.modelData === "S") decoration.requestToggleOnAllDesktops();
                    else if (parent.modelData === "M") decoration.requestShowWindowMenu();
                    else if (parent.modelData === "F") decoration.requestToggleKeepAbove();
                    else if (parent.modelData === "B") decoration.requestToggleKeepBelow();
                    else if (parent.modelData === "H") decoration.requestContextHelp();
                }
            }
        }
    }

    Component.onCompleted: {
        // No border on the sides or at the bottom: the window's frame is the
        // window, so an effect that shapes the frame (Rounded Corners, an
        // outline) shapes what the eye sees. The resize band is the
        // extended border below - Aurorae makes it a resize-only border,
        // input outside the frame and never drawn (it was a transparent
        // 6 px border inside the frame, and the rounded corners fell on
        // it, invisible). KWin has no resize-only border above a window, so
        // the title stays inside the frame: it is the bar, drawn edge to
        // edge, and the effect's top corners fall on it.
        borders.setBorders(0);
        borders.setTitle(root.band);
        // A maximized window is full-bleed: no bar, so the client runs to
        // the screen's top edge.
        maximizedBorders.setTitle(0);
        // The resize band, outside the frame: Aurorae passes the extended
        // borders to KWin as resize-only borders (left, right and bottom;
        // there is never a top one), so they take the pointer and draw
        // nothing.
        extendedBorders.setAllBorders(6);
        decoration.installTitleItem(dragBand);
    }
}
