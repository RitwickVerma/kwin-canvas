/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
/*
    The canvas's window frame is no frame at all. The window wears
    nothing - no border, no shadow - just a glass pill that pops up at
    the top edge's centre, half in and half out of the window, when the
    pointer comes near. The whole top edge drags the window. This is
    the decoration, so it is the window's frame in the normal desktop
    too, not only on the plane; the canvas keeps its own semantics
    untouched.

    The QML decoration cannot blur the desktop behind it (the engine
    exposes no blur region - Klassy can, as a C++ decoration); the
    pill's glass and the refraction here are drawn, and read the same.
*/
import QtQuick
import org.kde.kwin.decoration

Decoration {
    id: root
    alpha: true

    readonly property bool activeWindow: decoration.client.active
    readonly property color glyph: activeWindow ? Qt.rgba(1, 1, 1, 0.88) : Qt.rgba(1, 1, 1, 0.45)
    readonly property color glass: Qt.rgba(0.05, 0.05, 0.08, 0.62)
    readonly property bool pillShown: stripHover.hovered || closeButton.hovered || minButton.hovered || maxButton.hovered || floatButton.hovered || closeButton.pressed || minButton.pressed || maxButton.pressed || floatButton.pressed

    // The drag band: the whole top edge drags the window. Invisible by
    // design; the pill floats on it.
    Item {
        id: dragBand
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 32
    }

    // The pill: one glass capsule with the four glyphs inside. It pops
    // Only the focused window wears its pill. The unfocused pill waits
    // behind the window's top edge, invisible under the client; the
    // moment the window takes the focus, the pill slides out from
    // behind the edge and settles on top of it, a springy rise with a
    // hint of overshoot. When the focus leaves, it slides back behind.
    // Each glyph swells when the pointer comes near it, and sinks a
    // touch when pressed.
    Item {
        id: pill
        x: root.width / 2 - pill.width / 2
        // The pill rests with its bottom on the drag band's floor (the
        // client's top edge); one pill height lower it is entirely
        // behind the client and invisible. The activeWindow switch is
        // the whole show: the slide out and the slide back are the same
        // spring.
        y: dragBand.bottom - pill.height + (root.activeWindow ? 0 : pill.height)
        Behavior on y {
            SpringAnimation { spring: 2.6; damping: 0.8; epsilon: 0.01 }
        }
        width: 136
        height: 30

        // The capsule's glass, with the refraction: the gradient's own
        // top light reads as the lens; no extra streak, so nothing
        // reads as a stray line.
        Rectangle {
            id: capsule
            anchors.fill: parent
            radius: 15
            color: root.glass
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.24)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.02) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.06) }
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 8

            Item {
                id: closeButton
                width: 22
                height: 22
                property bool hovered: false
                property bool pressed: false
                scale: closeButton.pressed ? 0.86 : (closeButton.hovered ? 1.2 : 1)
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
                    color: closeButton.pressed ? Qt.rgba(1, 1, 1, 0.42) : (closeButton.hovered ? Qt.rgba(1, 1, 1, 0.28) : "transparent")
                    Behavior on color {
                        ColorAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }
                    border.width: 1
                    border.color: closeButton.hovered || closeButton.pressed ? Qt.rgba(1, 1, 1, 0.95) : root.glyph
                }
                // The close mark: two crossed strokes.
                Canvas {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.strokeStyle = "#ffffff";
                        ctx.lineWidth = 1.2;
                        ctx.beginPath();
                        ctx.moveTo(1, 1);
                        ctx.lineTo(8, 8);
                        ctx.moveTo(8, 1);
                        ctx.lineTo(1, 8);
                        ctx.stroke();
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    onEntered: closeButton.hovered = true
                    onExited: closeButton.hovered = false
                    onPressed: closeButton.pressed = true
                    onReleased: closeButton.pressed = false
                    onClicked: {
                            decoration.requestClose();
                    }
                }
            }

            Item {
                id: minButton
                width: 22
                height: 22
                property bool hovered: false
                property bool pressed: false
                scale: minButton.pressed ? 0.86 : (minButton.hovered ? 1.2 : 1)
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
                    color: minButton.pressed ? Qt.rgba(1, 1, 1, 0.42) : (minButton.hovered ? Qt.rgba(1, 1, 1, 0.28) : "transparent")
                    Behavior on color {
                        ColorAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }
                    border.width: 1
                    border.color: minButton.hovered || minButton.pressed ? Qt.rgba(1, 1, 1, 0.95) : root.glyph
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 9
                    height: 1.2
                    color: "#ffffff"
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    onEntered: minButton.hovered = true
                    onExited: minButton.hovered = false
                    onPressed: minButton.pressed = true
                    onReleased: minButton.pressed = false
                    onClicked: {
                            decoration.requestMinimize();
                    }
                }
            }

            Item {
                id: maxButton
                width: 22
                height: 22
                property bool hovered: false
                property bool pressed: false
                scale: maxButton.pressed ? 0.86 : (maxButton.hovered ? 1.2 : 1)
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
                    color: maxButton.pressed ? Qt.rgba(1, 1, 1, 0.42) : (maxButton.hovered ? Qt.rgba(1, 1, 1, 0.28) : "transparent")
                    Behavior on color {
                        ColorAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }
                    border.width: 1
                    border.color: maxButton.hovered || maxButton.pressed ? Qt.rgba(1, 1, 1, 0.95) : root.glyph
                }
                // The maximize mark: a hollow square.
                Rectangle {
                    anchors.centerIn: parent
                    width: 9
                    height: 9
                    color: "transparent"
                    border.width: 1.2
                    border.color: "#ffffff"
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    onEntered: maxButton.hovered = true
                    onExited: maxButton.hovered = false
                    onPressed: maxButton.pressed = true
                    onReleased: maxButton.pressed = false
                    onClicked: {
                            decoration.requestToggleMaximization(Qt.LeftButton);
                    }
                }
            }

            Item {
                id: floatButton
                width: 22
                height: 22
                property bool hovered: false
                property bool pressed: false
                scale: floatButton.pressed ? 0.86 : (floatButton.hovered ? 1.2 : 1)
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
                    color: floatButton.pressed ? Qt.rgba(1, 1, 1, 0.42) : (floatButton.hovered ? Qt.rgba(1, 1, 1, 0.28) : "transparent")
                    Behavior on color {
                        ColorAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }
                    border.width: 1
                    border.color: floatButton.hovered || floatButton.pressed ? Qt.rgba(1, 1, 1, 0.95) : root.glyph
                }
                // The float mark: an up arrow - keep above others.
                Canvas {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.strokeStyle = "#ffffff";
                        ctx.lineWidth = 1.3;
                        ctx.beginPath();
                        ctx.moveTo(1.5, 7);
                        ctx.lineTo(5, 2.5);
                        ctx.lineTo(8.5, 7);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(5, 2.5);
                        ctx.lineTo(5, 8);
                        ctx.stroke();
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    onEntered: floatButton.hovered = true
                    onExited: floatButton.hovered = false
                    onPressed: floatButton.pressed = true
                    onReleased: floatButton.pressed = false
                    onClicked: {
                            decoration.requestToggleKeepAbove();
                    }
                }
            }
        }
    }

    HoverHandler {
        id: stripHover
        target: dragBand
    }

    Component.onCompleted: {
        // The resize borders: a generous invisible band - the only
        // decoration the window carries besides the pill, and it is
        // invisible by design. The title is an invisible 24 px band -
        // the hover surface for the drag and the pill. With the title
        // at 0 the client covers the whole interior and the pill could
        // never be hovered; the band is transparent (alpha: true), so
        // the window wears nothing while the pill floats exactly on the
        // edge.
        borders.setBorders(6);
        borders.setTitle(32);
        maximizedBorders.setTitle(32);
        // No shadow: the extended borders only exist to give the
        // aurorae engine a region for its own dark shadow, and that
        // shadow read as a black line above the window. The pill fits
        // entirely inside the title band, so it needs no headroom.
        extendedBorders.setAllBorders(0);
        decoration.installTitleItem(dragBand);
    }
}
