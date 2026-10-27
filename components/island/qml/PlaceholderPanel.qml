import QtQuick
import AetherShared

// Stand-in until a panel's real page exists: exercises the frame and every shared control.
PanelScaffold {
    id: root
    property string panelId
    property string page
    property bool demoOn: true
    property int demoMode: 1
    showBack: true
    subtitle: "Coming soon · " + panelId
    headerTrailing: [ Switch { checked: root.demoOn; onToggled: (c) => root.demoOn = c } ]
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Button { kind: "text"; text: root.title + " settings ↗"; anchors.verticalCenter: parent.verticalCenter; x: 14 }
            Button { kind: "text"; text: "Scan"; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                onClicked: root.busy = !root.busy }
        }
    ]

    Column {
        width: parent.width
        leftPadding: 22; rightPadding: 22
        readonly property real w: width - 44
        spacing: Tokens.space.xs
        SectionLabel { width: parent.w; text: "Preview" }
        ListRow { width: parent.w; title: "A row"; subtitle: "With a subtitle"; showChevron: true }
        ListRow { width: parent.w; title: "A row with a switch"; Switch { checked: true } }
        SegmentedControl { width: parent.w; model: ["One", "Two", "Three"]; currentIndex: root.demoMode; onActivated: (i) => root.demoMode = i }
        KeyValueRow { width: parent.w; key: "Panel"; value: root.panelId }
    }
}
