import QtQuick
import AetherShared

// Single-line entry. `password` hides the text, offers Show/Hide and blocks copy/cut.
Item {
    id: root
    property alias text: input.text
    property string placeholder
    property bool password: false
    property bool error: false
    property string errorText
    signal accepted()

    implicitWidth: 300
    implicitHeight: 44 + (error && errorText.length > 0 ? errMsg.implicitHeight + Tokens.space.xs : 0)
    function forceFocus() { input.forceActiveFocus() }
    function shake() { shakeAnim.restart() }
    property bool revealed: false

    Item {
        id: shaker
        width: parent.width; height: 44
        SequentialAnimation {
            id: shakeAnim
            loops: 1
            NumberAnimation { target: shaker; property: "x"; to: -6; duration: 30 }
            NumberAnimation { target: shaker; property: "x"; to: 6; duration: 40 }
            NumberAnimation { target: shaker; property: "x"; to: -6; duration: 40 }
            NumberAnimation { target: shaker; property: "x"; to: 6; duration: 40 }
            NumberAnimation { target: shaker; property: "x"; to: -6; duration: 40 }
            NumberAnimation { target: shaker; property: "x"; to: 0; duration: 30 }
        }
        Rectangle {
            anchors.fill: parent
            radius: Tokens.radius.md
            color: Tokens.role.dark.surfaceSunken
            border {
                width: input.activeFocus || root.error ? 2 : 1
                color: root.error ? Tokens.role.island.negative : input.activeFocus ? Theme.accent : Theme.rim
            }
        }
        // the whole box is the target, not just the text line inside it
        TapHandler { onTapped: input.forceActiveFocus() }
        HoverHandler { cursorShape: Qt.IBeamCursor }
        Text {
            visible: input.text.length === 0 && !input.activeFocus
            anchors { left: parent.left; leftMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
            text: root.placeholder; textFormat: Text.PlainText
            font { family: Theme.font; pixelSize: Tokens.type.body }
            color: Theme.subtext
        }
        TextInput {
            id: input
            anchors {
                left: parent.left; leftMargin: Tokens.space.md
                right: reveal.visible ? reveal.left : parent.right; rightMargin: Tokens.space.md
                verticalCenter: parent.verticalCenter
            }
            clip: true
            echoMode: root.password && !root.revealed ? TextInput.Password : TextInput.Normal
            persistentSelection: false
            selectionColor: Theme.accent
            selectedTextColor: Tokens.role.dark.textOnAccent
            font { family: Theme.font; pixelSize: Tokens.type.body }
            color: Theme.text
            onAccepted: root.accepted()
            Keys.onPressed: (e) => {
                if (root.password && (e.matches(StandardKey.Copy) || e.matches(StandardKey.Cut))) e.accepted = true
            }
        }
        Text {
            id: reveal
            visible: root.password
            anchors { right: parent.right; rightMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
            text: root.revealed ? I18n.tr("Hide") : I18n.tr("Show")
            font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium }
            color: Theme.subtext
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.revealed = !root.revealed }
        }
    }
    Text {
        id: errMsg
        visible: root.error && root.errorText.length > 0
        y: 44 + Tokens.space.xs
        width: parent.width
        text: root.errorText; textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font { family: Theme.font; pixelSize: Tokens.type.label }
        color: Tokens.role.island.negative
    }
}
