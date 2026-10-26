import QtQuick

// Round frosted button used in the corners and inside the password pill.
Rectangle {
    id: root
    property string icon
    property var palette
    property int iconSize: 18
    property bool accent: false
    signal clicked()

    implicitWidth: 44
    implicitHeight: 44
    radius: height / 2
    color: accent ? palette.accent
                  : (mouse.containsMouse ? palette.glassHover : palette.glass)
    border.width: accent ? 0 : 1
    border.color: palette.glassBorder
    scale: mouse.pressed ? 0.92 : 1.0
    activeFocusOnTab: true

    Behavior on color { ColorAnimation { duration: 160 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: root.iconSize
        color: root.accent ? root.palette.onAccent : root.palette.text
    }

    Rectangle {           // keyboard focus ring
        anchors.fill: parent
        anchors.margins: -3
        radius: height / 2
        color: "transparent"
        border.width: 2
        border.color: root.palette.accent
        visible: root.activeFocus
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    Keys.onReturnPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()
}
