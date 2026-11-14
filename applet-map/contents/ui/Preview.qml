/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    A window's live picture: KWin streams the window (by its id, the one the
    map's windows carry) over PipeWire, the way Plasma's task manager shows
    its previews. Loaded by WindowSheet through a Loader only while the map is
    looked at, so the stream lives exactly as long as it is seen; a system
    without KPipeWire's QML module keeps the icons instead.
*/

import QtQuick
import org.kde.pipewire as PipeWire
import org.kde.taskmanager as TaskManager

PipeWire.PipeWireSourceItem {
    id: preview

    property string uuid: ""

    nodeId: request.nodeId
    objectSerial: request.objectSerial
    visible: request.nodeId > 0 && preview.ready

    TaskManager.ScreencastingRequest {
        id: request
        uuid: preview.uuid
    }
}
