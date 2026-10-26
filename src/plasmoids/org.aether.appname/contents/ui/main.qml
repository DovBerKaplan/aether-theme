/*
    Aether App Name - the focused app's name in bold, macOS menu bar style.
    Click for a small app menu (Hide / Quit), as on a Mac.
    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // Shown when no window has focus (on a Mac the desktop belongs to Finder).
    readonly property string idleName: i18n("Desktop")

    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupDisabled
    }

    property string appName: idleName
    function refresh() {
        const idx = tasks.activeTask
        const name = idx.valid ? tasks.data(idx, TaskManager.AbstractTasksModel.AppName) : ""
        appName = name && name.length ? name : idleName
    }
    Connections {
        target: tasks
        function onActiveTaskChanged() { root.refresh() }
        function onDataChanged() { root.refresh() }
        function onCountChanged() { root.refresh() }
    }
    Component.onCompleted: refresh()

    fullRepresentation: MouseArea {
        id: area
        Layout.minimumWidth: label.implicitWidth + Kirigami.Units.largeSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        hoverEnabled: true
        onClicked: menu.openRelative()

        Rectangle {   // soft capsule on hover/press, like Tahoe's menu bar items
            anchors.centerIn: parent
            width: parent.width
            height: Math.min(parent.height - 6, label.implicitHeight + 8)
            radius: height / 2
            color: Kirigami.Theme.textColor
            opacity: area.pressed || menu.status === PlasmaExtras.Menu.Open ? 0.18 : area.containsMouse ? 0.10 : 0
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
        }

        PlasmaComponents3.Label {
            id: label
            anchors.centerIn: parent
            text: root.appName
            font.weight: Font.Bold
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        PlasmaExtras.Menu {
            id: menu
            visualParent: area
            placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup

            PlasmaExtras.MenuItem {
                text: i18n("Hide %1", root.appName)
                icon: "window-minimize"
                enabled: tasks.activeTask.valid
                onClicked: tasks.requestToggleMinimized(tasks.activeTask)
            }
            PlasmaExtras.MenuItem {
                separator: true
            }
            PlasmaExtras.MenuItem {
                text: i18n("Quit %1", root.appName)
                icon: "application-exit"
                enabled: tasks.activeTask.valid
                onClicked: tasks.requestClose(tasks.activeTask)
            }
        }
    }
}
