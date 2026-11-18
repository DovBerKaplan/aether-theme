import QtQuick
import AetherShared

// One entry in the island's notification history. Quieter than a toast: no lifetime,
// no borders - a soft row that highlights on hover, dismisses on click.
Item {
    id: root
    property string app
    property string icon
    property string summary
    property string body
    property int urgency: 1
    property real ts: 0
    property date now: new Date()
    signal dismissed()

    height: 68

    function ago() {
        const s = Math.max(0, (root.now.getTime() - root.ts) / 1000)
        if (s < 60) return I18n.tr("now")
        if (s < 3600) return I18n.f("%1m", Math.floor(s / 60))
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius.xl
        color: Theme.veil(hover.hovered || tap.pressed ? Tokens.tint.subtle : Tokens.tint.faint)
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

    Rectangle {
        id: appIcon
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        width: 38; height: 38; radius: Tokens.radius.md
        color: Theme.chip
        clip: true
        Image {
            anchors.fill: parent
            anchors.margins: 5
            sourceSize: Qt.size(76, 76)
            source: "image://icon/" + (root.icon || "dialog-information")
            smooth: true
        }
    }
    Column {
        anchors { left: appIcon.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 1
        Item {
            width: parent.width
            height: appLabel.implicitHeight
            Text {
                id: appLabel
                anchors.left: parent.left
                width: Math.min(implicitWidth, parent.width - timeText.width - 10)
                text: root.app
                elide: Text.ElideRight
                font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium; capitalization: Font.AllUppercase; letterSpacing: 0.6 }
                color: Theme.subtext
            }
            Text {
                id: timeText
                anchors.right: parent.right
                text: root.ago()
                font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium }
                color: Theme.subtext
            }
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
            font { family: Theme.font; pixelSize: Tokens.type.label }
            color: Qt.alpha(Theme.text, Tokens.tint.textDim)
        }
    }
    // Urgent notifications keep the accent line they had as toasts.
    Rectangle {
        visible: root.urgency >= 2
        anchors.left: parent.left; y: 14; width: 3; height: root.height - 28; radius: Tokens.radius.hair
        color: Theme.accentFill
    }
    Rectangle {                          // dismiss, only while hovered
        anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 10 }
        width: 22; height: 22; radius: Tokens.radius.md
        color: Theme.chip
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
        Text { anchors.centerIn: parent; text: "✕"; color: Theme.text; font.pixelSize: Tokens.type.caption }
        TapHandler { onTapped: root.dismissed() }
    }
    TapHandler { id: tap; onTapped: root.dismissed() }
}
