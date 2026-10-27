import QtQuick
import AetherShared
import "."

// Display panel (docs/PANELS-SPEC.md section 7): brightness, Night Light, light/dark theme.
PanelScaffold {
    id: root
    property string page: ""
    signal pageRequested(string page)
    signal closeRequested()
    title: "Display"
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Button { kind: "text"; text: "Display settings ↗"; x: 14; anchors.verticalCenter: parent.verticalCenter
                onClicked: { displaySettings.openSettings(); root.closeRequested() } }
        }
    ]
    Component.onCompleted: displaySettings.refresh()

    Column {
        x: 22; width: parent.width - 44
        spacing: Tokens.space.xs
        Row {
            visible: system.brightness >= 0
            width: parent.width; height: 48
            spacing: Tokens.space.md
            Glyph { name: "sun"; size: 20; anchors.verticalCenter: parent.verticalCenter }
            SliderBar {
                width: parent.width - 20 - 44 - 2 * Tokens.space.md
                anchors.verticalCenter: parent.verticalCenter
                value: Math.max(0, system.brightness) / 100
                onMoved: (v) => system.setBrightness(Math.round(v * 100))
            }
            Text {
                width: 44; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight
                text: Math.max(0, system.brightness) + "%"
                font { family: Theme.mono; pixelSize: Tokens.type.body }
                color: Theme.subtext
            }
        }
        ListRow {
            visible: displaySettings.nightAvailable
            width: parent.width
            title: "Night Light"
            subtitle: displaySettings.nightEnabled ? "Warmer colors in the evening" : "Off"
            Switch { checked: displaySettings.nightEnabled; onToggled: (c) => displaySettings.setNightEnabled(c) }
        }
        Row {
            visible: displaySettings.nightAvailable && displaySettings.nightEnabled
            width: parent.width; height: 40
            spacing: Tokens.space.md
            leftPadding: Tokens.space.md
            Text {
                width: 56; anchors.verticalCenter: parent.verticalCenter
                text: "Warmth"
                font { family: Theme.font; pixelSize: Tokens.type.label }
                color: Theme.subtext
            }
            SliderBar {   // left = warmest (1000 K), right = coolest (6500 K)
                width: parent.width - 56 - 2 * Tokens.space.md - Tokens.space.md - 56
                anchors.verticalCenter: parent.verticalCenter
                value: (displaySettings.nightTemperature - 1000) / 5500
                onMoved: (v) => displaySettings.setNightTemperature(Math.round((1000 + v * 5500) / 100) * 100)
            }
            Text {
                width: 56; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight
                text: displaySettings.nightTemperature + " K"
                font { family: Theme.mono; pixelSize: Tokens.type.caption }
                color: Theme.subtext
            }
        }
        SectionLabel { width: parent.width; text: "Theme" }
        SegmentedControl {
            width: parent.width
            model: ["Light", "Dark"]
            currentIndex: displaySettings.dark ? 1 : 0
            onActivated: (i) => displaySettings.setDark(i === 1)
        }
        Item { width: 1; height: Tokens.space.sm }
    }
}
