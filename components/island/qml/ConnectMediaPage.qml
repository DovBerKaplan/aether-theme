import QtQuick
import AetherShared
import "."

// Phone media page of the Connect panel: what the phone plays, with transport, seek, volume and player.
// The progress ticks locally while it plays; each daemon update re-syncs it.
Column {
    id: mediaCol
    property var d: ({})
    readonly property var pm: connectModel.phoneMedia
    spacing: Tokens.space.md
    property int pos: 0
    Connections { target: connectModel; function onPhoneMediaChanged() { mediaCol.pos = pm.position || 0 } }
    Timer { running: visible && pm.playing === true; interval: 1000; repeat: true; onTriggered: mediaCol.pos = Math.min(pm.length || 0, mediaCol.pos + 1000) }
    Item {
        visible: pm.available !== true
        width: parent.width; height: 150
        Column {
            anchors.centerIn: parent
            spacing: Tokens.space.md
            Glyph { anchors.horizontalCenter: parent.horizontalCenter; name: "play"; size: 32; color: Theme.subtext }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (d.id !== undefined) ? I18n.f("Nothing is playing on %1", d.name) : ""; textFormat: Text.PlainText
                font { family: Theme.font; pixelSize: Tokens.type.body }
                color: Theme.subtext
            }
        }
    }
    Rectangle {
        visible: pm.available === true
        width: parent.width; height: mcol.height + 2 * Tokens.space.lg
        radius: Tokens.radius.lg
        color: Qt.rgba(1, 1, 1, Tokens.tint.subtle)
        Column {
            id: mcol
            x: Tokens.space.lg; y: Tokens.space.lg
            width: parent.width - 2 * Tokens.space.lg
            spacing: Tokens.space.md
            Column {
                width: parent.width
                spacing: 2
                Text {
                    width: parent.width; text: pm.title || ""; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                    font { family: Theme.font; pixelSize: Tokens.type.title; weight: Font.DemiBold }
                    color: Theme.text
                }
                Text {
                    width: parent.width; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                    text: [pm.artist, pm.album].filter(x => x && x.length > 0).join("  ·  ")
                    font { family: Theme.font; pixelSize: Tokens.type.label }
                    color: Theme.subtext
                }
            }
            Column {
                visible: (pm.length || 0) > 0
                width: parent.width
                spacing: 2
                LayoutMirroring.enabled: false      // progress and its times keep their direction, as on the media card
                LayoutMirroring.childrenInherit: true
                SliderBar {
                    mirrored: false
                    width: parent.width
                    enabled: pm.canSeek === true
                    value: (pm.length || 0) > 0 ? mediaCol.pos / pm.length : 0
                    onMoved: (v) => connectModel.mediaSeek(d.id, v)
                }
                Item {
                    width: parent.width; height: 16
                    function mmss(ms) { const s = Math.floor(ms / 1000); return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60) }
                    Text { anchors.left: parent.left; text: parent.mmss(mediaCol.pos); font { family: Theme.mono; pixelSize: Tokens.type.caption } color: Theme.subtext }
                    Text { anchors.right: parent.right; text: parent.mmss(pm.length || 0); font { family: Theme.mono; pixelSize: Tokens.type.caption } color: Theme.subtext }
                }
            }
            Row {      // transport: previous, play/pause, next (these stay left-to-right, as on the media card)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Tokens.space.xl
                LayoutMirroring.enabled: false
                Repeater {
                    model: [{ g: "prev", a: "Previous" }, { g: pm.playing ? "pause" : "play", a: "PlayPause" }, { g: "next", a: "Next" }]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: index === 1 ? 56 : 44; height: width; radius: width / 2
                        color: index === 1 ? Tokens.role.island.hero : Qt.rgba(1, 1, 1, tTap.pressed ? Tokens.tint.strong : tHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                        anchors.verticalCenter: parent.verticalCenter
                        Glyph { anchors.centerIn: parent; name: modelData.g; size: index === 1 ? 22 : 18; color: index === 1 ? Tokens.role.dark.surfaceSunken : Theme.text }
                        HoverHandler { id: tHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: tTap; onTapped: connectModel.mediaAction(d.id, modelData.a) }
                    }
                }
            }
            Row {
                width: parent.width
                spacing: Tokens.space.md
                Glyph { name: "volume-2"; size: 18; anchors.verticalCenter: parent.verticalCenter }
                SliderBar {
                    width: parent.width - 18 - Tokens.space.md
                    anchors.verticalCenter: parent.verticalCenter
                    value: (pm.volume || 0) / 100
                    onMoved: (v) => connectModel.mediaVolume(d.id, Math.round(v * 100))
                }
            }
            SegmentedControl {
                visible: (pm.players || []).length > 1
                width: parent.width
                model: pm.players || []
                currentIndex: Math.max(0, (pm.players || []).indexOf(pm.player))
                onActivated: (i) => connectModel.mediaPlayer(d.id, pm.players[i])
            }
        }
    }
    Item { width: 1; height: Tokens.space.sm }
}
