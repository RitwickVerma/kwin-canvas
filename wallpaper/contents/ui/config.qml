/*
    SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kquickcontrols as KQuickControls
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout

    property alias cfg_Background: backgroundButton.color
    property alias cfg_LineColor: lineButton.color
    property alias cfg_GridBase: gridBase.value
    property alias cfg_TileImage: tileImage.text
    property alias cfg_ShowLabels: showLabels.checked
    property alias formLayout: root

    // The Canvas effect writes these from its own settings at every move (its "Publish the ground"
    // knob, on by default), so a change made here is overwritten the next time the desktop slides.
    QQC2.Label {
        Kirigami.FormData.isSection: true
        width: Math.min(root.width, 560)
        wrapMode: Text.WordWrap
        text: "With the Canvas effect on, these follow the effect's own settings (Desktop Effects → Canvas → configure → The ground) at every move of the desktop. Set them there, or turn off \"Publish the ground\" in the effect to keep what you set here."
    }
    KQuickControls.ColorButton {
        id: backgroundButton
        Kirigami.FormData.label: "Background:"
    }
    KQuickControls.ColorButton {
        id: lineButton
        Kirigami.FormData.label: "Grid lines:"
    }
    QQC2.SpinBox {
        id: gridBase
        Kirigami.FormData.label: "Minor grid spacing:"
        from: 8
        to: 1024
    }
    QQC2.TextField {
        id: tileImage
        Kirigami.FormData.label: "Tile image (optional):"
        placeholderText: "file:///path/to/tile.png"
    }
    QQC2.CheckBox {
        id: showLabels
        Kirigami.FormData.label: "Coordinate labels:"
    }
}
