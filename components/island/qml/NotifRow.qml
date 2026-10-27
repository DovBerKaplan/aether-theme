import QtQuick
import AetherShared
import "."

// One phone notification: who, when, what, the buttons the notification itself carries, an inline
// reply when it offers one, and a dismiss. The text is the phone's own, shown as plain text.
Item {
    id: root
    required property var n
    property string deviceId
    property bool replying: false

    implicitHeight: card.height
    height: implicitHeight
    function ago(ts) {
        const s = Math.max(0, (Date.now() - ts) / 1000)
        if (s < 60) return I18n.tr("now")
        if (s < 3600) return I18n.f("%1m", Math.floor(s / 60))
        if (s < 86400) return I18n.f("%1h", Math.floor(s / 3600))
        return I18n.f("%1d", Math.floor(s / 86400))
    }

    Rectangle {
        id: card
        width: parent.width
        height: col.height + 2 * Tokens.space.md
        radius: Tokens.radius.lg
        color: Qt.rgba(1, 1, 1, Tokens.tint.subtle)
        Behavior on height { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
        Column {
            id: col
            x: Tokens.space.md; y: Tokens.space.md
            width: parent.width - 2 * Tokens.space.md
            spacing: Tokens.space.sm

            Item {      // app, time, dismiss
                width: parent.width; height: 28
                Rectangle {
                    id: badge
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 28; height: 28; radius: 14; color: Theme.chip
                    clip: true
                    Image {
                        anchors.fill: parent; visible: status === Image.Ready
                        source: root.n.iconPath && root.n.iconPath.length > 0 ? "file://" + root.n.iconPath : ""
                        sourceSize: Qt.size(56, 56); fillMode: Image.PreserveAspectCrop
                    }
                    Text {
                        anchors.centerIn: parent
                        text: (root.n.appName || "?").charAt(0).toUpperCase(); textFormat: Text.PlainText
                        font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.DemiBold }
                        color: Theme.subtext
                    }
                }
                Text {
                    anchors { left: badge.right; leftMargin: Tokens.space.sm; right: dismiss.left; rightMargin: Tokens.space.sm; verticalCenter: parent.verticalCenter }
                    horizontalAlignment: Text.AlignLeft; elide: Text.ElideRight; textFormat: Text.PlainText
                    text: (root.n.appName || "") + "  ·  " + root.ago(root.n.ts)
                    font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium }
                    color: Theme.subtext
                }
                Item {
                    id: dismiss
                    visible: root.n.dismissable
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 28; height: 28
                    Rectangle {
                        anchors.fill: parent; radius: 14
                        color: Qt.rgba(1, 1, 1, dTap.pressed ? Tokens.tint.strong : dHover.hovered ? Tokens.tint.soft : 0)
                    }
                    Glyph { anchors.centerIn: parent; name: "close"; size: 11; color: Theme.subtext }
                    HoverHandler { id: dHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: dTap; onTapped: connectModel.dismissNotification(root.deviceId, root.n.id) }
                }
            }
            Text {
                visible: text.length > 0
                width: parent.width; text: root.n.title || ""; textFormat: Text.PlainText
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.DemiBold }
                color: Theme.text
            }
            Text {
                visible: text.length > 0
                width: parent.width; text: root.n.text || ""; textFormat: Text.PlainText
                wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                font { family: Theme.font; pixelSize: Tokens.type.label }
                color: Theme.subtext
            }
            Flow {      // the notification's own buttons, and Reply
                visible: (root.n.actions && root.n.actions.length > 0) || (root.n.replyId && root.n.replyId.length > 0)
                width: parent.width
                spacing: Tokens.space.sm
                Repeater {
                    model: root.n.actions || []
                    delegate: Button {
                        required property string modelData
                        kind: "tonal"; text: modelData
                        onClicked: connectModel.notificationAction(root.deviceId, root.n.internalId, modelData)
                    }
                }
                Button {
                    visible: root.n.replyId && root.n.replyId.length > 0
                    kind: root.replying ? "text" : "tonal"
                    text: root.replying ? I18n.tr("Cancel") : I18n.tr("Reply")
                    onClicked: { root.replying = !root.replying; if (root.replying) replyField.forceFocus() }
                }
            }
            Row {
                visible: root.replying
                width: parent.width
                spacing: Tokens.space.sm
                TextField {
                    id: replyField
                    width: parent.width - replySend.width - Tokens.space.sm
                    placeholder: I18n.tr("Write a reply…")
                    onAccepted: replySend.clicked()
                }
                Button {
                    id: replySend
                    kind: "filled"; text: I18n.tr("Send")
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: replyField.text.trim().length > 0
                    onClicked: {
                        connectModel.replyToNotification(root.deviceId, root.n.replyId, replyField.text)
                        replyField.text = ""
                        root.replying = false
                    }
                }
            }
        }
    }
}
