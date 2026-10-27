import QtQuick
import AetherShared
import "."

// Type on the phone from here. The phone has to be using the KDE Connect keyboard (its input method);
// until it does, the page says so instead of sending keys into nothing.
Column {
    id: col
    property var d: ({})
    readonly property bool online: d.id !== undefined && d.reachable === true && d.pluginState !== undefined && d.pluginState["kdeconnect_remotekeyboard"] === true
    spacing: Tokens.space.md
    Component.onCompleted: if (d.id !== undefined) connectInput.watchKeyboard(d.id, true)
    Component.onDestruction: connectInput.watchKeyboard("", false)
    onDChanged: if (d.id !== undefined) connectInput.watchKeyboard(d.id, true)

    Rectangle {
        width: parent.width; height: hint.height + 2 * Tokens.space.md
        radius: Tokens.radius.lg
        color: Qt.rgba(1, 1, 1, Tokens.tint.subtle)
        Text {
            id: hint
            x: Tokens.space.md; y: Tokens.space.md
            width: parent.width - 2 * Tokens.space.md; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignLeft
            text: !col.online ? I18n.tr("The keyboard needs the phone to be connected with Keyboard switched on")
                : connectInput.keyboardReady ? I18n.f("Ready: what you type goes to %1", col.d.name)
                : I18n.tr("Switch to the KDE Connect keyboard on your phone to type from here")
            font { family: Theme.font; pixelSize: Tokens.type.label }
            color: connectInput.keyboardReady && col.online ? Theme.text : Theme.subtext
        }
    }
    Row {
        visible: col.online
        width: parent.width
        spacing: Tokens.space.sm
        TextField {
            id: field
            width: parent.width - sendBtn.width - Tokens.space.sm
            placeholder: I18n.tr("Type to send to the phone")
            onAccepted: sendBtn.clicked()
        }
        Button {
            id: sendBtn
            kind: "filled"; text: I18n.tr("Send")
            anchors.verticalCenter: parent.verticalCenter
            enabled: field.text.length > 0 && connectInput.keyboardReady
            onClicked: { connectInput.typeText(col.d.id, col.d.name, field.text); field.text = "" }
        }
    }
    Flow {      // keys that are not characters (these keep their physical direction, even in Hebrew)
        visible: col.online && connectInput.keyboardReady
        width: parent.width
        spacing: Tokens.space.sm
        LayoutMirroring.enabled: false
        Repeater {
            model: [{ t: "⌫", k: 16777219 }, { t: "⏎", k: 16777220 }, { t: "⇥", k: 16777217 }, { t: "←", k: 16777234 }, { t: "↑", k: 16777235 }, { t: "↓", k: 16777237 }, { t: "→", k: 16777236 }]
            delegate: Button {
                required property var modelData
                kind: "tonal"; text: modelData.t
                onClicked: connectInput.sendKey(col.d.id, modelData.k)
            }
        }
    }
    Text {
        visible: connectInput.lastAction.kind === "typed"
        width: parent.width; horizontalAlignment: Text.AlignLeft; wrapMode: Text.Wrap
        text: I18n.f("Typed on %1", connectInput.lastAction.device || "")
        font { family: Theme.font; pixelSize: Tokens.type.label }
        color: Theme.subtext
    }
}
