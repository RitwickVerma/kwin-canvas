/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
/*
    The canvas's window frame is no frame at all. The window wears
    nothing: no border, no shadow, no pill. The top edge is an
    invisible drag band, and the resize borders stay generous. The
    pill belongs to the effect now - the canvas's one pill rides any
    edge, drawn over the seam - so this decoration carries only what
    a decoration must: the drag surface and the resize grips.

    Keep the title: the invisible band is the hover surface for the
    native title drag. With the title at 0 the client covers the whole
    interior and there would be no band to drag.
*/
import QtQuick
import org.kde.kwin.decoration

Decoration {
    id: root
    alpha: true

    // The drag band: the whole top edge drags the window. Invisible by
    // design - the decoration's only job is the drag and the grips; the
    // window's chrome is the effect's pill.
    Item {
        id: dragBand
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 32
    }

    Component.onCompleted: {
        // The resize borders: a generous invisible band. The title is
        // the invisible drag band. No shadow: the extended borders only
        // exist to give the aurorae engine a region for its own dark
        // shadow, and that shadow read as a black line above the
        // window.
        borders.setBorders(6);
        borders.setTitle(32);
        maximizedBorders.setTitle(32);
        extendedBorders.setAllBorders(0);
        decoration.installTitleItem(dragBand);
    }
}
