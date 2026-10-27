import QtQuick
import AetherShared
import "."

// A transient card the island grows for something that just happened (a file arrived, later a call):
// glyph, what, who, one or two buttons. It leaves by itself; tapping the card opens the related panel.
//   a: { glyph, title, text, buttons: [{id, label, glyph}] }
Item {
    id: root
    property var a: ({})
    readonly property alias hovered: hover.hovered
    signal activated(string what)       // "tap" or a button id
    signal dismissed()

    HoverHandler { id: hover }
    TapHandler { onTapped: root.activated("tap") }

    Rectangle {
        id: disc
        anchors { left: parent.left; leftMargin: Tokens.space.xl; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
        width: 48; height: 48; radius: 24
        color: Theme.chip
        border { width: root.a.accent ? 2 : 0; color: Theme.accent }
        SequentialAnimation on scale {      // a ringing call breathes
            running: root.a.pulse === true
            loops: Animation.Infinite
            NumberAnimation { to: 1.08; duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.ambient }
            NumberAnimation { to: 1.0; duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.ambient }
        }
        Glyph { anchors.centerIn: parent; name: root.a.glyph || "phone"; size: 22 }
    }
    Column {
        anchors { left: disc.right; leftMargin: Tokens.space.md; right: btns.left; rightMargin: Tokens.space.md; verticalCenter: disc.verticalCenter }
        spacing: 2
        Text {
            width: parent.width; horizontalAlignment: Text.AlignLeft; elide: Text.ElideRight; textFormat: Text.PlainText
            text: root.a.title || ""
            font { family: Theme.font; pixelSize: Tokens.type.label }
            color: Theme.subtext
        }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignLeft; elide: Text.ElideMiddle; textFormat: Text.PlainText
            text: root.a.text || ""
            font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.DemiBold }
            color: Theme.text
        }
    }
    Row {
        id: btns
        anchors { right: parent.right; rightMargin: Tokens.space.xl; verticalCenter: disc.verticalCenter }
        spacing: Tokens.space.sm
        Repeater {
            model: root.a.buttons || []
            delegate: Item {
                required property var modelData
                required property int index
                readonly property bool iconOnly: modelData.glyph !== undefined && !modelData.label
                implicitWidth: iconOnly ? 36 : txt.implicitWidth
                width: implicitWidth; height: 36
                Button {      // a labelled button; the first one is the main action
                    id: txt
                    visible: !parent.iconOnly
                    kind: parent.modelData.kind || (parent.index === 0 ? "filled" : "tonal")
                    text: parent.modelData.label || ""
                    onClicked: root.activated(parent.modelData.id)
                }
                Rectangle {   // an icon-only button
                    visible: parent.iconOnly
                    anchors.fill: parent; radius: 18
                    color: Qt.rgba(1, 1, 1, iTap.pressed ? Tokens.tint.strong : iHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                    Glyph { anchors.centerIn: parent; name: parent.parent.modelData.glyph || ""; size: 16 }
                    HoverHandler { id: iHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: iTap; onTapped: root.activated(parent.parent.modelData.id) }
                }
            }
        }
    }
}
