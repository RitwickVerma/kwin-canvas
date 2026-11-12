/*
    SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    A panel button that fires the Toggle Canvas chord: step out to the
    overworld, or back into the location under the screen centre. The chord
    is invoked by name through kglobalaccel, over D-Bus in plasmashell's own
    process (no process per click), so a rebinding in System Settings is
    followed. When the effect is not loaded the button dims and says so.
*/

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    // Whether KWin has the effect loaded: asked once at the start, again when KWin (re)appears on
    // the bus, and at every click, so a click on a canvas that is not there says so instead of
    // doing nothing.
    property bool loaded: true
    function askLoaded(then) {
        const reply = DBus.SessionBus.asyncCall({ service: "org.kde.KWin", path: "/Effects", iface: "org.kde.kwin.Effects",
                                                  member: "isEffectLoaded", arguments: ["kwin-canvas"], signature: "(s)" });
        reply.finished.connect(() => {
            root.loaded = !reply.isError && String(reply.value) === "true";
            if (then) then(root.loaded);
            reply.destroy();
        });
    }
    function toggle() {
        askLoaded(function (ok) {
            if (!ok) return;
            const reply = DBus.SessionBus.asyncCall({ service: "org.kde.kglobalaccel", path: "/component/kwin", iface: "org.kde.kglobalaccel.Component",
                                                      member: "invokeShortcut", arguments: ["Toggle Canvas"], signature: "(s)" });
            reply.finished.connect(() => reply.destroy());
        });
    }
    DBus.DBusServiceWatcher {
        watchedService: "org.kde.KWin"
        onRegisteredChanged: if (registered) root.askLoaded()
    }
    Component.onCompleted: askLoaded()

    compactRepresentation: PlasmaComponents3.ToolButton {
        icon.name: "view-grid"
        display: PlasmaComponents3.AbstractButton.IconOnly
        text: i18n("Canvas")
        opacity: root.loaded ? 1 : 0.45
        PlasmaComponents3.ToolTip.text: root.loaded ? i18n("Canvas: step out or back in") : i18n("Canvas: the effect is not loaded (turn it on in Desktop Effects, or make enable)")
        PlasmaComponents3.ToolTip.visible: hovered
        PlasmaComponents3.ToolTip.delay: Qt.styleHints.mousePressAndHoldInterval
        onClicked: root.toggle()
    }

    fullRepresentation: compactRepresentation
}
