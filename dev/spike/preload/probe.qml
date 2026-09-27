// SPDX-FileCopyrightText: 2026 Aaron Bockelie <aaronsb@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Probe client: logs every press, release and key it receives with
// surface-local coordinates, so the harness can check where input landed.
import QtQuick
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
        onPressed: (m) => console.log("PROBE", win.title, "press", m.x.toFixed(1), m.y.toFixed(1))
        onReleased: (m) => console.log("PROBE", win.title, "release", m.x.toFixed(1), m.y.toFixed(1))
    }
}
