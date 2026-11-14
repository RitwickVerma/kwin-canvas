/*
    SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The map's settings: what the panel shows, how the plane is drawn, and
    whether minimized windows and live pictures are on it.
*/
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property string cfg_panelView
    property alias cfg_toScale: toScale.checked
    property alias cfg_showMinimized: showMinimized.checked
    property alias cfg_livePreviews: livePreviews.checked

    Kirigami.FormLayout {
        QQC2.RadioButton {
            Kirigami.FormData.label: i18n("In a panel:")
            text: i18n("A button for each cluster")
            checked: cfg_panelView !== "map"
            onToggled: if (checked) cfg_panelView = "clusters"
        }
        QQC2.RadioButton {
            text: i18n("A small map")
            checked: cfg_panelView === "map"
            onToggled: if (checked) cfg_panelView = "map"
        }
        QQC2.CheckBox {
            id: toScale
            Kirigami.FormData.label: i18n("The map:")
            text: i18n("Draw the plane to scale (far clusters become small)")
        }
        QQC2.CheckBox {
            id: showMinimized
            text: i18n("Show minimized windows")
        }
        QQC2.CheckBox {
            id: livePreviews
            text: i18n("Live window pictures while the map is open")
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Each picture is a screencast of the window. They run only while the panel's map is open or the pointer is on the desktop's map, stop while a game has the focus, and skip windows hidden from capture.")
        }
    }
}
