import QtQuick

// Small frosted pop-up list (sessions, power actions). Items: [{text, icon, enabled, action}]
Rectangle {
    id: root
    property var palette
    property var items: []
    property int current: -1
    property string fontFamily
    signal picked(int index)

    width: 240
    height: column.implicitHeight + 16
    radius: 22
    color: palette.menu
    border.width: 1
    border.color: palette.glassBorder
    opacity: visible ? 1 : 0
    transformOrigin: Item.Bottom
    scale: visible ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: 160 } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

    Column {
        id: column
        anchors.fill: parent
        anchors.margins: 8
        spacing: 2
        Repeater {
            model: root.items
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: column.width
                height: 40
                radius: 14
                enabled: modelData.enabled !== false
                opacity: enabled ? 1 : 0.4
                color: rowMouse.containsMouse ? root.palette.glassHover
                     : (index === root.current ? root.palette.glass : "transparent")
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 12
                    spacing: 10
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!modelData.icon
                        name: modelData.icon || "session"
                        size: 16
                        color: root.palette.text
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.text
                        color: root.palette.text
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        font.weight: index === root.current ? Font.DemiBold : Font.Normal
                    }
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(index)
                }
            }
        }
    }
}
