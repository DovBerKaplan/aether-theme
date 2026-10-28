import QtQuick
import AetherShared
import "."

// The tile set. Normal: pages of 8 (4 x 2) with dots when there is more than one page.
// Editing: every tile is shown at once; drag one onto another slot to reorder, tap the minus
// badge to remove it, tap a tile in I18n.tr("Available") to add it. Every change is saved at once.
Item {
    id: root
    property bool editing: false
    signal panelRequested(string id)
    signal closeRequested()
    signal doneRequested()

    readonly property int cols: 4
    readonly property int gap: 10
    readonly property int cellH: 58
    readonly property real cellW: (width - (cols - 1) * gap) / cols
    function colX(c) { const x = c * (cellW + gap); return I18n.rtl ? width - cellW - x : x }
    readonly property int perPage: 8
    readonly property int count: work.count
    readonly property int pages: Math.max(1, Math.ceil(count / perPage))
    readonly property int pageRows: Math.max(1, Math.min(2, Math.ceil(Math.min(count, perPage) / cols)))
    readonly property real pagerH: pageRows * cellH + (pageRows - 1) * gap
    readonly property real editRows: Math.max(1, Math.ceil(count / cols))
    readonly property real gridH: editRows * cellH + (editRows - 1) * gap
    readonly property var available: {
        const used = {}
        for (let i = 0; i < work.count; ++i) used[work.get(i).tid] = true
        return tiles.catalog.filter(c => !used[c.id])
    }

    implicitHeight: editing ? editCol.implicitHeight : pagerH + (pages > 1 ? 18 : 0)
    Behavior on implicitHeight { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }

    // The working copy of the order; the store is the saved one.
    ListModel { id: work }
    function load() {
        work.clear()
        for (const id of tiles.order) work.append({ tid: id })
    }
    function save() {
        const ids = []
        for (let i = 0; i < work.count; ++i) ids.push(work.get(i).tid)
        tiles.setOrder(ids)
    }
    function removeAt(i) { work.remove(i); save() }
    function addId(id) { work.append({ tid: id }); save() }   // see WidgetStack: the delegate dies with its row
    Component.onCompleted: load()
    Connections { target: tiles; function onOrderChanged() { if (!root.editing) root.load() } }
    onEditingChanged: if (!editing) load()

    // ---- normal mode: pages ------------------------------------------------------------
    ListView {
        id: pager
        visible: !root.editing
        width: parent.width; height: root.pagerH
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        interactive: root.pages > 1
        clip: true
        model: root.pages
        delegate: Item {
            required property int index
            width: pager.width; height: pager.height
            Repeater {
                model: Math.min(root.perPage, root.count - index * root.perPage)
                delegate: Tile {
                    required property int index
                    readonly property int slot: index
                    tileId: work.get(parent.index * root.perPage + slot).tid
                    host: root
                    x: root.colX(slot % root.cols)
                    y: Math.floor(slot / root.cols) * (root.cellH + root.gap)
                    width: root.cellW; height: root.cellH
                }
            }
        }
    }
    Row {
        visible: !root.editing && root.pages > 1
        anchors { horizontalCenter: parent.horizontalCenter; top: pager.bottom; topMargin: 8 }
        spacing: 6
        Repeater {
            model: root.pages
            Rectangle {
                required property int index
                width: index === pager.currentIndex ? 14 : 5; height: 5; radius: 2.5
                color: index === pager.currentIndex ? Theme.text : Theme.subtext
                opacity: index === pager.currentIndex ? 0.9 : 0.5
                Behavior on width { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }
            }
        }
    }

    // Two-finger swipe on the touchpad (or a sideways wheel): one step per gesture, not per event.
    WheelHandler {
        id: swipe
        orientation: Qt.Horizontal
        target: pager; enabled: root.pages > 1 && !root.editing
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        property real acc: 0
        property bool cooling: false
        onWheel: (e) => {
            const d = Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y) ? e.angleDelta.x : 0
            if (d === 0) return
            if (cooling) { cool.restart(); return }
            acc += d
            if (Math.abs(acc) < 90) return
            const dir = (acc < 0) !== I18n.rtl ? 1 : -1
            pager.currentIndex = Math.max(0, Math.min(root.pages - 1, pager.currentIndex + dir))
            acc = 0; cooling = true; cool.restart()
        }
    }
    Timer { id: cool; interval: 280; onTriggered: { swipe.cooling = false; swipe.acc = 0 } }

    // ---- edit mode ----------------------------------------------------------------------
    // Nothing in edit mode may fall through to the island's click-outside-to-close area: a drag
    // released on a tile, or a tap on dead space, would fold the island mid-edit.
    MouseArea { visible: root.editing; anchors.fill: parent }
    Column {
        id: editCol
        visible: root.editing
        width: parent.width
        spacing: Tokens.space.md

        Item {
            id: gridArea
            width: parent.width; height: root.gridH
            property int target: -1            // slot under the dragged tile, -1 when none
            function slotAt(px, py) {
                const c = Math.max(0, Math.min(root.cols - 1, Math.floor((I18n.rtl ? root.width - px : px) / (root.cellW + root.gap))))
                const r = Math.max(0, Math.min(root.editRows - 1, Math.floor(py / (root.cellH + root.gap))))
                return Math.min(root.count - 1, r * root.cols + c)
            }
            Rectangle {      // where the dragged tile will land
                visible: gridArea.target >= 0
                x: root.colX(gridArea.target % root.cols)
                y: Math.floor(gridArea.target / root.cols) * (root.cellH + root.gap)
                width: root.cellW; height: root.cellH; radius: Tokens.radius.xl
                color: "transparent"
                border { width: 2; color: Theme.accent }
                Behavior on x { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }
                Behavior on y { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }
            }
            Repeater {
                model: work
                delegate: Item {
                    id: slotItem
                    required property int index
                    required property string tid
                    x: root.colX(index % root.cols)
                    y: Math.floor(index / root.cols) * (root.cellH + root.gap)
                    width: root.cellW; height: root.cellH
                    z: held.dragging ? 10 : 0
                    Behavior on x { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
                    Behavior on y { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }

                    Item {
                        id: held
                        property bool dragging: drag.active
                        width: parent.width; height: parent.height
                        scale: dragging ? 1.06 : 1
                        opacity: dragging ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
                        Behavior on x { enabled: !held.dragging; NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
                        Behavior on y { enabled: !held.dragging; NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
                        Tile { anchors.fill: parent; tileId: slotItem.tid; host: root; editing: true }
                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton }
                        DragHandler {
                            id: drag
                            target: held
                            onActiveChanged: {
                                if (active) return
                                const to = gridArea.target
                                gridArea.target = -1
                                held.x = 0; held.y = 0
                                if (to >= 0 && to !== slotItem.index) { work.move(slotItem.index, to, 1); root.save() }
                            }
                            onTranslationChanged: if (active)
                                gridArea.target = gridArea.slotAt(slotItem.x + held.x + held.width / 2, slotItem.y + held.y + held.height / 2)
                        }
                        HoverHandler { cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
                    }
                    Rectangle {      // remove badge
                        visible: root.count > 1 && !held.dragging
                        x: I18n.rtl ? -4 : parent.width - width + 4; y: -4
                        width: 20; height: 20; radius: 10
                        color: Theme.chip
                        border { width: 1; color: Theme.rim }
                        Glyph { anchors.centerIn: parent; name: "minus"; size: 12 }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.removeAt(slotItem.index) }
                    }
                }
            }
        }

        SectionLabel { visible: root.available.length > 0; width: parent.width; text: I18n.tr("Available") }
        Flow {
            visible: root.available.length > 0
            width: parent.width
            spacing: Tokens.space.sm
            Repeater {
                model: root.available
                delegate: Rectangle {
                    required property var modelData
                    height: 34; width: chipRow.width + 2 * Tokens.space.md; radius: height / 2
                    color: Qt.rgba(1, 1, 1, addTap.pressed ? Tokens.tint.strong : addHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Tokens.space.sm
                        Glyph { name: "plus"; size: 12; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: modelData.label; textFormat: Text.PlainText
                            font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
                            color: Theme.text; anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: addTap; onTapped: root.addId(modelData.id) }
                }
            }
        }
        Row {
            spacing: Tokens.space.sm
            Button { kind: "filled"; text: I18n.tr("Done"); onClicked: root.doneRequested() }
            Button { kind: "text"; text: I18n.tr("Reset"); onClicked: { tiles.reset(); root.load() } }
        }
    }
}
