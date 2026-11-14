/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    Every window's icon and app name, from Plasma's task manager model: the
    model's window ids are KWin's own (the ids the map's windows carry), so a
    window's icon is a lookup. Loaded by main.qml through a Loader, so a
    system without the task manager's QML module loses the icons, not the map.
*/

import QtQuick
import org.kde.taskmanager as TaskManager
import "../code/layout.js" as MapLayout

Item {
    id: icons

    // Bumped on every rebuild: a binding that reads it asks again.
    property int rev: 0
    property var byId: ({})
    function iconFor(id) {
        const e = byId[MapLayout.normId(id)];
        return e ? e.icon : null;
    }
    function appNameFor(id) {
        const e = byId[MapLayout.normId(id)];
        return e ? e.app : "";
    }

    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
        filterMinimized: false
    }
    // A burst of changes (a session's windows arriving) is one rebuild.
    function rebuild() { rebuildTimer.restart(); }
    Timer {
        id: rebuildTimer
        interval: 50
        onTriggered: {
            const m = {};
            for (let i = 0; i < rows.count; ++i) {
                const o = rows.objectAt(i);
                if (!o || !o.ids) continue;
                for (let k = 0; k < o.ids.length; ++k) m[MapLayout.normId(o.ids[k])] = { icon: o.icon, app: o.appName };
            }
            icons.byId = m;
            icons.rev++;
        }
    }
    Instantiator {
        id: rows
        model: tasks
        delegate: QtObject {
            required property var model
            readonly property var ids: model.WinIdList
            readonly property var icon: model.decoration
            readonly property string appName: model.AppName || ""
            onIdsChanged: icons.rebuild()
            onIconChanged: icons.rebuild()
            onAppNameChanged: icons.rebuild()
        }
        onObjectAdded: icons.rebuild()
        onObjectRemoved: icons.rebuild()
    }
}
