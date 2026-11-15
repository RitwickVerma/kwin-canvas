/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    One window on the map: a sheet of glass at the window's place, its app's
    icon on it, or the window's live picture while the map is looked at, and
    its caption along the foot when there is room. The focused window wears
    the accent and a glow; one a search passes over fades back. A window
    hidden from capture is never streamed. (Minimized windows are not on the
    plane; MapView's tray holds them.)
*/

import QtQuick
import QtQuick.Effects
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Item {
    id: sheet

    // The window, as MapView's model row gives it.
    required property string wid
    required property string caption
    required property string app
    required property real px
    required property real py
    required property real pw
    required property real ph
    required property int active
    required property int here
    required property int min
    required property int above
    required property int pin
    required property int nocap
    required property int order
    // Its place among the windows by size: the live pictures go to the biggest dozen.
    required property int rank
    // The map drawing it (not "view": the delegate's `view: view` would read its own property).
    required property var map

    // A stream costs: only a dozen, only big enough sheets, only while the map is looked at.
    readonly property bool live: map.previews && rank < 12 && width >= 56 && height >= 32

    readonly property bool hovered: map.hoveredId === wid
    readonly property bool selected: map.selectedId === wid
    readonly property bool matched: map.matchesFilter(caption, app)
    readonly property bool dragged: map.dragId === wid
    readonly property real side: Math.min(width, height)

    x: map.mx(px)
    y: map.my(py)
    // From the place it is going, not from x: while x glides, x is somewhere on the way.
    width: Math.max(3, map.mx(px + pw) - map.mx(px))
    height: Math.max(3, map.my(py + ph) - map.my(py))
    z: 10 + order
    opacity: (matched ? 1 : 0.16) * (min ? 0.45 : 1) * (here ? 1 : 0.6) * (dragged ? 0.35 : 1)
    scale: hovered && map.interactive ? 1.035 : 1
    Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    // A moved window glides to its new place instead of jumping, in step with the screens'
    // frames, the cards and the labels (MapView's glideMs): one glide, so nothing drawn is ever
    // off from the rest mid-way. Skipped while the map itself is zoomed, panned or resized,
    // which has to follow the hand.
    Behavior on x { enabled: map.glide; NumberAnimation { duration: map.glideMs; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: map.glide; NumberAnimation { duration: map.glideMs; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: map.glide; NumberAnimation { duration: map.glideMs; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: map.glide; NumberAnimation { duration: map.glideMs; easing.type: Easing.OutCubic } }

    readonly property color ink: Kirigami.Theme.textColor
    readonly property color glass: Kirigami.Theme.backgroundColor
    readonly property color accent: Kirigami.Theme.highlightColor

    // The glow under the focused window.
    RectangularShadow {
        anchors.fill: body
        visible: sheet.active === 1 && sheet.map.interactive
        radius: body.radius
        blur: Math.min(18, sheet.side * 0.5)
        spread: 1
        color: Qt.rgba(sheet.accent.r, sheet.accent.g, sheet.accent.b, 0.55)
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: Math.min(6, sheet.side / 6)
        color: Qt.rgba(sheet.glass.r, sheet.glass.g, sheet.glass.b, sheet.map.interactive ? 0.66 : 0.8)
        border.width: sheet.active === 1 ? Math.max(1, Math.min(2, sheet.side / 12)) : (sheet.side > 6 ? 1 : 0)
        border.color: sheet.active === 1 ? sheet.accent
                     : (sheet.hovered ? Qt.rgba(sheet.ink.r, sheet.ink.g, sheet.ink.b, 0.85)
                                      : Qt.rgba(sheet.ink.r, sheet.ink.g, sheet.ink.b, 0.3))
        clip: true

        Loader {
            id: picture
            anchors.fill: parent
            anchors.margins: body.border.width
            // Never a window kept from capture, nor a minimized one (it has no picture to give).
            active: sheet.live && !sheet.min && !sheet.nocap
            source: "Preview.qml"
            onLoaded: item.uuid = Qt.binding(function () { return sheet.wid; })
        }
        readonly property bool showsPicture: picture.status === Loader.Ready && picture.item && picture.item.visible

        Kirigami.Icon {
            readonly property real size: Math.max(0, Math.min(48, Math.round(sheet.side * 0.52)))
            anchors.centerIn: parent
            anchors.verticalCenterOffset: captionBar.visible ? -captionBar.height / 2 : 0
            width: size
            height: size
            visible: size >= 9 && !body.showsPicture
            source: { sheet.map.iconsRev; return sheet.map.ctl ? sheet.map.ctl.iconFor(sheet.wid, sheet.app) : "application-x-executable"; }
        }

        Rectangle {
            id: captionBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: captionText.implicitHeight + 2
            visible: sheet.map.interactive && sheet.height >= 40 && sheet.width >= 64
            color: Qt.rgba(sheet.glass.r, sheet.glass.g, sheet.glass.b, 0.78)
            PlasmaComponents3.Label {
                id: captionText
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                verticalAlignment: Text.AlignVCenter
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
                text: sheet.caption
            }
        }
    }

    // The window's states, small in the top right corner.
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 2
        spacing: 1
        visible: sheet.map.interactive && sheet.side >= 24
        Kirigami.Icon { width: 12; height: 12; visible: sheet.min === 1; source: "window-minimize" }
        Kirigami.Icon { width: 12; height: 12; visible: sheet.above === 1; source: "window-keep-above" }
        Kirigami.Icon { width: 12; height: 12; visible: sheet.pin === 1; source: "window-pin" }
    }

    // The keyboard's pick: a ring outside the sheet.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        visible: sheet.selected
        color: "transparent"
        radius: body.radius + 3
        border.width: 1.5
        border.color: sheet.accent
    }
}
