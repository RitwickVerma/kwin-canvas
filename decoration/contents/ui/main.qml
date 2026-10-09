/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
/*
    The canvas's window frame is no frame at all. The window wears
    nothing - no border, no shadow - just a glass pill at the top edge's
    left end, half in and half out of the window, that slides out of the
    edge when the window takes the focus and back behind it when the
    focus leaves. The whole top edge drags the window. This is
    the decoration, so it is the window's frame in the normal desktop
    too, not only on the plane; the canvas keeps its own semantics
    untouched.

    The pill wears the native configuration: System Settings' titlebar
    buttons decide which glyphs it shows and in what order (the left
    set first, then the right), and moving them between the sides
    reshapes the pill without a re-login. Every button the QML bridge
    reports gets a glyph: X the close, I the minimize, A the maximize,
    S the float (the on-all-desktops pin), M the menu, F the
    keep-above, B the keep-below, H the help, and a configured spacer
    becomes a gap. One button cannot be drawn here: the
    exclude-from-capture glyph, because this KWin's QML bridge predates
    the button and drops it from the list entirely.

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
    // The states the pill shows: a floated window wears the accent ring
    // and the filled arrow; a maximized one shows the restore glyph;
    // the keep-above and keep-below marks light their own accent.
    readonly property bool floating: decoration.client.onAllDesktops
    readonly property bool maximized: decoration.client.maximized
    readonly property bool above: decoration.client.keepAbove
    readonly property bool below: decoration.client.keepBelow
    readonly property color glyph: activeWindow ? Qt.rgba(1, 1, 1, 0.88) : Qt.rgba(1, 1, 1, 0.45)
    readonly property color glass: Qt.rgba(0.05, 0.05, 0.08, 0.62)

    // The native titlebar-buttons configuration: which glyphs the pill
    // shows, in the user's own order - the left set first, then the
    // right - so the pill is the system's buttons, just drawn in the
    // canvas's glass. Every code the QML bridge reports maps to a
    // glyph; a spacer maps to an empty gap. The exclude-from-capture
    // button never arrives (the bridge's enum predates it) and the
    // application-menu and shade codes have no room here, so those are
    // left out by the bridge's own shape.
    DecorationOptions {
        id: options
        deco: decoration
    }
    readonly property var pillButtons: {
        const sets = options.titleButtonsLeft.concat(options.titleButtonsRight);
        const out = [];
        for (let i = 0; i < sets.length; i++) {
            const t = sets[i];
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

    // The pill: one glass capsule with the configured glyphs inside. It
    // sits at the top edge's left end. Only the focused window wears
    // its pill. The unfocused pill waits behind the window's top edge,
    // invisible under the client; the moment the window takes the
    // focus, the pill slides out from behind the edge and settles on
    // top of it, a springy rise with a hint of overshoot. When the
    // focus leaves, it slides back behind. Each glyph swells when the
    // pointer comes near it, and sinks a touch when pressed.
    Item {
        id: pill
        anchors.left: parent.left
        anchors.leftMargin: 8
        // The pill rests with its bottom on the drag band's floor (the
        // client's top edge); one pill height lower it is entirely
        // behind the client and invisible. The activeWindow switch is
        // the whole show: the slide out and the slide back are the same
        // spring. A maximized window keeps the pill tucked away too -
        // the full-bleed surface is its own chrome, and the band above
        // it still drags (KWin un-maximizes on the drag).
        y: dragBand.y + dragBand.height - pill.height + ((root.activeWindow && !root.maximized) ? 0 : pill.height)
        Behavior on y {
            SpringAnimation { spring: 2.6; damping: 0.8; epsilon: 0.01 }
        }
        // The capsule hugs its glyphs: the four-glyph pill is the
        // familiar 136, fewer buttons make a shorter pill, and a
        // configuration with none of the four hides it entirely.
        width: 24 + root.pillButtons.length * 30 - (root.pillButtons.length > 0 ? 8 : 0)
        height: 30
        visible: root.pillButtons.length > 0

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
            // The glass is the capsule, flat: the QML gradient would REPLACE
            // the color (the refraction wash made the pill nearly invisible
            // against the wallpaper - measured in the nest).
        }

        Row {
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: root.pillButtons
                delegate: glyphDelegate
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
                border.color: parent.hovered || parent.pressed ? Qt.rgba(1, 1, 1, 0.95) : (parent.lit ? "#2a6ddf" : root.glyph)
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
                    } else if (code === "M") {
                        ctx.beginPath();
                        ctx.arc(5, 2, 0.9, 0, Math.PI * 2);
                        ctx.arc(5, 5, 0.9, 0, Math.PI * 2);
                        ctx.arc(5, 8, 0.9, 0, Math.PI * 2);
                        ctx.fill();
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
                Connections {
                    target: root
                    function onFloatingChanged() {
                        mark.requestPaint();
                    }
                    function onMaximizedChanged() {
                        mark.requestPaint();
                    }
                    function onAboveChanged() {
                        mark.requestPaint();
                    }
                    function onBelowChanged() {
                        mark.requestPaint();
                    }
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
        // A maximized window is full-bleed: no band, so the client runs
        // to the screen's top edge and no transparent strip shows above
        // it. The pill is already tucked away when maximized.
        maximizedBorders.setTitle(0);
        // No shadow: the extended borders only exist to give the
        // aurorae engine a region for its own dark shadow, and that
        // shadow read as a black line above the window. The pill fits
        // entirely inside the title band, so it needs no headroom.
        extendedBorders.setAllBorders(0);
        decoration.installTitleItem(dragBand);
    }
}
