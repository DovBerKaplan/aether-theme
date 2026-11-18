import QtQuick
import AetherShared

// The pane's ⋯ menu, drawn inside our own window (a popup surface cannot hang off a
// layer-shell window). A full-window catcher behind it closes it on any outside click.
Item {
    id: menu
    property var shell
    readonly property string gid: shell.menuGid
    visible: gid !== ""
    anchors.fill: parent
    z: 200

    readonly property bool canSplitH: gid !== "" && shell.canSplitPane(gid, "right")
    readonly property bool canSplitV: gid !== "" && shell.canSplitPane(gid, "bottom")
    readonly property var items: [
        { label: I18n.tr("Split right"), act: "right", on: canSplitH },
        { label: I18n.tr("Split down"), act: "bottom", on: canSplitV },
        { label: I18n.tr("Equalize sizes"), act: "equalize", on: shell.groupIds.length > 1 },
        { label: shell.maxGroup === gid ? I18n.tr("Restore size") : I18n.tr("Maximize pane"), act: "max", on: shell.groupIds.length > 1 },
        { label: I18n.tr("Close pane"), act: "close", on: shell.groupIds.length > 1 },
        { label: I18n.tr("Layout"), act: "", on: false, header: true },
        { label: I18n.tr("Single pane"), act: "preset:single", on: shell.groupIds.length > 1 },
        { label: I18n.tr("Two columns"), act: "preset:cols2", on: shell.tabs.length > 1 },
        { label: I18n.tr("Two rows"), act: "preset:rows2", on: shell.tabs.length > 1 },
        { label: I18n.tr("Three columns"), act: "preset:cols3", on: shell.tabs.length > 2 },
        { label: I18n.tr("Main and side"), act: "preset:main-side", on: shell.tabs.length > 2 },
        { label: I18n.tr("Grid 2×2"), act: "preset:grid4", on: shell.tabs.length > 3 }
    ]

    MouseArea { anchors.fill: parent; onPressed: shell.menuGid = "" }

    Rectangle {
        id: card
        x: Math.max(8, Math.min(menu.width - width - 8, shell.menuPos.x - width + 28))
        y: shell.menuPos.y + 4
        width: 190; height: col.implicitHeight + 12
        radius: 14
        // opaque: the terminal windows beneath would otherwise show through the glass tint
        color: Qt.rgba(Theme.bodyBottom.r, Theme.bodyBottom.g, Theme.bodyBottom.b, 1)
        border { width: 1; color: Theme.rim }
        Column {
            id: col
            x: 6; y: 6
            width: parent.width - 12
            Repeater {
                model: menu.items
                Item {
                    required property var modelData
                    width: col.width; height: modelData.header ? 30 : 34
                    opacity: modelData.on || modelData.header ? 1 : 0.35
                    Rectangle {
                        anchors.fill: parent; radius: 9
                        color: Qt.rgba(1, 1, 1, hover.hovered && modelData.on ? Tokens.material.tintHover : 0)
                    }
                    Text {
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        font { family: Theme.font; pixelSize: modelData.header ? Tokens.type.caption : Tokens.type.label
                               weight: modelData.header ? Font.DemiBold : Font.Normal }
                        color: modelData.header ? Theme.subtext : Theme.text
                    }
                    HoverHandler { id: hover; cursorShape: modelData.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { enabled: modelData.on; onTapped: shell.paneAction(menu.gid, modelData.act) }
                }
            }
        }
    }
}
