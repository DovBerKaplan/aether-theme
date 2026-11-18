import QtQuick
import AetherShared
import "."

// Sound panel (docs/PANELS-SPEC.md section 6): output volume, output picker, microphone and
// per-app volumes. Reads PipeWire's PulseAudio layer only while the panel is open.
PanelScaffold {
    id: root
    property string page: ""
    signal pageRequested(string page)
    signal closeRequested()

    readonly property var out: sound.outputs.find(o => o.isDefault) || (sound.outputs.length > 0 ? sound.outputs[0] : null)
    readonly property var mic: sound.inputs.length > 0 ? sound.inputs[0] : null

    title: I18n.tr("Sound")
    subtitle: out ? out.description : I18n.tr("No output device")
    showBack: true
    headerTrailing: [
        Button {
            visible: root.out !== null
            kind: "tonal"
            text: root.out && root.out.muted ? I18n.tr("Unmute") : I18n.tr("Mute")
            onClicked: sound.setOutputMuted(root.out.name, !root.out.muted)
        }
    ]
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Button { kind: "text"; text: I18n.tr("Sound settings ↗"); anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                onClicked: { sound.openSettings(); root.closeRequested() } }
        }
    ]
    Component.onCompleted: sound.setActive(true)
    Component.onDestruction: sound.setActive(false)

    Column {
        width: parent.width
        spacing: Tokens.space.xs
        Column {
            x: 22; width: parent.width - 44
            spacing: Tokens.space.xs

            // hero: the active output and its volume
            Rectangle {
                visible: root.out !== null
                width: parent.width
                height: 76
                radius: Tokens.radius.lg
                color: Theme.veil(Tokens.tint.subtle)
                Row {
                    x: Tokens.space.lg; y: Tokens.space.md
                    width: parent.width - 2 * Tokens.space.lg
                    spacing: Tokens.space.md
                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        name: !root.out || root.out.muted || root.out.volume === 0 ? "volume-muted" : root.out.volume < 34 ? "volume-1" : "volume-2"
                        size: 22
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 22 - 44 - 2 * Tokens.space.md
                        text: root.out ? root.out.description : ""; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                        font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.DemiBold }
                        color: Theme.text
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44; horizontalAlignment: Text.AlignRight
                        text: root.out ? root.out.volume + "%" : ""
                        font { family: Theme.mono; pixelSize: Tokens.type.body }
                        color: Theme.subtext
                    }
                }
                SliderBar {
                    x: Tokens.space.lg; y: parent.height - height - Tokens.space.sm
                    width: parent.width - 2 * Tokens.space.lg
                    value: root.out && !root.out.muted ? root.out.volume / 100 : 0
                    onMoved: (v) => sound.setOutputVolume(root.out.name, Math.round(v * 100))
                }
            }

            SectionLabel { visible: sound.outputs.length > 1; width: parent.width; text: I18n.tr("Output") }
            Repeater {
                model: sound.outputs.length > 1 ? sound.outputs : []
                delegate: ListRow {
                    required property var modelData
                    width: parent.width
                    title: modelData.description
                    subtitle: modelData.bluetooth ? I18n.tr("Bluetooth") : ""
                    onClicked: sound.setDefaultOutput(modelData.name)
                    Text {
                        text: modelData.isDefault ? "●" : "○"
                        font { family: Theme.font; pixelSize: Tokens.type.body }
                        color: modelData.isDefault ? Theme.accent : Theme.subtext
                    }
                }
            }

            SectionLabel { visible: root.mic !== null; width: parent.width; text: I18n.tr("Input") }
            Item {
                visible: root.mic !== null
                width: parent.width; height: 64
                Text {
                    anchors.left: parent.left; anchors.leftMargin: Tokens.space.md; y: 6
                    width: parent.width - 100
                    text: root.mic ? root.mic.description : ""; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                    font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.Medium }
                    color: Theme.text
                }
                Button {
                    anchors { right: parent.right; top: parent.top }
                    height: 28
                    kind: "text"
                    text: root.mic && root.mic.muted ? I18n.tr("Unmute") : I18n.tr("Mute")
                    onClicked: sound.setInputMuted(root.mic.name, !root.mic.muted)
                }
                SliderBar {
                    x: Tokens.space.md; y: 34
                    width: parent.width - 2 * Tokens.space.md
                    value: root.mic && !root.mic.muted ? root.mic.volume / 100 : 0
                    onMoved: (v) => sound.setInputVolume(root.mic.name, Math.round(v * 100))
                }
            }

            SectionLabel { visible: sound.apps.length > 0; width: parent.width; text: I18n.tr("Apps") }
            Repeater {
                model: sound.apps
                delegate: Item {
                    required property var modelData
                    width: parent.width; height: 64
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: Tokens.space.md; y: 6
                        width: parent.width - 100
                        text: modelData.paused ? I18n.f("%1 · paused", modelData.name) : modelData.name; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                        font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.Medium }
                        color: Theme.text
                    }
                    Button {
                        anchors { right: parent.right; top: parent.top }
                        height: 28
                        kind: "text"
                        text: modelData.muted ? I18n.tr("Unmute") : I18n.tr("Mute")
                        onClicked: sound.setAppMuted(modelData.index, !modelData.muted)
                    }
                    SliderBar {
                        x: Tokens.space.md; y: 34
                        width: parent.width - 2 * Tokens.space.md
                        value: modelData.muted ? 0 : modelData.volume / 100
                        onMoved: (v) => sound.setAppVolume(modelData.index, Math.round(v * 100))
                    }
                }
            }
        }
    }
}
