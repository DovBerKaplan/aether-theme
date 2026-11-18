import QtQuick
import org.kde.kirigami as Kirigami
import AetherShared

// A round dark-glass button with an icon: close, translate, Lens.
Rectangle {
    id: root
    property string icon
    property bool active: false
    signal clicked()

    implicitWidth: 44
    implicitHeight: 44
    radius: width / 2
    color: active ? Qt.rgba(Tokens.role.lens.primary.r, Tokens.role.lens.primary.g, Tokens.role.lens.primary.b, 0.95)
                   : (ma.pressed ? Qt.rgba(Theme.chip.r, Theme.chip.g, Theme.chip.b, 0.92)
                                 : Qt.rgba(Theme.bodyTop.r, Theme.bodyTop.g, Theme.bodyTop.b, 0.82))
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, active ? 0 : 0.12)
    scale: ma.pressed ? 0.92 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.4 } }
    Behavior on color { ColorAnimation { duration: 140 } }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: 22; height: 22
        visible: root.icon !== ""
        source: root.icon
        color: root.active ? Tokens.role.lens.textOnPrimary : Theme.text
        isMask: true
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
