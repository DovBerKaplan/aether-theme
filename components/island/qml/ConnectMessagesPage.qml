import QtQuick
import AetherShared
import "."

// Write a text message that goes out from the phone's own number. Recipients are suggested from the phone's
// synced contacts while you type (kept in memory only while this page is open); nothing here reads or
// shows existing conversations (that needs the SMS check, see docs/WIDGETS-SPEC.md section 5).
Column {
    id: col
    property var d: ({})
    property var suggestions: []
    property string recipientName: ""
    readonly property bool online: d.id !== undefined && d.reachable === true && d.pluginState !== undefined && d.pluginState["kdeconnect_sms"] === true
    readonly property bool valid: /^[+0-9 ()\-]{3,24}$/.test(to.text.trim()) && body.text.trim().length > 0
    spacing: Tokens.space.sm
    // Choosing a suggestion removes the row that was clicked, so the work happens here, not in its handler.
    function pick(name, number) {
        to.text = number            // first: changing the text clears the name
        recipientName = name
        suggestions = []
        focusBody.restart()
    }
    Component.onDestruction: connectInput.closeContacts()
    Timer { id: focusBody; interval: 150; onTriggered: body.forceFocus() }   // after the suggestion row (which held the click) is gone

    Text {
        visible: !col.online
        width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignLeft
        text: I18n.tr("Messages need the phone to be connected with Messages switched on")
        font { family: Theme.font; pixelSize: Tokens.type.label }
        color: Theme.subtext
    }
    TextField {
        id: to
        visible: col.online
        width: parent.width
        placeholder: I18n.tr("To (name or number)")
        onTextChanged: { col.recipientName = ""; col.suggestions = col.online ? connectInput.suggest(col.d.id, text) : [] }
    }
    Repeater {
        model: col.online ? col.suggestions : []
        delegate: ListRow {
            required property var modelData
            width: col.width
            height: 52
            title: modelData.name
            subtitle: modelData.number
            onClicked: col.pick(modelData.name, modelData.number)
        }
    }
    Text {
        visible: col.recipientName.length > 0
        width: parent.width; horizontalAlignment: Text.AlignLeft; elide: Text.ElideRight; textFormat: Text.PlainText
        text: col.recipientName
        font { family: Theme.font; pixelSize: Tokens.type.label }
        color: Theme.subtext
    }
    TextField {
        id: body
        visible: col.online
        width: parent.width
        placeholder: I18n.tr("Message")
        onAccepted: sendBtn.clicked()
    }
    Button {
        id: sendBtn
        visible: col.online
        kind: "filled"; text: I18n.tr("Send")
        enabled: col.valid
        onClicked: if (connectInput.sendSms(col.d.id, col.d.name, to.text, body.text)) body.text = ""
    }
    Text {
        visible: connectInput.lastAction.kind === "sms"
        width: parent.width; horizontalAlignment: Text.AlignLeft; wrapMode: Text.Wrap
        text: I18n.f("Message sent via %1", connectInput.lastAction.device || "")
        font { family: Theme.font; pixelSize: Tokens.type.label }
        color: Theme.subtext
    }
}
