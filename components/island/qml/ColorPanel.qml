import QtQuick
import AetherShared
import "."

// Color panel: the accent the island uses for the few things that glow - and, in a small dose, the glass.
// A row of swatches for the quick choice, a hue bar and a brightness bar for the exact one. The saved
// choice lives in TileStore (accentHue / accentLight); the island reads it into Theme.accentOverride.
PanelScaffold {
    id: root
    property string page: ""
    title: I18n.tr("Color")
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Button { kind: "text"; text: I18n.tr("Reset"); enabled: tiles.accentCustom; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                onClicked: tiles.resetAccent() }
        }
    ]

    readonly property var presets: [183, 215, 265, 325, 5, 28, 48, 140]     // cyan, blue, violet, pink, red, orange, yellow, green
    function swatch(h, l, sat) { return Qt.hsla(h / 360, sat === undefined ? tiles.accentSat : sat, l, 1) }

    Column {
        x: 22; width: parent.width - 44
        spacing: Tokens.space.md
        Row {      // preview: what the accent looks like on a small switch and a pill
            width: parent.width; height: 40
            spacing: Tokens.space.md
            Rectangle { width: 40; height: 40; radius: 12; color: Theme.accent }
            Rectangle {
                width: 74; height: 24; radius: 12; anchors.verticalCenter: parent.verticalCenter
                color: Theme.veil(Tokens.tint.subtle)
                Rectangle { x: 38; y: 3; width: 34; height: 18; radius: 9; color: Theme.accent }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tiles.accentCustom ? I18n.tr("Your color") : I18n.tr("Theme color")
                font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
                color: Theme.subtext
            }
        }
        Row {      // swatches
            width: parent.width; height: 40
            spacing: (width - 8 * 34) / 7
            Repeater {
                model: root.presets
                delegate: Rectangle {
                    required property int modelData
                    width: 34; height: 34; radius: 17
                    color: root.swatch(modelData, tiles.accentLight)
                    border { width: tiles.accentCustom && Math.abs(tiles.accentHue - modelData) < 6 ? 2 : 0; color: "white" }
                    scale: sTap.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: sTap; onTapped: tiles.setAccent(modelData, tiles.accentLight, tiles.accentSat) }
                }
            }
        }
        SectionLabel { width: parent.width; text: I18n.tr("Hue") }
        Item {
            id: hueBar
            width: parent.width; height: 28
            LayoutMirroring.enabled: false      // a spectrum always runs the same way
            LayoutMirroring.childrenInherit: true
            Rectangle {
                id: hueTrack
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 10; radius: 5
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0 / 6; color: "#ff0000" }
                    GradientStop { position: 1.0 / 6; color: "#ffff00" }
                    GradientStop { position: 2.0 / 6; color: "#00ff00" }
                    GradientStop { position: 3.0 / 6; color: "#00ffff" }
                    GradientStop { position: 4.0 / 6; color: "#0000ff" }
                    GradientStop { position: 5.0 / 6; color: "#ff00ff" }
                    GradientStop { position: 6.0 / 6; color: "#ff0000" }
                }
            }
            Rectangle {
                x: tiles.accentHue / 359 * (hueTrack.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 11
                color: root.swatch(tiles.accentHue, 0.5, 1.0)
                border { width: 2; color: "white" }
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                function set(mx) { tiles.setAccent(Math.round(Math.max(0, Math.min(1, (mx - 11) / (width - 22))) * 359), tiles.accentLight, tiles.accentSat) }
                onPressed: (m) => set(m.x)
                onPositionChanged: (m) => { if (pressed) set(m.x) }
            }
        }
        SectionLabel { width: parent.width; text: I18n.tr("Lightness") }
        Item {
            id: lightBar
            width: parent.width; height: 28
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true
            Rectangle {
                id: lightTrack
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 10; radius: 5
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.swatch(tiles.accentHue, 0.25) }
                    GradientStop { position: 1.0; color: root.swatch(tiles.accentHue, 0.8) }
                }
            }
            Rectangle {
                x: (tiles.accentLight - 0.25) / 0.55 * (lightTrack.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 11
                color: root.swatch(tiles.accentHue, tiles.accentLight)
                border { width: 2; color: "white" }
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                function set(mx) { tiles.setAccent(tiles.accentHue, 0.25 + Math.max(0, Math.min(1, (mx - 11) / (width - 22))) * 0.55, tiles.accentSat) }
                onPressed: (m) => set(m.x)
                onPositionChanged: (m) => { if (pressed) set(m.x) }
            }
        }
        SectionLabel { width: parent.width; text: I18n.tr("Vividness") }
        Item {
            id: satBar
            width: parent.width; height: 28
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true
            Rectangle {
                id: satTrack
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 10; radius: 5
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.swatch(tiles.accentHue, tiles.accentLight, 0.15) }
                    GradientStop { position: 1.0; color: root.swatch(tiles.accentHue, tiles.accentLight, 1.0) }
                }
            }
            Rectangle {
                x: (tiles.accentSat - 0.15) / 0.85 * (satTrack.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 11
                color: root.swatch(tiles.accentHue, tiles.accentLight)
                border { width: 2; color: "white" }
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                function set(mx) { tiles.setAccent(tiles.accentHue, tiles.accentLight, 0.15 + Math.max(0, Math.min(1, (mx - 11) / (width - 22))) * 0.85) }
                onPressed: (m) => set(m.x)
                onPositionChanged: (m) => { if (pressed) set(m.x) }
            }
        }
        Item { width: 1; height: Tokens.space.sm }
    }
}
