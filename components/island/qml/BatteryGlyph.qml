import QtQuick
import AetherShared

// Battery: rounded outline, level fill, little tip; the fill turns accent while charging
// and red-ish when low.
Item {
    id: root
    property int percent: 100
    property bool charging: false
    implicitWidth: 25
    implicitHeight: 12

    readonly property color fillColor: charging ? Theme.accent : (percent <= 15 ? Tokens.role.island.negative : Theme.text)
    Rectangle {
        id: shell
        width: 22; height: 12; radius: Tokens.radius.xs
        color: "transparent"
        border.width: 1.4
        border.color: Theme.veil(Tokens.tint.edge)
        Rectangle {
            x: 2.4; y: 2.4
            width: Math.max(2, (shell.width - 4.8) * root.percent / 100)
            height: shell.height - 4.8
            radius: Tokens.radius.hair
            color: root.fillColor
        }
    }
    Rectangle {
        x: 23; y: 4; width: 2; height: 4; radius: Tokens.radius.hair
        color: Theme.veil(Tokens.tint.edge)
    }
}
