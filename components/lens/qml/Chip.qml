import QtQuick
import org.kde.kirigami as Kirigami
import AetherShared

// An action chip in the results sheet: icon + label, outlined, filled when primary.
Rectangle {
    id: root
    property string text
    property string icon
    property bool primary: false
    property bool lensMark: false
    property bool translateMark: false
    signal clicked()

    implicitHeight: 36
    implicitWidth: row.implicitWidth + 28
    radius: height / 2
    color: primary ? (ma.pressed ? Tokens.role.lens.primaryPressed : Tokens.role.lens.primary)
                     : (ma.pressed ? Qt.rgba(1, 1, 1, 0.14) : (ma.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"))
    border.width: primary ? 0 : 1
    border.color: Qt.rgba(1, 1, 1, 0.22)
    Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.space.sm
        Item {
            id: glyphSlot
            width: 18; height: 18
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== "" || root.lensMark || root.translateMark
            TranslateGlyph { anchors.centerIn: parent; visible: root.translateMark; size: 18; color: root.primary ? Tokens.role.lens.textOnPrimary : Theme.text; cut: root.primary ? Tokens.role.lens.primary : "#1c1e24" }
            LensGlyph { anchors.centerIn: parent; visible: root.lensMark; size: 18; color: root.primary ? Tokens.role.lens.textOnPrimary : Theme.text }
            Kirigami.Icon {
                anchors.fill: parent
                visible: root.icon !== ""
                source: root.icon
                isMask: true
                color: root.primary ? Tokens.role.lens.textOnPrimary : Theme.text
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.Medium
            color: root.primary ? Tokens.role.lens.textOnPrimary : Theme.text
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
