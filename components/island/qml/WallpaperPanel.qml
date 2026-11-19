import QtQuick
import AetherShared
import "."

// Wallpaper panel: the aether fields, each preview wearing its real shader at card size on the same
// 10 Hz tick the desktops run - so the choice is made on the living thing, in the accent in play.
// A tap moves every desktop over at once (TileStore rides plasmashell's scripting API and the sync
// oneshots hand the new field its accent and mode); the footer's switch lets it rest.
PanelScaffold {
    id: root
    property string page: ""
    title: I18n.tr("Wallpaper")
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Row {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 10
                Switch { checked: tiles.wallpaperAnimate; onToggled: (c) => tiles.setWallpaperAnimate(c) }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Let it live")
                    font { family: Theme.font; pixelSize: Tokens.type.label }
                    color: Theme.subtext
                }
            }
        }
    ]

    // One clock for every preview: 10 Hz, like the wallpapers themselves; nothing repaints faster,
    // and the whole panel is torn down shortly after the island closes anyway.
    property real time: 0
    property real startedAt: Date.now()
    Timer {
        interval: 100
        repeat: true
        running: root.visible
        onTriggered: root.time = ((Date.now() - root.startedAt) / 1000) % 100000
    }

    Column {
        x: 22; width: parent.width - 44
        spacing: Tokens.space.md

        Grid {
            columns: 2
            spacing: 12
            width: parent.width

            Repeater {
                model: tiles.wallpapers
                delegate: Item {
                    id: entry
                    required property var modelData
                    readonly property bool chosen: tiles.wallpaperStyle === modelData.id
                    width: (parent.width - parent.spacing) / 2
                    height: card.height + 28

                    Rectangle {
                        id: card
                        width: parent.width; height: 118
                        radius: 16
                        color: "black"
                        clip: true
                        border { width: entry.chosen ? 2 : 0; color: "white" }   // the swatch's signature
                        scale: tap.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }

                        ShaderEffect {
                            anchors.fill: parent
                            fragmentShader: Qt.resolvedUrl("assets/wallpapers/" + entry.modelData.shader + ".frag.qsb")
                            property color accent: Theme.accent
                            property real dark: displaySettings.dark ? 1 : 0
                            property real aspect: width / Math.max(1, height)
                            property real px: 1 / Math.max(1, height)
                            property real time: root.time
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: tap; onTapped: tiles.setWallpaper(entry.modelData.id) }
                    }
                    Text {
                        anchors { top: card.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                        text: I18n.tr(entry.modelData.title)
                        font { family: Theme.font; pixelSize: Tokens.type.label; weight: entry.chosen ? Font.Medium : Font.Normal }
                        color: entry.chosen ? Theme.text : Theme.subtext
                    }
                }
            }
        }
        Item { width: 1; height: Tokens.space.sm }
    }
}
