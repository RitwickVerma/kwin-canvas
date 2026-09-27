// SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Probe client: logs every press, release and key it receives with
// surface-local coordinates, so the harness can check where input landed.
// A right press opens a menu at the pointer as its own window (an
// xdg_popup with a grab), with a submenu; the menus log opening, closing
// and the item triggered. Their backgrounds are flat colours a screenshot
// can find: the menu magenta, the submenu cyan.
import QtQuick
import QtQuick.Controls
import QtQuick.Window

Window {
    id: win
    title: "Probe " + Qt.application.arguments[Qt.application.arguments.length - 1]
    width: 400; height: 300
    visible: true
    color: active ? "#2a4" : "#555"
    onActiveChanged: console.log("PROBE", title, "active", active)

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: (e) => console.log("PROBE", win.title, "key", e.text, e.key)
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: (m) => {
            console.log("PROBE", win.title, "press", m.x.toFixed(1), m.y.toFixed(1));
            if (m.button === Qt.RightButton) menu.popup();
        }
        onReleased: (m) => console.log("PROBE", win.title, "release", m.x.toFixed(1), m.y.toFixed(1))
    }

    component ProbeItem : MenuItem {
        implicitWidth: 160
        implicitHeight: 30
        onTriggered: console.log("PROBE", win.title, "triggered", text)
    }

    Menu {
        id: menu
        popupType: Popup.Window
        padding: 10
        background: Rectangle { implicitWidth: 180; color: "#f0f" }
        onOpened: console.log("PROBE", win.title, "menu opened")
        onClosed: console.log("PROBE", win.title, "menu closed")
        ProbeItem { text: "One" }
        ProbeItem { text: "Two" }
        Menu {
            id: sub
            title: "More"
            popupType: Popup.Window
            padding: 10
            background: Rectangle { implicitWidth: 180; color: "#0ff" }
            onOpened: console.log("PROBE", win.title, "submenu opened")
            onClosed: console.log("PROBE", win.title, "submenu closed")
            ProbeItem { text: "Three" }
            ProbeItem { text: "Four" }
        }
    }
}
