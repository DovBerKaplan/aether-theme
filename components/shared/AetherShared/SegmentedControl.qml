import QtQuick
import AetherShared

// 2-4 exclusive options; the raised thumb slides to the selection.
Item {
    id: root
    property var model: []
    property int currentIndex: 0
    signal activated(int index)

    implicitWidth: 300
    implicitHeight: 36
    activeFocusOnTab: true
    readonly property real segW: model.length > 0 ? (width - 6) / model.length : 0
    function pick(i) {
        if (i < 0 || i >= model.length || i === currentIndex) return
        currentIndex = i
        activated(i)
    }
    Keys.onLeftPressed: pick(currentIndex - 1)
    Keys.onRightPressed: pick(currentIndex + 1)

    Rectangle {
        anchors.fill: parent; radius: height / 2
        color: Qt.rgba(1, 1, 1, Tokens.tint.subtle)
        border { width: root.activeFocus ? 2 : 0; color: Theme.accent }
    }
    Rectangle {
        x: I18n.rtl ? root.width - 3 - (root.currentIndex + 1) * root.segW : 3 + root.currentIndex * root.segW; y: 3
        width: root.segW; height: parent.height - 6; radius: height / 2
        color: Theme.chip
        border { width: 1; color: Theme.rim }
        Behavior on x { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
    }
    Row {
        x: 3; y: 3; height: parent.height - 6
        Repeater {
            model: root.model
            Item {
                required property int index
                required property string modelData
                width: root.segW; height: parent.height
                Text {
                    anchors.centerIn: parent
                    text: modelData; textFormat: Text.PlainText
                    font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
                    color: index === root.currentIndex ? Theme.text : Theme.subtext
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.pick(index) }
            }
        }
    }
}
