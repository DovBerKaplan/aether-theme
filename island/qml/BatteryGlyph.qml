import QtQuick

// Battery: rounded outline, level fill, little tip; the fill turns accent while charging
// and red-ish when low.
Item {
    id: root
    property int percent: 100
    property bool charging: false
    implicitWidth: 25
    implicitHeight: 12

    readonly property color fillColor: charging ? Theme.accent : (percent <= 15 ? "#ff6b6b" : Theme.text)
    Rectangle {
        id: shell
        width: 22; height: 12; radius: 3.5
        color: "transparent"
        border.width: 1.4
        border.color: Qt.rgba(1, 1, 1, 0.55)
        Rectangle {
            x: 2.4; y: 2.4
            width: Math.max(2, (shell.width - 4.8) * root.percent / 100)
            height: shell.height - 4.8
            radius: 1.5
            color: root.fillColor
        }
    }
    Rectangle {
        x: 23; y: 4; width: 2; height: 4; radius: 1
        color: Qt.rgba(1, 1, 1, 0.55)
    }
}
