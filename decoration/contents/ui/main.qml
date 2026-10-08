/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
/*
    The canvas's window frame. No title bar: a hairline border, and a
    small glass pill - close, minimize, maximize - fading in at the top
    left (Klassy's own side) when the pointer rests on the top edge. The
    pill wears the canvas's glass with a refraction gradient: a light
    streak across the capsule, the look of the thing bent behind it. The
    whole top edge drags the window. This is the decoration, so it is the
    window's frame in the normal desktop too, not only on the plane; the
    canvas keeps its own semantics untouched.

    The QML decoration cannot blur the desktop behind it (the engine
    exposes no blur region - Klassy can, as a C++ decoration); the glass
    and the refraction here are drawn, and read the same. The corners
    are the same story: the compositor draws the client square, so the
    QML frame cannot round it - the shadow rounds, the window does not.
*/
import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kwin.decoration

Decoration {
    id: root
    alpha: true

    readonly property bool activeWindow: decoration.client.active
    readonly property color line: activeWindow ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
    readonly property color glyph: activeWindow ? Qt.rgba(1, 1, 1, 0.88) : Qt.rgba(1, 1, 1, 0.45)
    readonly property color glass: Qt.rgba(0.05, 0.05, 0.08, 0.62)
    readonly property bool pillShown: stripHover.hovered || closeButton.hovered || minButton.hovered || maxButton.hovered || closeButton.pressed || minButton.pressed || maxButton.pressed

    // The shadow: the window's own, drawn into the extended borders.
    // The frame reads as a sheet floating above the desktop instead of
    // a flat rectangle on it.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -28
        radius: 10
        color: root.activeWindow ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.35)
        layer.enabled: true
        layer.effect: GaussianBlur {
            radius: 20
            samples: 32
            transparentBorder: true
        }
    }

    // The frame: a hairline, the window's own content untouched inside.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: root.line
    }

    // The bevel: a faint lift along the top edge - the light that makes
    // the sheet read as a sheet.
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 1
        color: root.activeWindow ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
    }

    // The drag band: the whole top edge drags the window. Invisible by
    // design; the pill floats on it.
    Item {
        id: dragBand
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 24
    }

    // The pill: one small glass capsule with the three glyphs inside.
    Item {
        id: pill
        anchors {
            bottom: dragBand.bottom
            bottomMargin: 1
            horizontalCenter: parent.horizontalCenter
        }
        width: 66
        height: 22
        opacity: root.pillShown ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        // The capsule's glass, with the refraction: a light streak
        // bending down from the top-left corner, and a faint lift along
        // the bottom edge - the glass reads as a lens, not a patch.
        Rectangle {
            id: capsule
            anchors.fill: parent
            radius: 11
            color: root.glass
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.24)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.02) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.06) }
            }
        }
        // The specular streak across the top of the capsule.
        Rectangle {
            anchors {
                top: capsule.top
                left: capsule.left
                margins: 2
            }
            width: capsule.width * 0.45
            height: 2
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.16)
        }

        Row {
            anchors.centerIn: parent
            spacing: 6

            Item {
                id: closeButton
                width: 18
                height: 18
                property bool hovered: false
                property bool pressed: false

                Rectangle {
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    radius: 6
                    color: closeButton.hovered || closeButton.pressed ? Qt.rgba(1, 1, 1, 0.18) : "transparent"
                    border.width: 1
                    border.color: root.glyph
                }
                // The close mark: two crossed strokes.
                Canvas {
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.strokeStyle = "#ffffff";
                        ctx.lineWidth = 1.2;
                        ctx.beginPath();
                        ctx.moveTo(1, 1);
                        ctx.lineTo(7, 7);
                        ctx.moveTo(7, 1);
                        ctx.lineTo(1, 7);
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
                width: 18
                height: 18
                property bool hovered: false
                property bool pressed: false

                Rectangle {
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    radius: 6
                    color: minButton.hovered || minButton.pressed ? Qt.rgba(1, 1, 1, 0.18) : "transparent"
                    border.width: 1
                    border.color: root.glyph
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 8
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
                width: 18
                height: 18
                property bool hovered: false
                property bool pressed: false

                Rectangle {
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    radius: 6
                    color: maxButton.hovered || maxButton.pressed ? Qt.rgba(1, 1, 1, 0.18) : "transparent"
                    border.width: 1
                    border.color: root.glyph
                }
                // The maximize mark: a hollow square.
                Rectangle {
                    anchors.centerIn: parent
                    width: 7
                    height: 7
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
        }
    }

    HoverHandler {
        id: stripHover
        target: dragBand
    }

    Component.onCompleted: {
        // The resize borders: a generous invisible band, the hairline is
        // the visible edge. The title is an invisible 24 px band - the
        // hover surface for the drag and the pill. With the title at 0
        // the client covers the whole interior and the pill could never
        // be hovered; the band is transparent (alpha: true), so the look
        // stays borderless while the pill floats exactly on the edge.
        borders.setBorders(6);
        borders.setTitle(24);
        maximizedBorders.setTitle(24);
        extendedBorders.setAllBorders(28);
        decoration.installTitleItem(dragBand);
    }
}
