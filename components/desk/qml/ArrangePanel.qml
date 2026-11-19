import QtQuick
import AetherShared

// The desktop's right click: the glass arrange panel, opened by Folder View (through the
// bridge) at the pointer. Flow packs every icon into one direction - rows from the top,
// columns hugging the right or the left edge; sort picks the key, its direction and whether
// folders lead. Every control writes Folder View's own settings through the desk, so the
// desktop re-flows at once and the choice survives; "free" hands the icons back to wherever
// they were dragged. Shift + right click keeps Plasma's own menu one click away.
Item {
    id: panel
    property bool open: false
    signal glassChanged()

    readonly property var grid: desk.grid
    readonly property int flowIndex: grid.arrangement === 0 ? 0 : (grid.alignment === 1 ? 2 : 1)
    // Folder View stores KDirModel's columns (name 0, size 1, date 2, type 6); -1 is manual
    // placement and lights none of the segments
    readonly property var sortToSegment: ({ "-1": -1, "0": 0, "1": 1, "6": 2, "2": 3 })
    readonly property int sortIndex: sortToSegment[String(grid.sortMode)] !== undefined ? sortToSegment[String(grid.sortMode)] : -1
    readonly property var sortNames: [I18n.tr("Name"), I18n.tr("Size"), I18n.tr("Type"), I18n.tr("Date")]
    readonly property var flowNames: [I18n.tr("Top"), I18n.tr("Right"), I18n.tr("Left")]
    readonly property string subtitle: sortIndex === -1 ? I18n.tr("Free placement")
        : I18n.f("%1 · %2", flowNames[flowIndex], sortNames[sortIndex])

    width: 372
    height: body.implicitHeight + 2 * 14

    // at the pointer, clamped inside the screen; a second click on the same spot shuts it
    function openAt(x, y) {
        const px = Math.max(12, Math.min(x - width / 2, parent.width - width - 12));
        const py = Math.max(12, Math.min(y + 8, parent.height - height - 12));
        if (open && Math.abs(px - panel.x) < 8 && Math.abs(py - panel.y) < 8) {
            closePanel();
            return;
        }
        panel.x = px;
        panel.y = py;
        open = true;
    }
    function closePanel() {
        open = false;
    }

    // The desk's surface must not mirror (Folder View's grid is set by its own settings), but
    // this panel speaks the island's language, so it mirrors on its own.
    LayoutMirroring.enabled: I18n.rtl
    LayoutMirroring.childrenInherit: true

    opacity: open ? 1 : 0
    scale: open ? 1 : 0.94
    visible: opacity > 0.01
    Behavior on opacity {
        NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter }
    }
    Behavior on scale {
        NumberAnimation { duration: Tokens.motion.duration.morph; easing.type: Tokens.motion.easing.spring }
    }
    onOpenChanged: glassChanged()
    onXChanged: glassChanged()
    onYChanged: glassChanged()

    // the milky glass: body gradient, rim and grain, blurred behind by the desk (glassChanged)
    CardSurface { anchors.fill: parent }

    // right click on the panel itself shuts it
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: panel.closePanel()
    }

    Column {
        id: body
        x: 14
        y: 14
        width: parent.width - 28
        spacing: Tokens.space.sm

        Item {   // header: title over the live state line, a quiet ✕ at the far end
            width: parent.width
            height: 44
            Column {
                anchors {
                    left: parent.left
                    right: closeX.left
                    rightMargin: Tokens.space.sm
                    verticalCenter: parent.verticalCenter
                }
                Text {
                    width: parent.width
                    text: I18n.tr("Arrange desktop")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: Tokens.type.title; weight: Font.DemiBold }
                    color: Theme.text
                }
                Text {
                    width: parent.width
                    text: panel.subtitle
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: Tokens.type.label }
                    color: Theme.subtext
                }
            }
            Text {
                id: closeX
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                font { family: Theme.font; pixelSize: 16 }
                color: closeXHover.hovered ? Theme.text : Theme.subtext
                HoverHandler { id: closeXHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: panel.closePanel() }
            }
        }

        SectionLabel { width: parent.width; text: I18n.tr("Pack to") }
        SegmentedControl {
            width: parent.width
            model: panel.flowNames
            currentIndex: panel.flowIndex
            onActivated: (i) => desk.arrange(i)
        }

        SectionLabel { width: parent.width; text: I18n.tr("Sort by") }
        SegmentedControl {
            width: parent.width
            model: panel.sortNames
            currentIndex: panel.sortIndex
            onActivated: (i) => desk.sort(i, panel.grid.sortDesc, panel.grid.sortDirsFirst)
        }

        Row {   // direction, only while a sort key is picked
            visible: panel.sortIndex !== -1
            width: parent.width
            height: visible ? 36 : 0
            spacing: Tokens.space.md
            Text {
                width: 72
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Direction")
                textFormat: Text.PlainText
                font { family: Theme.font; pixelSize: Tokens.type.label }
                color: Theme.subtext
            }
            SegmentedControl {
                width: parent.width - 72 - Tokens.space.md
                model: [I18n.tr("Ascending"), I18n.tr("Descending")]
                currentIndex: panel.grid.sortDesc ? 1 : 0
                onActivated: (i) => desk.sort(panel.sortIndex, i === 1, panel.grid.sortDirsFirst)
            }
        }

        ListRow {
            width: parent.width
            title: I18n.tr("Folders first")
            Switch {
                enabled: panel.sortIndex !== -1
                checked: panel.grid.sortDirsFirst
                onToggled: (c) => desk.sort(panel.sortIndex, panel.grid.sortDesc, c)
            }
        }

        Item {   // the free order hand-off and the stock menu hint, at the two ends
            width: parent.width
            height: 34
            Button {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                kind: "text"
                text: I18n.tr("Free order")
                onClicked: desk.freeSort()
            }
            Text {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                text: I18n.tr("Shift + right-click: Plasma menu")
                textFormat: Text.PlainText
                font { family: Theme.font; pixelSize: Tokens.type.caption }
                color: Theme.subtext
                opacity: 0.8
            }
        }
    }
}
