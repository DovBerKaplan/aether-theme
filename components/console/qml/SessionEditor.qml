import QtQuick
import AetherShared

// New / edit connection. Save keeps it in aetherconsolerc; the key tile runs ssh-copy-id once,
// in a visible Konsole window (the password is typed there, never here).
PanelScaffold {
    id: root
    property var session: ({})
    signal saved()

    function begin(s) {
        session = s
        name.text = s.name || ""
        group.text = s.group || ""
        host.text = s.host || ""
        port.text = s.port || ""
        user.text = s.user || ""
        identity.text = s.identity || ""
        host.forceActiveFocus()
    }
    function collect() {
        return {
            id: session.id || "", name: name.text.trim(), group: group.text.trim(),
            host: host.text.trim(), port: port.text.trim(), user: user.text.trim(),
            identity: identity.text.trim(),
        }
    }

    title: session.id ? I18n.tr("Edit connection") : I18n.tr("New connection")
    subtitle: I18n.tr("saved on this machine · the session itself lives on the server")
    footerHeight: 48

    footer: Row {
        spacing: Tokens.space.sm
        anchors { left: parent.left; right: parent.right; leftMargin: Tokens.space.md; rightMargin: Tokens.space.md }
        Button {
            text: I18n.tr("Save")
            kind: "filled"
            enabled: host.text.trim().length > 0
            onClicked: { store.save(root.collect()); root.saved() }
        }
        Button {
            visible: !!root.session.id
            text: I18n.tr("Delete")
            kind: "negative"
            onClicked: { store.remove(root.session.id); root.saved() }
        }
    }

    Column {
        width: parent.width
        spacing: Tokens.space.md

        Column {
            width: parent.width - 2 * Tokens.space.md
            x: Tokens.space.md
            spacing: Tokens.space.xs
            Text {
                text: I18n.tr("Name"); font { family: Theme.font; pixelSize: Tokens.type.label } color: Theme.subtext
            }
            TextField { id: name; width: parent.width; placeholder: I18n.tr("optional") }
        }
        Column {
            width: parent.width - 2 * Tokens.space.md
            x: Tokens.space.md
            spacing: Tokens.space.xs
            Text {
                text: I18n.tr("Host"); font { family: Theme.font; pixelSize: Tokens.type.label } color: Theme.subtext
            }
            TextField { id: host; width: parent.width; placeholder: I18n.tr("address or hostname"); onAccepted: user.forceFocus() }
        }
        Row {
            x: Tokens.space.md
            width: parent.width - 2 * Tokens.space.md
            spacing: Tokens.space.md
            Column {
                width: (parent.width - Tokens.space.md) / 2
                spacing: Tokens.space.xs
                Text {
                    text: I18n.tr("User"); font { family: Theme.font; pixelSize: Tokens.type.label } color: Theme.subtext
                }
                TextField { id: user; width: parent.width; placeholder: I18n.tr("optional") }
            }
            Column {
                width: (parent.width - Tokens.space.md) / 2
                spacing: Tokens.space.xs
                Text {
                    text: I18n.tr("Port"); font { family: Theme.font; pixelSize: Tokens.type.label } color: Theme.subtext
                }
                TextField { id: port; width: parent.width; placeholder: "22" }
            }
        }
        Column {
            width: parent.width - 2 * Tokens.space.md
            x: Tokens.space.md
            spacing: Tokens.space.xs
            Text {
                text: I18n.tr("Group"); font { family: Theme.font; pixelSize: Tokens.type.label } color: Theme.subtext
            }
            TextField { id: group; width: parent.width; placeholder: I18n.tr("General") }
        }
        Column {
            width: parent.width - 2 * Tokens.space.md
            x: Tokens.space.md
            spacing: Tokens.space.xs
            Text {
                text: I18n.tr("Identity file"); font { family: Theme.font; pixelSize: Tokens.type.label } color: Theme.subtext
            }
            TextField { id: identity; width: parent.width; placeholder: I18n.tr("agent default") }
            Flow {
                width: parent.width
                spacing: Tokens.space.xs
                Repeater {
                    model: store.sshKeys()
                    Rectangle {
                        required property string modelData
                        radius: height / 2
                        width: keyLabel.implicitWidth + 2 * Tokens.space.md
                        height: 28
                        color: Theme.chip
                        border { width: tap.pressed ? 2 : 0; color: Theme.accent }
                        Text {
                            id: keyLabel
                            anchors.centerIn: parent
                            text: I18n.ltr(modelData.split("/").pop())
                            font { family: Theme.mono; pixelSize: Tokens.type.caption }
                            color: Theme.subtext
                        }
                        TapHandler { id: tap; onTapped: identity.text = modelData }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
        }
        Item { width: 1; height: Tokens.space.xs }
        ConfirmTile {
            id: deploy
            anchors.horizontalCenter: parent.horizontalCenter
            enabled: host.text.trim().length > 0
            label: I18n.tr("Deploy key")
            confirmLabel: I18n.tr("Deploy to host?")
            glyphSource: Qt.resolvedUrl("assets/glyphs/key.svg")
            timeoutMs: 4000
            onActivated: {
                const s = root.collect()
                launcher.deployKey(s)
                s.keyDeployed = true
                if (s.id) store.save(s)
            }
        }
        Text {
            width: parent.width - 2 * Tokens.space.md
            x: Tokens.space.md
            text: I18n.tr("Opens a Konsole window: the password (if any) is typed there, once. After that the agent and ControlMaster connect silently.")
            wrapMode: Text.Wrap
            font { family: Theme.font; pixelSize: Tokens.type.caption }
            color: Theme.subtext
        }
    }
}
