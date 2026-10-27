import QtQuick
import AetherShared
import "."

// Battery & power mode (docs/PANELS-SPEC.md section 8): state from UPower, mode from
// power-profiles-daemon. Both are signals, so the panel never polls.
PanelScaffold {
    id: root
    property string page: ""
    signal pageRequested(string page)
    signal closeRequested()
    title: "Battery"
    subtitle: power.hasBattery ? power.timeText : "No battery"
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Button { kind: "text"; text: "Power settings ↗"; x: 14; anchors.verticalCenter: parent.verticalCenter
                onClicked: { power.openSettings(); root.closeRequested() } }
        }
    ]
    Component.onCompleted: power.refresh()

    readonly property var names: ({ "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" })
    readonly property var blurbs: ({
        "power-saver": "Longest battery life, reduced performance",
        "balanced": "Good performance, normal battery life",
        "performance": "Fastest, uses more power and runs warmer"
    })

    Column {
        x: 22; width: parent.width - 44
        spacing: Tokens.space.xs
        Rectangle {
            visible: power.hasBattery
            width: parent.width; height: 92
            radius: Tokens.radius.lg
            color: Qt.rgba(1, 1, 1, Tokens.tint.subtle)
            Text {
                x: Tokens.space.lg; y: Tokens.space.md
                text: power.percent + "%"
                font { family: Theme.mono; pixelSize: Tokens.type.display; weight: Font.Medium }
                color: power.percent <= 10 && power.state === "discharging" ? Tokens.role.island.negative : Theme.text
            }
            Text {
                anchors { right: parent.right; rightMargin: Tokens.space.lg; top: parent.top; topMargin: Tokens.space.lg }
                horizontalAlignment: Text.AlignRight
                text: (power.state === "charging" ? "Charging" : power.state === "discharging" ? "On battery" : power.state === "full" ? "Full" : "")
                      + (power.watts > 0.5 ? " · " + Math.round(power.watts) + " W" : "")
                font { family: Theme.font; pixelSize: Tokens.type.label }
                color: Theme.subtext
            }
            Rectangle {   // charge bar: a thin pill, the one place accent may be large-ish
                x: Tokens.space.lg; y: parent.height - 22
                width: parent.width - 2 * Tokens.space.lg; height: 6; radius: 3
                color: Qt.rgba(1, 1, 1, Tokens.tint.soft)
                Rectangle {
                    width: Math.max(parent.height, parent.width * power.percent / 100); height: parent.height; radius: 3
                    color: power.state === "charging" ? Theme.accent : Theme.text
                    Behavior on width { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
                }
            }
        }
        SectionLabel { visible: power.profiles.length > 0; width: parent.width; text: "Power mode" }
        SegmentedControl {
            visible: power.profiles.length > 0
            width: parent.width
            model: power.profiles.map(p => root.names[p] || p)
            currentIndex: Math.max(0, power.profiles.indexOf(power.profile))
            onActivated: (i) => power.setProfile(power.profiles[i])
        }
        Text {
            visible: power.profile.length > 0
            width: parent.width; topPadding: Tokens.space.xs; wrapMode: Text.Wrap
            text: (root.blurbs[power.profile] || "") + (power.profile === "performance" && power.degraded ? " · limited by heat" : "")
            font { family: Theme.font; pixelSize: Tokens.type.caption }
            color: Theme.subtext
        }
        KeyValueRow { visible: power.health >= 0; width: parent.width; key: "Battery health"; copyable: false; value: power.health + " %" }
        Item { width: 1; height: Tokens.space.sm }
    }
}
