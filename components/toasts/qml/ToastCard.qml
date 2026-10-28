import QtQuick
import AetherShared

// One notification card that drops from above and slides back up when done.
Item {
    id: root
    property string app
    property string icon
    property string summary
    property string body
    property int urgency: 1
    property int lifetime: 5000
    property real slotY: 46            // where it rests (set by the stack)
    property bool shown: false

    signal dismissed()
    signal activated()

    width: 380
    height: 78
    y: shown ? slotY : -height - 10
    opacity: shown ? 1 : 0
    Behavior on y { SpringAnimation { spring: 3.0; damping: 0.30; epsilon: 0.3 } }
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }

    function close() { shown = false; removeTimer.start() }
    Component.onCompleted: shown = true
    Timer { id: removeTimer; interval: 320; onTriggered: root.dismissed() }
    Timer {
        interval: root.lifetime
        running: root.shown && !hover.hovered && root.urgency < 2     // critical ones wait for a click
        onTriggered: root.close()
    }

    CardSurface { anchors.fill: parent; radius: Tokens.radius.card }
    HoverHandler { id: hover }

    Image {
        id: appIcon
        x: 16; y: 16
        width: 40; height: 40
        sourceSize: Qt.size(80, 80)
        source: "image://icon/" + (root.icon || "dialog-information")
        smooth: true
    }
    Column {
        anchors { left: appIcon.right; leftMargin: 12; right: parent.right; rightMargin: 40; verticalCenter: parent.verticalCenter }
        spacing: 1
        Text {
            width: parent.width
            text: root.app
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium; capitalization: Font.AllUppercase; letterSpacing: 0.6 }
            color: Theme.subtext
        }
        Text {
            width: parent.width
            text: root.summary
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.DemiBold }
            color: Theme.text
        }
        Text {
            width: parent.width
            text: root.body.replace(/<[^>]*>/g, "")
            visible: text.length > 0
            elide: Text.ElideRight
            maximumLineCount: 1
            font { family: Theme.font; pixelSize: Tokens.type.body }
            color: Qt.alpha(Theme.text, Tokens.tint.textDim)
        }
    }
    // Critical notifications get a thin accent line on the left edge.
    Rectangle {
        visible: root.urgency >= 2
        x: 0; y: 18; width: 3; height: root.height - 36; radius: Tokens.radius.hair
        color: Theme.accent
    }
    Rectangle {                          // dismiss, only while hovered
        anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 12 }
        width: 22; height: 22; radius: Tokens.radius.md
        color: Theme.chip
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
        Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: Tokens.type.caption }
        TapHandler { onTapped: root.close() }
    }
    TapHandler { onTapped: { root.activated(); root.close() } }
}
